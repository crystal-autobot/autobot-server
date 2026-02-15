require "json"
require "socket"
require "file_utils"

module AutobotServer
  struct Request
    include JSON::Serializable

    getter id : String
    getter op : String
    getter path : String?
    getter content : String?
    getter command : String?
    getter stdin : String?
    getter timeout : Int32?
  end

  struct Response
    include JSON::Serializable

    getter id : String
    getter status : String
    getter data : String?
    getter error : String?
    getter exit_code : Int32?

    def initialize(@id : String, @status : String, @data : String? = nil, @error : String? = nil, @exit_code : Int32? = nil)
    end
  end

  class Server
    TIMEOUT_EXIT_CODE    =    124
    MAX_OUTPUT_SIZE      = 10_000
    IO_BUFFER_SIZE       =   4096
    SIGNAL_GRACE_PERIOD  = 0.5.seconds
    DEFAULT_EXEC_TIMEOUT = 60

    def initialize(@socket_path : String, @workspace : String)
      @running = true
    end

    def run : Nil
      File.delete(@socket_path) if File.exists?(@socket_path)

      server = UNIXServer.new(@socket_path)
      STDERR.puts "Sandbox server listening on #{@socket_path}"

      client = server.accept
      STDERR.puts "Client connected"

      while @running && (line = client.gets)
        handle_request(line, client)
      end

      client.close
      server.close
      File.delete(@socket_path) if File.exists?(@socket_path)
    end

    private def handle_request(line : String, client : UNIXSocket) : Nil
      request = Request.from_json(line)
      STDERR.puts "Received request: #{request.id} - #{request.op}"

      response = case request.op
                 when "read_file"
                   handle_read_file(request)
                 when "write_file"
                   handle_write_file(request)
                 when "list_dir"
                   handle_list_dir(request)
                 when "exec"
                   handle_exec(request)
                 else
                   Response.new(
                     id: request.id,
                     status: "error",
                     error: "Unknown operation: #{request.op}"
                   )
                 end

      client.puts(response.to_json)
      client.flush
    rescue ex
      STDERR.puts "Error handling request: #{ex.message}"
      error_response = Response.new(
        id: "error",
        status: "error",
        error: ex.message
      )
      client.puts(error_response.to_json)
      client.flush
    end

    private def handle_read_file(request : Request) : Response
      path = request.path
      return error_response(request.id, "Missing path") unless path

      full_path = resolve_path(path)

      unless File.exists?(full_path)
        return error_response(request.id, "File not found: #{path}")
      end

      unless File.file?(full_path)
        return error_response(request.id, "Path is not a file: #{path}")
      end

      content = File.read(full_path)
      Response.new(id: request.id, status: "ok", data: content)
    rescue ex
      error_response(request.id, "Cannot read file: #{ex.message}")
    end

    private def handle_write_file(request : Request) : Response
      path = request.path
      content = request.content

      return error_response(request.id, "Missing path") unless path
      return error_response(request.id, "Missing content") unless content

      full_path = resolve_path(path)

      dir = File.dirname(full_path)
      Dir.mkdir_p(dir) unless Dir.exists?(dir)

      File.write(full_path, content)
      Response.new(
        id: request.id,
        status: "ok",
        data: "Wrote #{content.bytesize} bytes"
      )
    rescue ex
      error_response(request.id, "Cannot write file: #{ex.message}")
    end

    private def handle_list_dir(request : Request) : Response
      path = request.path
      return error_response(request.id, "Missing path") unless path

      full_path = resolve_path(path)

      unless Dir.exists?(full_path)
        return error_response(request.id, "Directory not found: #{path}")
      end

      entries = Dir.entries(full_path)
        .reject { |e| e == "." || e == ".." }
        .sort!

      if entries.empty?
        return Response.new(id: request.id, status: "ok", data: "Directory is empty")
      end

      items = entries.map do |entry|
        full = File.join(full_path, entry)
        prefix = Dir.exists?(full) ? "[dir]  " : "[file] "
        "#{prefix}#{entry}"
      end

      Response.new(id: request.id, status: "ok", data: items.join("\n"))
    rescue ex
      error_response(request.id, "Cannot list directory: #{ex.message}")
    end

    private def handle_exec(request : Request) : Response
      command = request.command
      return error_response(request.id, "Missing command") unless command

      timeout = request.timeout || DEFAULT_EXEC_TIMEOUT

      status, stdout, stderr = exec_with_timeout(command, timeout)

      parts = [] of String
      parts << stdout unless stdout.empty?
      parts << "STDERR:\n#{stderr}" unless stderr.empty?

      if !status.success? && status.exit_code != TIMEOUT_EXIT_CODE
        parts << "\nExit code: #{status.exit_code}"
      end

      data = parts.empty? ? "[no output]" : parts.join("\n")

      Response.new(
        id: request.id,
        status: "ok",
        data: data,
        exit_code: status.exit_code
      )
    rescue ex
      error_response(request.id, "Cannot execute command: #{ex.message}")
    end

    private def exec_with_timeout(command : String, timeout : Int32) : {Process::Status, String, String}
      stdout_read, stdout_write = IO.pipe
      stderr_read, stderr_write = IO.pipe

      process = Process.new(
        "sh",
        ["-c", command],
        output: stdout_write,
        error: stderr_write,
        chdir: @workspace
      )

      stdout_write.close
      stderr_write.close

      stdout_channel = Channel(String).new(1)
      stderr_channel = Channel(String).new(1)

      spawn { stdout_channel.send(read_limited_output(stdout_read, MAX_OUTPUT_SIZE)) }
      spawn { stderr_channel.send(read_limited_output(stderr_read, MAX_OUTPUT_SIZE)) }

      completed = Channel(Process::Status).new(1)
      spawn do
        status = process.wait
        completed.send(status)
      end

      status = wait_for_process(process, completed, timeout)

      stdout_text = stdout_channel.receive
      stderr_text = stderr_channel.receive

      stdout_read.close
      stderr_read.close

      {status, stdout_text, stderr_text}
    end

    private def read_limited_output(io : IO, max_size : Int32) : String
      buffer = IO::Memory.new
      bytes_read = 0
      chunk = Bytes.new(IO_BUFFER_SIZE)

      while (n = io.read(chunk)) > 0
        bytes_read += n
        if bytes_read > max_size
          buffer.write(chunk[0, Math.max(0, max_size - (bytes_read - n))])
          buffer << "\n... (output truncated at #{max_size} bytes)"
          break
        end
        buffer.write(chunk[0, n])
      end

      buffer.to_s
    rescue
      ""
    end

    private def wait_for_process(
      process : Process,
      completed : Channel(Process::Status),
      timeout : Int32,
    ) : Process::Status
      select
      when status = completed.receive
        status
      when timeout(timeout.seconds)
        begin
          process.signal(Signal::TERM)
          sleep SIGNAL_GRACE_PERIOD
          process.signal(Signal::KILL) unless process.terminated?
          status = process.wait
          status
        rescue
          Process::Status.new(TIMEOUT_EXIT_CODE)
        end
      end
    end

    private def resolve_path(path : String) : String
      # Security: Reject absolute paths and parent directory traversal
      if Path[path].absolute?
        raise "Absolute paths not allowed"
      end

      if path.includes?("..") || path.starts_with?("../")
        raise "Parent directory traversal not allowed"
      end

      full_path = File.join(@workspace, path)
      Path[full_path].normalize.to_s
    end

    private def error_response(id : String, message : String) : Response
      Response.new(id: id, status: "error", error: message)
    end
  end

  def self.run(socket_path : String, workspace : String)
    server = Server.new(socket_path, workspace)
    server.run
  end
end

# Only run main if not running specs
unless PROGRAM_NAME.includes?("crystal-run-spec")
  if ARGV.size != 2
    STDERR.puts "Usage: autobot-server <socket_path> <workspace>"
    exit 1
  end

  AutobotServer.run(ARGV[0], ARGV[1])
end

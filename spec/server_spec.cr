require "./spec_helper"
require "file_utils"

describe AutobotServer do
  describe "Request" do
    it "deserializes from JSON" do
      json = %q({"id":"req-1","op":"read_file","path":"test.txt"})
      request = AutobotServer::Request.from_json(json)

      request.id.should eq("req-1")
      request.op.should eq("read_file")
      request.path.should eq("test.txt")
    end

    it "handles optional fields" do
      json = %q({"id":"req-2","op":"exec","command":"ls","timeout":30})
      request = AutobotServer::Request.from_json(json)

      request.id.should eq("req-2")
      request.op.should eq("exec")
      request.command.should eq("ls")
      request.timeout.should eq(30)
    end
  end

  describe "Response" do
    it "serializes to JSON" do
      response = AutobotServer::Response.new(
        id: "req-1",
        status: "ok",
        data: "file contents"
      )

      json = response.to_json
      json.should contain("req-1")
      json.should contain("ok")
      json.should contain("file contents")
    end

    it "handles error responses" do
      response = AutobotServer::Response.new(
        id: "req-2",
        status: "error",
        error: "File not found"
      )

      response.to_json.should contain("error")
      response.to_json.should contain("File not found")
    end
  end

  describe "Server security" do
    it "constructs with workspace path" do
      workspace = File.join(Dir.tempdir, "autobot-test-#{Random.rand(10000)}")
      Dir.mkdir_p(workspace)

      begin
        server = AutobotServer::Server.new("/tmp/test.sock", workspace)
        server.should_not be_nil
      ensure
        FileUtils.rm_rf(workspace)
      end
    end
  end

  describe "Protocol constants" do
    it "defines expected constants" do
      AutobotServer::Server::TIMEOUT_EXIT_CODE.should eq(124)
      AutobotServer::Server::MAX_OUTPUT_SIZE.should eq(10_000)
      AutobotServer::Server::IO_BUFFER_SIZE.should eq(4096)
      AutobotServer::Server::DEFAULT_EXEC_TIMEOUT.should eq(60)
    end
  end
end

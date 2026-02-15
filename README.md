# autobot-server

High-performance persistent sandbox server for the Autobot AI agent framework.

**Linux only** - Works with bubblewrap for 15x faster file operations.

## Performance

| Platform | Mode | Per Operation |
|----------|------|---------------|
| **Linux** | autobot (default) | ~50ms |
| **Linux** | autobot + autobot-server | ~3ms (15x faster) ✅ |
| **macOS** | autobot (default) | ~50ms |
| **macOS** | autobot-server | Not applicable (Docker overhead) |

## Why Linux Only?

- **Linux + bubblewrap** is very fast (~5ms overhead)
  - autobot-server reduces this to ~3ms → **big win**
- **macOS/Windows + Docker** is slower (~50ms overhead)
  - autobot-server would save ~2ms → **negligible gain**
  - Added complexity not worth it

## Installation (Linux Only)

### Linux AMD64
```bash
curl -L https://github.com/crystal-autobot/sandbox-server/releases/latest/download/autobot-server-linux-amd64 \
  -o /usr/local/bin/autobot-server
chmod +x /usr/local/bin/autobot-server
```

### Linux ARM64
```bash
curl -L https://github.com/crystal-autobot/sandbox-server/releases/latest/download/autobot-server-linux-arm64 \
  -o /usr/local/bin/autobot-server
chmod +x /usr/local/bin/autobot-server
```

## Usage

On Linux, autobot automatically detects and uses autobot-server if installed:

```bash
$ autobot agent  # On Linux with autobot-server installed

✓ Sandbox: bubblewrap (Linux namespaces)
→ Sandbox mode: autobot-server (persistent, ~3ms/op)
```

Manual usage (for testing):
```bash
autobot-server /tmp/socket.sock /path/to/workspace
```

## Protocol

JSON over Unix socket.

### Request Format
```json
{
  "id": "req-1",
  "op": "read_file|write_file|list_dir|exec",
  "path": "/path/to/file",
  "content": "file content",
  "command": "shell command",
  "timeout": 60
}
```

### Response Format
```json
{
  "id": "req-1",
  "status": "ok|error",
  "data": "result data",
  "error": "error message",
  "exit_code": 0
}
```

## Development

```bash
# Build
make build

# Build release binaries for all platforms
make release-all

# Clean
make clean
```

## License

MIT

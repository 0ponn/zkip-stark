# Debugging HTTP/0.9 Error

The error "curl: (1) Received HTTP/0.9 when not allowed" means curl is receiving a response that doesn't start with "HTTP/1.0" or "HTTP/1.1".

## Current Response Format

The response should be:
```
HTTP/1.1 200 OK\r\n
Content-Length: 123\r\n
Content-Type: application/json\r\n
\r\n
{body}
```

## Possible Issues

1. **Missing HTTP version in status line** - Should be `HTTP/1.1`, not just `1.1`
2. **Wrong line endings** - Must use `\r\n`, not just `\n`
3. **Headers not properly formatted** - Each header must end with `\r\n`
4. **Missing empty line** - Must have `\r\n\r\n` between headers and body

## Test Manually

To see what the server is actually sending:

```bash
# Start server
socat TCP-LISTEN:8081,fork,reuseaddr EXEC:'.lake/build/bin/Main 8081' &

# Test with netcat to see raw output
echo -e "GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n" | nc localhost 8081 | od -c
```

This will show the exact bytes being sent.


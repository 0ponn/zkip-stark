# Port 8080 Conflict Resolution

## Current Situation

Port 8080 is currently in use by:
- **Process**: python3
- **PID**: 463414
- **User**: mlayug

## Options

### Option 1: Use a Different Port (Recommended)

This is the safest option - it won't interfere with your existing Python service.

```bash
# Start ZKIP-STARK on port 8081
socat TCP-LISTEN:8081,fork,reuseaddr EXEC:'.lake/build/bin/Main 8081'

# Or use the start script
bash START_SERVICE.sh 8081
```

Then access the service at:
- `http://localhost:8081/health`
- `http://localhost:8081/api/v1/certificate/generate`

### Option 2: Stop the Python Process

If you don't need the Python service running on port 8080:

```bash
# Check what the Python process is doing
ps aux | grep 463414

# Stop it gracefully
kill 463414

# Or force stop if needed
kill -9 463414

# Then start ZKIP-STARK on port 8080
socat TCP-LISTEN:8080,fork,reuseaddr EXEC:'.lake/build/bin/Main'
```

### Option 3: Find and Stop the Python Service Properly

If the Python process is a service you want to manage:

```bash
# Check if it's a systemd service
systemctl list-units | grep python

# Or check if it's running in a screen/tmux session
screen -ls
tmux ls

# Or check if it's a background job
jobs
```

## Recommended: Use Port 8081

Since you already have something running on 8080, the easiest solution is to use port 8081:

```bash
# Build the service (if not already built)
lake build Main

# Start on port 8081
socat TCP-LISTEN:8081,fork,reuseaddr EXEC:'.lake/build/bin/Main 8081'
```

Then test it:
```bash
curl http://localhost:8081/health
```

## Update Documentation

If you use a different port, remember to:
- Update any API documentation
- Update Kubernetes manifests if deploying
- Update any client code that connects to the service


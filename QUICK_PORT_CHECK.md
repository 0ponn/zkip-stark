# Quick Port Check

## Simple Commands to Check Port 8080

### Option 1: Using `ss` (most common on Fedora)
```bash
ss -tuln | grep :8080
```
If nothing is returned, port 8080 is **available**.

### Option 2: Using `lsof`
```bash
lsof -i :8080
```
If nothing is returned, port 8080 is **available**.

### Option 3: Try to connect
```bash
timeout 1 bash -c "echo > /dev/tcp/localhost/8080" 2>&1
```
If it fails (connection refused), port 8080 is **available**.

### Option 4: Use the script
```bash
bash CHECK_PORT.sh 8080
# or
bash check-port-8080.sh
```

## If Port 8080 is Taken

Use a different port when starting the service:

```bash
# Use port 8081
.lake/build/bin/Main 8081

# Or with socat
socat TCP-LISTEN:8081,fork,reuseaddr EXEC:'.lake/build/bin/Main 8081'
```

## Quick Test

Run this to check port 8080:
```bash
ss -tuln | grep :8080 || echo "Port 8080 is available"
```


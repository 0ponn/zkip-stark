# Port Configuration Guide

## Default Port

The ZKIP-STARK API service uses **port 8080** by default.

## Check if Port is Available

```bash
# Use the helper script
./CHECK_PORT.sh 8080

# Or manually check
lsof -i :8080
# or
ss -tuln | grep :8080
```

## Use a Different Port

### Option 1: Command Line Argument

```bash
# Use port 8081
.lake/build/bin/Main 8081

# Or with socat
socat TCP-LISTEN:8081,fork,reuseaddr EXEC:'.lake/build/bin/Main 8081'
```

### Option 2: Use the Start Script

```bash
# Default port (8080)
./START_SERVICE.sh

# Custom port
./START_SERVICE.sh 8081
```

## If Port 8080 is Already in Use

1. **Find what's using it:**
   ```bash
   lsof -i :8080
   # or
   ss -tuln | grep :8080
   ```

2. **Stop the service** using port 8080, or

3. **Use a different port:**
   ```bash
   ./START_SERVICE.sh 8081
   ```

## Common Port Conflicts

- **8080**: Often used by development servers (Tomcat, Jenkins, etc.)
- **3000**: Common for Node.js apps
- **5000**: Common for Flask apps
- **8000**: Common for Django apps

## Recommended Alternative Ports

If 8080 is taken, try:
- **8081** - Close to default, easy to remember
- **8443** - HTTPS alternative
- **9090** - Common for development
- **3001** - Alternative development port

## Testing the Service

Once running, test with:

```bash
# Health check
curl http://localhost:8080/health

# Or if using a different port
curl http://localhost:8081/health
```


# Building Container Image for ZKIP-STARK

This guide explains how to build a container image for the zkip-stark application.

## Current Status

The deployment currently uses `nginx:alpine` as a placeholder image. This allows Argo CD to successfully deploy and manage the application while you build your actual container image.

## Building Your Container Image

### Option 1: Simple Lean 4 Application Container

If your application is a Lean 4 executable:

```dockerfile
# Dockerfile
FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install Elan (Lean version manager)
RUN curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | sh -s -- -y

# Set up environment
ENV PATH="/root/.elan/bin:$PATH"

# Copy application
WORKDIR /app
COPY . .

# Build the application
RUN elan toolchain install stable && \
    elan default stable && \
    lake build

# Expose port
EXPOSE 8080

# Run the application
CMD ["lake", "exe", "YourMainExecutable"]
```

Build and push:
```bash
docker build -t ghcr.io/memmmmike/zkip-stark:latest .
docker push ghcr.io/memmmmike/zkip-stark:latest
```

### Option 2: Multi-stage Build (Recommended)

For a smaller final image:

```dockerfile
# Dockerfile
# Build stage
FROM ubuntu:22.04 AS builder

RUN apt-get update && apt-get install -y \
    curl \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

RUN curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | sh -s -- -y
ENV PATH="/root/.elan/bin:$PATH"

WORKDIR /build
COPY . .
RUN elan toolchain install stable && \
    elan default stable && \
    lake build

# Runtime stage
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    libgmp10 \
    libffi8 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy built artifacts from builder
COPY --from=builder /root/.elan /root/.elan
COPY --from=builder /build/.lake/build /app/.lake/build
COPY --from=builder /build /app

WORKDIR /app
ENV PATH="/root/.elan/bin:$PATH"

EXPOSE 8080
CMD ["lake", "exe", "YourMainExecutable"]
```

### Option 3: GitHub Container Registry (ghcr.io)

For public or private images:

```bash
# Login to GitHub Container Registry
echo $GITHUB_TOKEN | docker login ghcr.io -u memmmmike --password-stdin

# Build and push
docker build -t ghcr.io/memmmmike/zkip-stark:latest .
docker push ghcr.io/memmmmike/zkip-stark:latest
```

### Option 4: Docker Hub

```bash
# Login to Docker Hub
docker login

# Build and push
docker build -t memmmmike/zkip-stark:latest .
docker push memmmmike/zkip-stark:latest
```

## Updating the Deployment

After building and pushing your image:

1. **Update `k8s/base/deployment.yaml`**:
   ```yaml
   image: ghcr.io/memmmmike/zkip-stark:latest  # Or your registry
   ```

2. **Update health check ports** if your app uses a different port:
   ```yaml
   ports:
   - containerPort: 8080  # Your app's port

   livenessProbe:
     httpGet:
       path: /health
       port: 8080
   ```

3. **Commit and push**:
   ```bash
   git add k8s/base/deployment.yaml
   git commit -m "Update deployment to use actual container image"
   git push origin main
   ```

4. **Argo CD will automatically sync** the changes

## Testing Locally

Before pushing to registry, test locally:

```bash
# Build
docker build -t zkip-stark:latest .

# Test run
docker run -p 8080:8080 zkip-stark:latest

# Test in Kubernetes (if using local registry)
kubectl set image deployment/zkip-stark zkip-stark=zkip-stark:latest --local
```

## CI/CD Integration

You can automate image building with GitHub Actions:

```yaml
# .github/workflows/docker-build.yml
name: Build and Push Docker Image

on:
  push:
    branches: [ main ]
    tags: [ 'v*' ]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Build and push
        uses: docker/build-push-action@v4
        with:
          push: true
          tags: ghcr.io/memmmmike/zkip-stark:latest
          context: .
```

## Current Placeholder

The deployment currently uses `nginx:alpine` which:
- ✅ Allows Argo CD to deploy successfully
- ✅ Verifies the Kubernetes setup works
- ✅ Provides a working service for testing
- ⚠️ Does NOT run your actual application

Replace it with your actual image when ready!


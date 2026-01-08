# Multi-stage Dockerfile for ZKIP-STARK API Service
# Stage 1: Build
FROM leanprover/lean4:v4.24.0 AS builder

WORKDIR /app

# Copy project files
COPY lakefile.lean ./
COPY lake-manifest.json* ./
COPY . ./

# Build the application
RUN lake build Main

# Stage 2: Runtime
FROM ubuntu:22.04

WORKDIR /app

# Install only necessary runtime libraries
RUN apt-get update && apt-get install -y \
    libgmp10 \
    libffi8 \
    ca-certificates \
    socat \
    && rm -rf /var/lib/apt/lists/*

# Copy built executable and dependencies from builder
COPY --from=builder /root/.elan /root/.elan
COPY --from=builder /app/.lake/build /app/.lake/build
COPY --from=builder /app /app

# Set up environment
ENV PATH="/root/.elan/bin:$PATH"

# Expose port
EXPOSE 8080

# Use socat to handle TCP connections and pipe to our executable
# This allows the simple stdin/stdout server to work with TCP
CMD ["sh", "-c", "socat TCP-LISTEN:8080,fork,reuseaddr EXEC:'lake exe Main'"]


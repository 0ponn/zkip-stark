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
    && rm -rf /var/lib/apt/lists/*

# Copy built executable and dependencies from builder
COPY --from=builder /root/.elan /root/.elan
COPY --from=builder /app/.lake/build /app/.lake/build
COPY --from=builder /app /app

# Set up environment
ENV PATH="/root/.elan/bin:$PATH"

# Expose port
EXPOSE 8080

# One long-running server. Pass ZKIP_API_KEY at run time (docker run -e);
# proofs use RAYON_NUM_THREADS threads (4 unless overridden). --public binds
# 0.0.0.0 inside the container; publish the port only where it should be reachable.
ENV RAYON_NUM_THREADS=4
CMD ["/app/.lake/build/bin/Main", "8080", "--public"]

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

# Stage 2: Runtime. Main links only libc (the Lean runtime is static), so the
# image needs the binary and nothing from the toolchain.
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --uid 10001 --no-create-home --shell /usr/sbin/nologin zkip

COPY --from=builder /app/.lake/build/bin/Main /app/Main

# Run unprivileged.
USER zkip

EXPOSE 8080

# One long-running server. Pass ZKIP_API_KEY at run time (docker run -e);
# proofs use RAYON_NUM_THREADS threads (4 unless overridden). --public binds
# 0.0.0.0 inside the container; publish the port only where it should be reachable.
ENV RAYON_NUM_THREADS=4
CMD ["/app/Main", "8080", "--public"]

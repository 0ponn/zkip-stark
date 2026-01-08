# ZKIP-STARK Quick Start Guide

## What You Built

You've built a **Zero-Knowledge Intellectual Property Protocol** with STARK proofs. This allows you to:

- **Prove** IP attributes meet requirements without revealing actual values
- **Verify** certificates cryptographically
- **Deploy** as a production API service

## Quick Start

### 1. Build the Service

```bash
cd /home/mlayug/Documents/GitHub/zkp-projects/zk-ip-protocol
lake build Main
```

### 2. Run Locally (with socat)

```bash
# Install socat if needed
sudo apt-get install socat  # or equivalent for your distro

# Run the service
socat TCP-LISTEN:8080,fork,reuseaddr EXEC:'lake exe Main'
```

### 3. Test the API

**Health Check:**
```bash
curl http://localhost:8080/health
```

**Generate Certificate:**
```bash
curl -X POST http://localhost:8080/api/v1/certificate/generate \
  -H "Content-Type: application/json" \
  -d '{
    "id": 1,
    "attributes": [
      {"type": "performance", "value": 1500}
    ],
    "merkleRoot": [],
    "timestamp": 1234567890,
    "predicate": {
      "threshold": 1000,
      "operator": ">="
    },
    "privateAttribute": 1500
  }'
```

## Docker Deployment

### Build Image

```bash
docker build -t zkip-stark:latest .
```

### Run Container

```bash
docker run -p 8080:8080 zkip-stark:latest
```

## Kubernetes Deployment (via Argo CD)

Your Kubernetes manifests are already set up in `k8s/`. Argo CD will automatically deploy when you:

1. Build and push your Docker image:
   ```bash
   docker build -t ghcr.io/memmmmike/zkip-stark:latest .
   docker push ghcr.io/memmmmike/zkip-stark:latest
   ```

2. Update `k8s/base/deployment.yaml` to use your image:
   ```yaml
   image: ghcr.io/memmmmike/zkip-stark:latest
   ```

3. Commit and push to your repository - Argo CD will sync automatically!

## API Endpoints

- `GET /health` - Health check
- `GET /ready` - Readiness check
- `POST /api/v1/certificate/generate` - Generate ZK certificate
- `POST /api/v1/certificate/verify` - Verify certificate

See `API_USAGE.md` for detailed API documentation.

## What's Next?

1. **Add Authentication**: Secure your API with API keys or OAuth
2. **Add Database**: Store certificates and metadata
3. **Add Logging**: Track requests and errors
4. **Add Metrics**: Monitor performance
5. **Complete Verification**: Finish the certificate verification endpoint
6. **Add Batching**: Expose batch verification endpoints
7. **Add ZKMB**: Expose Zero-Knowledge Middlebox features

## Architecture

```
┌─────────────┐
│   Client    │
│  (curl/API) │
└──────┬──────┘
       │ HTTP
       ▼
┌─────────────────┐
│  Main.lean      │  ← HTTP API Server
│  (API Layer)    │
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│ STARKIntegration│  ← STARK Proof Generation
│ Advertisement   │  ← Certificate Logic
│ MerkleCommitment│  ← Merkle Tree Operations
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│   Ix/Aiur       │  ← STARK Backend
│   (Rust FFI)    │
└─────────────────┘
```

## Troubleshooting

**Build fails:**
- Ensure Lean 4 toolchain is installed: `elan toolchain install leanprover/lean4:v4.24.0`
- Check `.lean-toolchain` file exists

**Service won't start:**
- Ensure port 8080 is available
- Check socat is installed

**API returns errors:**
- Check JSON format matches API documentation
- Verify all required fields are present

## Support

- See `API_USAGE.md` for API documentation
- See `README.md` for project overview
- Check `k8s/ARGOCD_SETUP_GUIDE.md` for deployment help


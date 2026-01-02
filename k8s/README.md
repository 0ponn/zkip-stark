# Kubernetes Manifests for ZKIP-STARK

This directory contains Kubernetes manifests for deploying ZKIP-STARK using Argo CD (GitOps).

**📖 For complete setup instructions, see [ARGOCD_SETUP_GUIDE.md](ARGOCD_SETUP_GUIDE.md)**

## Structure

```
k8s/
├── base/                    # Base manifests (used by all environments)
│   ├── deployment.yaml     # Deployment configuration
│   ├── service.yaml        # Service configuration
│   ├── configmap.yaml      # Application configuration
│   └── kustomization.yaml  # Kustomize base configuration
├── overlays/               # Environment-specific overlays
│   ├── production/         # Production environment
│   │   ├── kustomization.yaml
│   │   └── deployment-patch.yaml
│   └── staging/           # Staging environment
│       └── kustomization.yaml
├── argocd-application.yaml # Argo CD Application manifest
└── README.md              # This file
```

## Quick Start

### Deploy with Argo CD

1. **Apply the Argo CD Application manifest**:
   ```bash
   kubectl apply -f k8s/argocd-application.yaml
   ```

2. **Or use the Argo CD UI**:
   - Go to Argo CD UI
   - Click "New App"
   - Use the settings from `argocd-application.yaml`

### Deploy with kubectl

```bash
# Deploy base configuration
kubectl apply -k k8s/base

# Deploy to staging
kubectl apply -k k8s/overlays/staging

# Deploy to production
kubectl apply -k k8s/overlays/production
```

## Configuration

### Base Configuration

The base configuration (`k8s/base/`) includes:
- **Deployment**: 2 replicas, basic resource limits
- **Service**: ClusterIP service on port 80
- **ConfigMap**: Application settings

### Environment Overlays

- **Staging**: 1 replica, debug logging
- **Production**: 3 replicas, higher resource limits, warn logging

## Customization

### Update Image

Edit `k8s/base/deployment.yaml`:
```yaml
containers:
- name: zkip-stark
  image: your-registry/zkip-stark:v1.0.0
```

### Update Resources

Edit `k8s/base/deployment.yaml`:
```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "200m"
  limits:
    memory: "1Gi"
    cpu: "1000m"
```

### Update Configuration

Edit `k8s/base/configmap.yaml` or use overlays to merge environment-specific values.

## Argo CD Sync

The Argo CD Application is configured with:
- **Automated sync**: Automatically syncs when changes are pushed
- **Self-heal**: Automatically corrects drift
- **Prune**: Removes resources no longer in Git
- **Retry**: Retries failed syncs with exponential backoff

## Health Checks

The deployment includes:
- **Liveness probe**: `/health` endpoint (30s initial delay)
- **Readiness probe**: `/ready` endpoint (5s initial delay)

## Notes

- The manifests assume a containerized version of zkip-stark
- Update the image reference in `deployment.yaml` to point to your container registry
- Adjust resource limits based on your cluster capacity
- Add secrets for sensitive configuration (API keys, etc.) as needed


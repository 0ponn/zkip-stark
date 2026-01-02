# Argo CD Quick Start for ZKIP-STARK

Quick reference for setting up Argo CD with zkip-stark.

## Prerequisites

- Kubernetes cluster running
- Argo CD installed
- `kubectl` configured
- `argocd` CLI installed (optional)

## Quick Setup (3 Steps)

### 1. Commit Manifests to Git

```bash
cd /home/mlayug/Documents/GitHub/zkp-projects/zk-ip-protocol
git add k8s/
git commit -m "Add Kubernetes manifests for Argo CD"
git push origin main
```

### 2. Create Argo CD Application

**Using kubectl:**
```bash
kubectl apply -f k8s/argocd-application.yaml
```

**Using Argo CD CLI:**
```bash
export PATH="$HOME/.local/bin:$PATH"
argocd app create zkip-stark \
  --repo https://github.com/memmmmike/zkip-stark.git \
  --path k8s/base \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default \
  --sync-policy automated \
  --self-heal \
  --auto-prune
```

**Using Argo CD UI:**
1. Go to Argo CD UI (usually `https://localhost:8081`)
2. Click "New App"
3. Set:
   - **Name**: `zkip-stark`
   - **Repo URL**: `https://github.com/memmmmike/zkip-stark.git`
   - **Path**: `k8s/base`
   - **Sync Policy**: `Automatic`
4. Click "CREATE"

### 3. Verify

```bash
# Check application status
kubectl get applications -n argocd zkip-stark

# Check resources
kubectl get deployment,service,configmap -l app=zkip-stark

# Check pods
kubectl get pods -l app=zkip-stark
```

## Expected Result

After setup, Argo CD should show:
- ✅ **Status**: Synced, Healthy
- ✅ **Resources**: Deployment, Service, ConfigMap
- ✅ **Pods**: Running (2 replicas by default)

## Troubleshooting

**No resources showing?**
- Check that `k8s/` directory is in the repo
- Verify path in Argo CD app is `k8s/base`
- Check Argo CD logs: `kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller`

**Pods not starting?**
- Update image in `k8s/base/deployment.yaml`
- Check pod logs: `kubectl logs -l app=zkip-stark`
- Check events: `kubectl describe pod -l app=zkip-stark`

## Next Steps

1. **Update container image** in `k8s/base/deployment.yaml`
2. **Customize resources** as needed
3. **Set up staging/production** environments using overlays

## Full Documentation

See [ARGOCD_SETUP_GUIDE.md](ARGOCD_SETUP_GUIDE.md) for:
- Detailed setup instructions
- Environment-specific deployments
- Advanced configuration
- Complete troubleshooting guide


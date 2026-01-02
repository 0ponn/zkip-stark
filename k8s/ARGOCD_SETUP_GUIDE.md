# Argo CD Setup Guide for ZKIP-STARK

Complete guide for setting up Argo CD to manage zkip-stark Kubernetes resources via GitOps.

## Prerequisites

- Kubernetes cluster running
- Argo CD installed and accessible
- `kubectl` configured to access your cluster
- Access to the zkip-stark GitHub repository

## Overview

This guide will help you:
1. Set up Argo CD Application for zkip-stark
2. Configure GitOps sync
3. Verify deployment
4. Troubleshoot common issues

---

## Step 1: Verify Kubernetes Manifests

First, ensure the Kubernetes manifests are in your repository:

```bash
cd /home/mlayug/Documents/GitHub/zkp-projects/zk-ip-protocol

# Verify manifests exist
ls -la k8s/base/
ls -la k8s/overlays/
```

You should see:
- `k8s/base/deployment.yaml`
- `k8s/base/service.yaml`
- `k8s/base/configmap.yaml`
- `k8s/base/kustomization.yaml`
- `k8s/argocd-application.yaml`

---

## Step 2: Commit and Push Manifests

If you haven't already, commit the Kubernetes manifests:

```bash
cd /home/mlayug/Documents/GitHub/zkp-projects/zk-ip-protocol

# Add Kubernetes manifests
git add k8s/

# Commit
git commit -m "Add Kubernetes manifests for Argo CD GitOps"

# Push to GitHub
git push origin main
```

---

## Step 3: Update Image Reference

**Important**: Before deploying, update the container image in `k8s/base/deployment.yaml`:

```yaml
containers:
- name: zkip-stark
  image: your-registry/zkip-stark:latest  # Update this!
  imagePullPolicy: IfNotPresent
```

If you don't have a container image yet, you can:
1. Use a placeholder image for testing
2. Build and push your own image
3. Use a public test image

---

## Step 4: Apply Argo CD Application

### Option A: Using kubectl (Recommended)

```bash
# Apply the Argo CD Application manifest
kubectl apply -f k8s/argocd-application.yaml

# Verify it was created
kubectl get applications -n argocd
```

### Option B: Using Argo CD CLI

```bash
# Login to Argo CD
argocd login localhost:8081  # Or your Argo CD server

# Create application
argocd app create zkip-stark \
  --repo https://github.com/memmmmike/zkip-stark.git \
  --path k8s/base \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default \
  --sync-policy automated \
  --self-heal \
  --auto-prune
```

### Option C: Using Argo CD UI

1. Open Argo CD UI (usually at `https://localhost:8081` or your Argo CD URL)
2. Click **"New App"** or **"+ CREATE APPLICATION"**
3. Fill in the form:
   - **Application Name**: `zkip-stark`
   - **Project Name**: `default`
   - **Sync Policy**: `Automatic`
   - **Repository URL**: `https://github.com/memmmmike/zkip-stark.git`
   - **Revision**: `main`
   - **Path**: `k8s/base`
   - **Cluster URL**: `https://kubernetes.default.svc`
   - **Namespace**: `default`
4. Click **"CREATE"**

---

## Step 5: Verify Deployment

### Check Argo CD Application Status

```bash
# Check application status
kubectl get applications -n argocd zkip-stark

# Get detailed status
kubectl describe application -n argocd zkip-stark

# Or use Argo CD CLI
argocd app get zkip-stark
```

### Check Deployed Resources

```bash
# Check deployment
kubectl get deployment zkip-stark

# Check pods
kubectl get pods -l app=zkip-stark

# Check service
kubectl get service zkip-stark

# Check configmap
kubectl get configmap zkip-stark-config
```

### View in Argo CD UI

1. Go to Argo CD UI
2. Click on **"zkip-stark"** application
3. You should see:
   - **Status**: Synced, Healthy
   - **Resources**: Deployment, Service, ConfigMap
   - **Pods**: Running pods

---

## Step 6: Sync Configuration

### Manual Sync

If automatic sync is disabled or you need to force a sync:

```bash
# Using kubectl
kubectl patch application zkip-stark -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"main"}}}'

# Using Argo CD CLI
argocd app sync zkip-stark
```

### Automatic Sync

The `argocd-application.yaml` includes automatic sync:

```yaml
syncPolicy:
  automated:
    prune: true      # Remove resources not in Git
    selfHeal: true   # Automatically correct drift
    allowEmpty: false
```

This means:
- Changes pushed to `main` branch are automatically synced
- Drift (manual changes) is automatically corrected
- Resources deleted from Git are automatically removed

---

## Step 7: Environment-Specific Deployments

### Deploy to Staging

Create a separate Argo CD Application for staging:

```bash
# Copy and modify the application manifest
cp k8s/argocd-application.yaml k8s/argocd-application-staging.yaml
```

Edit `k8s/argocd-application-staging.yaml`:

```yaml
metadata:
  name: zkip-stark-staging
spec:
  source:
    path: k8s/overlays/staging  # Use staging overlay
  destination:
    namespace: staging  # Deploy to staging namespace
```

Apply:

```bash
kubectl apply -f k8s/argocd-application-staging.yaml
```

### Deploy to Production

Similarly for production:

```yaml
metadata:
  name: zkip-stark-production
spec:
  source:
    path: k8s/overlays/production  # Use production overlay
  destination:
    namespace: production  # Deploy to production namespace
```

---

## Troubleshooting

### Application Shows "Synced" but No Resources

**Problem**: Argo CD shows "Synced" and "Healthy" but no resources are deployed.

**Solutions**:
1. **Check the path**: Ensure `path: k8s/base` matches your directory structure
2. **Check branch**: Verify `targetRevision: main` is correct
3. **Check manifests**: Ensure YAML files are valid:
   ```bash
   kubectl apply --dry-run=client -k k8s/base
   ```
4. **Check Argo CD logs**:
   ```bash
   kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
   ```

### Pods Not Starting

**Problem**: Pods are in `Pending` or `CrashLoopBackOff` state.

**Solutions**:
1. **Check image**: Ensure the container image exists and is accessible
2. **Check resources**: Verify cluster has enough resources
3. **Check logs**:
   ```bash
   kubectl logs -l app=zkip-stark
   kubectl describe pod -l app=zkip-stark
   ```

### Sync Failures

**Problem**: Argo CD shows sync errors.

**Solutions**:
1. **Check repository access**: Ensure Argo CD can access the GitHub repo
2. **Check permissions**: Verify Argo CD has permissions to create resources
3. **Check namespace**: Ensure the target namespace exists:
   ```bash
   kubectl create namespace default  # If needed
   ```
4. **View sync details**:
   ```bash
   argocd app get zkip-stark
   kubectl get application zkip-stark -n argocd -o yaml
   ```

### Resources Drift

**Problem**: Manual changes to resources are reverted.

**This is expected behavior** with `selfHeal: true`. To allow manual changes:
1. Temporarily disable self-heal in Argo CD UI
2. Or make changes in Git and let Argo CD sync them

---

## Advanced Configuration

### Custom Resource Limits

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

### Add Secrets

Create a secret for sensitive data:

```bash
kubectl create secret generic zkip-stark-secrets \
  --from-literal=api-key=your-key \
  --from-literal=db-password=your-password
```

Reference in deployment:

```yaml
env:
- name: API_KEY
  valueFrom:
    secretKeyRef:
      name: zkip-stark-secrets
      key: api-key
```

### Health Check Endpoints

The deployment expects health check endpoints. If your application doesn't have them yet:

1. **Temporary fix**: Remove or adjust probes in `deployment.yaml`
2. **Proper fix**: Add `/health` and `/ready` endpoints to your application

### Ingress (Optional)

Add an Ingress resource to expose the service:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: zkip-stark
spec:
  rules:
  - host: zkip-stark.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: zkip-stark
            port:
              number: 80
```

---

## Verification Checklist

After setup, verify:

- [ ] Argo CD Application created and visible in UI
- [ ] Application status shows "Synced" and "Healthy"
- [ ] Resources visible in Argo CD (Deployment, Service, ConfigMap)
- [ ] Pods are running: `kubectl get pods -l app=zkip-stark`
- [ ] Service is accessible: `kubectl get service zkip-stark`
- [ ] ConfigMap applied: `kubectl get configmap zkip-stark-config`
- [ ] Automatic sync working (push a change and verify it syncs)

---

## Next Steps

1. **Build and push container image** to your registry
2. **Update image reference** in `k8s/base/deployment.yaml`
3. **Add monitoring** (Prometheus, Grafana)
4. **Set up CI/CD** to build and push images automatically
5. **Configure production environment** with proper resource limits

---

## Useful Commands

```bash
# View Argo CD applications
kubectl get applications -n argocd

# Get application details
argocd app get zkip-stark

# Force sync
argocd app sync zkip-stark

# View application resources
argocd app resources zkip-stark

# Delete application (removes managed resources)
argocd app delete zkip-stark

# View logs
kubectl logs -l app=zkip-stark -f

# Port forward to test locally
kubectl port-forward service/zkip-stark 8080:80
```

---

## References

- **Argo CD Documentation**: https://argo-cd.readthedocs.io/
- **Kustomize Documentation**: https://kustomize.io/
- **Repository**: https://github.com/memmmmike/zkip-stark
- **Kubernetes Manifests**: `k8s/` directory

---

**Last Updated**: 2025-01-XX
**Status**: Ready for deployment


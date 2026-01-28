# Prerequisites for Lightspeed Stack + vLLM Deployment

This directory contains scripts and documentation to verify and set up prerequisites.

## Quick Check

Run this first to see what's missing:

```bash
./check-prerequisites.sh
```

## Common Issues and Solutions

### 1. KServe CRDs Not Found

**Error**: `no matches for kind "ServingRuntime"`

**Solution**: Install RHOAI and create DataScienceCluster

See: `setup-rhoai.md`

### 2. Webhook Service Not Ready

**Error**: `no endpoints available for service "kserve-webhook-server-service"`

**Solution**: Wait for KServe to be fully ready

```bash
./wait-for-kserve.sh
```

This script waits for:
- KServe controller deployment
- Webhook service endpoints
- CRDs to be established
- Knative Serving components

### 3. GPU Nodes Not Found

**Error**: No GPU nodes in prerequisite check

**Solution**: Add GPU nodes to your ROSA cluster

For ROSA:
```bash
rosa create machine-pool --cluster=<cluster-name> \
  --name=gpu-pool \
  --replicas=1 \
  --instance-type=g5.2xlarge \
  --labels=node-role.kubernetes.io/gpu=true
```

### 4. NVIDIA GPU Operator Not Installed

**Solution**: Install from OperatorHub

See: `setup-rhoai.md` (GPU Setup section)

## Files in This Directory

- **check-prerequisites.sh** - Comprehensive prerequisite check
- **wait-for-kserve.sh** - Wait for KServe to be ready
- **setup-rhoai.md** - Detailed RHOAI setup instructions
- **README.md** - This file

## Typical Setup Sequence

1. **Install RHOAI Operator**
   ```bash
   # Follow instructions in setup-rhoai.md
   ```

2. **Create DataScienceCluster**
   ```bash
   # Follow instructions in setup-rhoai.md
   ```

3. **Wait for KServe**
   ```bash
   ./wait-for-kserve.sh
   ```

4. **Verify All Prerequisites**
   ```bash
   ./check-prerequisites.sh
   ```

5. **Proceed with Deployment**
   ```bash
   cd ../scripts
   ./deploy-all.sh
   ```

## Manual Checks

### Check RHOAI Operator

```bash
oc get csv -n redhat-ods-operator | grep rhods
```

Should show: `rhods-operator.vX.Y.Z   Succeeded`

### Check DataScienceCluster

```bash
oc get datasciencecluster
```

Should show: `default-dsc`

### Check KServe

```bash
# Controller pod
oc get pods -n redhat-ods-applications -l control-plane=kserve-controller-manager

# Webhook service
oc get svc kserve-webhook-server-service -n redhat-ods-applications

# Endpoints
oc get endpoints kserve-webhook-server-service -n redhat-ods-applications
```

### Check CRDs

```bash
oc get crd | grep kserve
```

Should show:
- `inferenceservices.serving.kserve.io`
- `servingruntimes.serving.kserve.io`
- And others

### Check GPU Nodes

```bash
oc get nodes -l nvidia.com/gpu.present=true
```

Should show at least one GPU node.

## Getting Help

If you're stuck:

1. Check RHOAI operator logs:
   ```bash
   oc logs -n redhat-ods-operator deployment/rhods-operator
   ```

2. Check KServe controller logs:
   ```bash
   oc logs -n redhat-ods-applications -l control-plane=kserve-controller-manager
   ```

3. Check DataScienceCluster status:
   ```bash
   oc describe datasciencecluster default-dsc
   ```

4. Check recent events:
   ```bash
   oc get events -A --sort-by='.lastTimestamp' | tail -20
   ```

## Resources

- [RHOAI Documentation](https://access.redhat.com/documentation/en-us/red_hat_openshift_ai_self-managed)
- [KServe Documentation](https://kserve.github.io/website/)
- [ROSA Documentation](https://docs.openshift.com/rosa/)

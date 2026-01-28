# Setting Up Red Hat OpenShift AI (RHOAI)

KServe CRDs are installed as part of Red Hat OpenShift AI. You need to install and configure RHOAI before deploying vLLM.

## Step 1: Install RHOAI Operator

### Via Web Console

1. Log into OpenShift Console
2. Navigate to **Operators** → **OperatorHub**
3. Search for **"Red Hat OpenShift AI"**
4. Click **Install**
5. Select installation settings:
   - **Update channel**: stable
   - **Installation mode**: All namespaces on the cluster (recommended)
   - **Installed Namespace**: redhat-ods-operator
6. Click **Install**

### Via CLI

```bash
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: redhat-ods-operator
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: redhat-ods-operator
  namespace: redhat-ods-operator
spec: {}
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhods-operator
  namespace: redhat-ods-operator
spec:
  channel: stable
  name: rhods-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

Wait for the operator to be installed:

```bash
oc get csv -n redhat-ods-operator -w
```

You should see `rhods-operator.vX.Y.Z` with status `Succeeded`.

## Step 2: Create DataScienceCluster

The DataScienceCluster resource enables all RHOAI components, including KServe.

### Via Web Console

1. Navigate to **Operators** → **Installed Operators**
2. Select **Red Hat OpenShift AI** operator
3. Click **Data Science Cluster** tab
4. Click **Create DataScienceCluster**
5. Use the default configuration or customize as needed
6. Ensure **KServe** component is enabled:
   ```yaml
   kserve:
     managementState: Managed
   ```
7. Click **Create**

### Via CLI (Recommended)

```bash
cat <<EOF | oc apply -f -
apiVersion: datasciencecluster.opendatahub.io/v1
kind: DataScienceCluster
metadata:
  name: default-dsc
spec:
  components:
    codeflare:
      managementState: Removed
    dashboard:
      managementState: Managed
    datasciencepipelines:
      managementState: Removed
    kserve:
      managementState: Managed
      serving:
        ingressGateway:
          certificate:
            type: OpenshiftDefaultIngress
        managementState: Managed
        name: knative-serving
    kueue:
      managementState: Removed
    modelmeshserving:
      managementState: Removed
    ray:
      managementState: Removed
    trainingoperator:
      managementState: Removed
    trustyai:
      managementState: Removed
    workbenches:
      managementState: Managed
EOF
```

**Key points:**
- **KServe** must be `Managed` (this installs the CRDs you need)
- **ModelMesh** is `Removed` (we're using KServe instead)
- Other components can be `Removed` if not needed for the POC

## Step 3: Wait for Installation

Monitor the DataScienceCluster status:

```bash
oc get datasciencecluster default-dsc -w
```

Wait for all components to be ready. This can take 5-10 minutes.

Check the status:

```bash
oc get datasciencecluster default-dsc -o yaml
```

Look for conditions showing `Available: True`.

## Step 4: Verify KServe Installation

Check that KServe CRDs are installed:

```bash
# Check ServingRuntime CRD
oc get crd servingruntimes.serving.kserve.io

# Check InferenceService CRD
oc get crd inferenceservices.serving.kserve.io
```

Both commands should return successfully showing the CRDs exist.

Check KServe controller is running:

```bash
oc get pods -n redhat-ods-applications | grep kserve
```

You should see pods like:
- `kserve-controller-manager-xxxxx`
- `kserve-models-web-app-xxxxx`

## Step 5: Verify Knative Serving

KServe uses Knative Serving for networking:

```bash
oc get pods -n knative-serving
```

You should see pods like:
- `activator-xxxxx`
- `autoscaler-xxxxx`
- `controller-xxxxx`
- `webhook-xxxxx`

## Troubleshooting

### Operator Installation Stuck

Check operator logs:
```bash
oc logs -n redhat-ods-operator deployment/rhods-operator
```

### DataScienceCluster Not Creating Resources

Check the DSC status:
```bash
oc describe datasciencecluster default-dsc
```

Look at the events and status conditions.

### KServe CRDs Not Appearing

Ensure KServe is enabled in the DSC:
```bash
oc get datasciencecluster default-dsc -o jsonpath='{.spec.components.kserve.managementState}'
```

Should return: `Managed`

If not, patch the DSC:
```bash
oc patch datasciencecluster default-dsc --type=merge -p '{"spec":{"components":{"kserve":{"managementState":"Managed"}}}}'
```

### Pod Failures in redhat-ods-applications

Check events:
```bash
oc get events -n redhat-ods-applications --sort-by='.lastTimestamp' | tail -20
```

Check specific pod logs:
```bash
oc logs -n redhat-ods-applications <pod-name>
```

## GPU Setup (If Using GPU Nodes)

### Install NVIDIA GPU Operator

If you have GPU nodes but the operator isn't installed:

1. Navigate to **Operators** → **OperatorHub**
2. Search for **"NVIDIA GPU Operator"**
3. Click **Install**
4. Follow installation instructions

Or via CLI:

```bash
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: nvidia-gpu-operator
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: nvidia-gpu-operator-group
  namespace: nvidia-gpu-operator
spec:
  targetNamespaces:
  - nvidia-gpu-operator
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: gpu-operator-certified
  namespace: nvidia-gpu-operator
spec:
  channel: stable
  name: gpu-operator-certified
  source: certified-operators
  sourceNamespace: openshift-marketplace
EOF
```

### Create ClusterPolicy

After the operator is installed:

```bash
cat <<EOF | oc apply -f -
apiVersion: nvidia.com/v1
kind: ClusterPolicy
metadata:
  name: gpu-cluster-policy
spec:
  operator:
    defaultRuntime: crio
  dcgmExporter:
    enabled: true
  gfd:
    enabled: true
EOF
```

Wait for GPU nodes to be detected:

```bash
oc get nodes -l nvidia.com/gpu.present=true
```

## Verification Checklist

Run the prerequisite check script:

```bash
cd deploy/rosa-poc/00-prerequisites
./check-prerequisites.sh
```

All checks should pass before proceeding with the Lightspeed Stack deployment.

## Next Steps

Once all prerequisites are met:

```bash
cd ../scripts
./deploy-all.sh
```

Or follow the manual deployment in the main README.md.

## References

- [RHOAI Documentation](https://access.redhat.com/documentation/en-us/red_hat_openshift_ai_self-managed)
- [KServe Documentation](https://kserve.github.io/website/)
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/openshift/contents.html)

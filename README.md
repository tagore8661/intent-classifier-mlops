# Intent Classifier MLOps Project - KServe Deployment

This project demonstrates how to deploy a machine learning intent classifier model using KServe on Kubernetes. The deployment process showcases MLOps best practices with versioned model releases and automated serving infrastructure.

---

## Prerequisites

- Kubernetes cluster (kind, minikube, or any K8s cluster)
- kubectl configured and working
- Helm installed
- Python 3.x for model training

## Deployment Steps

### Step 1: Create Kubernetes Cluster

```bash
kind create cluster --name=kserve-demo-intent
```

### Step 2: Install Cert Manager

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

# Verify installation
kubectl get pods -n cert-manager
```

### Step 3: Create KServe Namespace

```bash
kubectl create namespace kserve
```

### Step 4: Install KServe CRDs

```bash
helm install kserve-crd oci://ghcr.io/kserve/charts/kserve-crd \
  --version v0.16.0 \
  -n kserve \
  --wait
```

### Step 5: Install KServe Controller

```bash
helm install kserve oci://ghcr.io/kserve/charts/kserve \
  --version v0.16.0 \
  -n kserve \
  --set kserve.controller.deploymentMode=RawDeployment \
  --wait
```

### Step 6: Prepare Model for Deployment

Clone the repository and train the model:

```bash
git clone https://github.com/tagore8661/intent-classifier-mlops
cd intent-classifier-mlops

# Train the model
python3 model/train.py
```

This creates the model file in `artifacts/intent-model.pkl`:

```bash
cd model/artifacts
ls -la
# You should find: intent-model.pkl
```

### Step 7: Upload Model to GitHub Release

**Why GitHub Releases?**
- Real-world approach for model versioning
- Models are versioned alongside code
- Easy to track model versions
- Download URL is always accessible

**Steps:**
1. Go to GitHub repo: [Intent Classifier MLOps - KServe Branch](https://github.com/tagore8661/intent-classifier-mlops/tree/kserve)
2. Click on the **Releases** tab
3. Click **Draft a new release**
4. Fill in:
   - Tag: `v1.0` (or your version)
   - Title: `KServe Deployment v1.0`
5. Scroll down to **Attach binaries**
6. Upload `intent-model.pkl` file
7. Click **Publish Release**

### Step 8: Get Model Download URL

1. Go to the release you just created
2. Right-click on `intent-model.pkl`
3. Select **Copy Link**

You now have the model URL:
```
https://github.com/tagore8661/intent-classifier-mlops/releases/download/v1.0/intent_model.pkl
```

### Step 9: Create Intent Namespace

```bash
kubectl create namespace intent
```

### Step 10: Create InferenceService for Intent Classifier

The `intent-classifier-kserve.yml` file contains the KServe InferenceService configuration:

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: intent-classifier
  namespace: intent
spec:
  predictor:
    model:
      modelFormat:
        name: sklearn
      storageUri: "<STORAGE_URI>"
      resources:
        requests:
          cpu: "100m"
          memory: "512Mi"
        limits:
          cpu: "1"
          memory: "1Gi"
```

Replace the `storageUri` with your actual model URL if different.

### Step 11: Deploy InferenceService

```bash
kubectl apply -f intent-classifier-kserve.yml
```

### Step 12: Verify Deployment

```bash
# Check inference service
kubectl get inferenceservice -n intent

# Check if pods are running
kubectl get pods -n intent

# Check horizontal pod autoscaler
kubectl get hpa -n intent

# Check service
kubectl get svc -n intent
```

### Step 13: Monitor Controller Logs

```bash
kubectl logs <POD-NAME> -n kserve
# or
kubectl logs -n kserve -l app=kserve-controller -c kserve-controller --all-containers
```

Expected logs:
```
Reconciling inference service intent-classifier
Creating deployment
Creating service
Creating HPA
```

### Step 14: Port Forward Service

```bash
kubectl port-forward -n intent svc/intent-classifier-predictor 8080:80 --address 0.0.0.0
```

### Step 15: Test Intent Classifier Model

Open a new terminal and test the deployed model:

```bash
# Test 1: Greeting intent
curl -s -X POST http://localhost:8080/v1/models/intent-classifier:predict \
  -H "Content-Type: application/json" \
  -d '{
    "instances": [["Hi, how are you?"]]
  }'

# Test 2: Cancellation intent
curl -s -X POST http://localhost:8080/v1/models/intent-classifier:predict \
  -H "Content-Type: application/json" \
  -d '{
    "instances": [["I want to cancel my subscription"]]
  }'

# Test 3: Different greeting
curl -s -X POST http://localhost:8080/v1/models/intent-classifier:predict \
  -H "Content-Type: application/json" \
  -d '{
    "instances": [["Hello, how are you?"]]
  }'
```

**Expected Output:**
- `"Hi, how are you?"` → Greeting intent
- `"I want to cancel my subscription"` → Cancellation intent
- `"Hello, how are you?"` → Greeting intent


## Summary of Implementation

**What MLOps Engineers Did:**
1. Created Kubernetes cluster
2. Installed Cert Manager and KServe (one-time setup)
3. Prepared model and uploaded to GitHub release
4. Created InferenceService manifest with model URL
5. Applied manifest
6. Model is live and serving predictions

**Time Taken:** Approximately 10 minutes

**Comparison with Raw Kubernetes:**
- **Raw Kubernetes:** Create Dockerfile, Flask API, WSGI config, deployment manifest, service manifest, ingress, setup autoscaling = 2-3 days
- **KServe:** Provide model location + create InferenceService = 10 minutes

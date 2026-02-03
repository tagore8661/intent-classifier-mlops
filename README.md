# Intent Classifier MLOps Project - Kubernetes Deployment

This repository contains an Intent Classification model served via a Flask API, containerized with Docker, and deployed on a production-grade Kubernetes cluster using AWS EKS with Traefik Ingress.

---

## Table of Contents

1. [Phase 1: Docker Image & Registry](#phase-1-docker-image--registry)
2. [Phase 2: Kubernetes Cluster Setup](#phase-2-kubernetes-cluster-setup)
3. [Phase 3: Model Deployment](#phase-3-model-deployment)
4. [Phase 4: Ingress Controller & Routing](#phase-4-ingress-controller--routing)
5. [Phase 5: Testing Production Access](#phase-5-testing-production-access)
6. [Cleanup](#cleanup)

---

## Prerequisites

Before you begin, ensure you have the following tools installed and configured:
-   **Docker**: For building and testing images.
-   **AWS CLI**: Configured with appropriate credentials.
-   **kubectl**: The Kubernetes command-line tool.
-   **eksctl**: AWS CLI for managing EKS clusters.
-   **Helm**: The package manager for Kubernetes.

---

## Phase 1: Docker Image & Registry

### 1. Clone & Switch Branch
First, clone the repository and switch to the `k8s` branch which contains the necessary Kubernetes manifests.
```bash
git clone https://github.com/tagore8661/intent-classifier-mlops
cd intent-classifier-mlops
git checkout k8s
```

### 2. Build & Verify Locally
Build the image and run it locally to ensure the API works as expected.
```bash
# Build the image
docker build -t mlops-demo:latest .

# Run locally
docker run -d -p 6000:6000 mlops-demo:latest

# Test the local endpoint
curl -X POST http://localhost:6000/predict \
     -H "Content-Type: application/json" \
     -d '{"text": "Hi, How are you?"}'
# Expected Output: {"intent": "greeting"}
```

### 3. Push to Docker Hub
Authenticate and push the image to your repository.
```bash
# Login (Use PAT for security)
docker login -u <your-username>

# Tag the image
docker tag mlops-demo:latest <your-username>/intent-classifier-mlops:v1

# Push the image
docker push <your-username>/intent-classifier-mlops:v1
```

---

## Phase 2: Kubernetes Cluster Setup

### 1. Create EKS Cluster
Use `eksctl` to provision a cluster in AWS. This step typically takes 15-20 minutes.
```bash
eksctl create cluster \
  --name demo-cluster \
  --region ap-south-1 \
  --version 1.32 \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 3 \
  --managed
```

### 2. Configure Access
Update your local `kubeconfig` to connect to the new cluster.
```bash
aws eks update-kubeconfig --name demo-cluster --region ap-south-1
kubectl config current-context
```

---

## Phase 3: Model Deployment

Apply the Kubernetes manifests in order to set up the infrastructure.

### 1. Create Namespace
Isolate the application resources.
```bash
kubectl apply -f namespace.yml
```

### 2. Deploy the Model
This creates the pods based on the deployment configuration.
```bash
kubectl apply -f deployment.yml
```

### 3. Expose via Service
Create a Service to internal/external load balancing within the cluster.
```bash
kubectl apply -f service.yml
```

### 4. Verify Status
```bash
kubectl get all -n intent-namespace
```

---

## Phase 4: Ingress Controller & Routing

To expose the application to the internet with a clean URL structure, we use Traefik.

### 1. Install Traefik via Helm
```bash
# Add Helm Repo
helm repo add traefik https://helm.traefik.io/traefik
helm repo update

# Install Traefik
helm install traefik traefik/traefik --create-namespace --namespace traefik
```

### 2. Apply Ingress Rules
Define how traffic should be routed to our service.
```bash
kubectl apply -f ingress.yml
```

---

## Phase 5: Testing Production Access

### 1. Identify Load Balancer Endpoint
Fetch the external address of the Traefik Ingress.
```bash
kubectl get svc -n traefik
```

### 2. Real-World Test (The Curl Hack)
Since we are using a dummy host `example.com` in `ingress.yml`, we use the `--resolve` flag to test it.
```bash
# Get the IP of your Load Balancer if it's a hostname
nslookup <YOUR_LOAD_BALANCER_HOSTNAME>

# Test the Ingress
curl -X POST http://example.com/predict \
     --resolve example.com:80:<LOAD_BALANCER_IP> \
     -H "Content-Type: application/json" \
     -d '{"text": "Hello, how are you?"}'
```

---

## Cleanup
To avoid unnecessary AWS costs, delete the cluster when finished.
```bash
eksctl delete cluster --name demo-cluster --region ap-south-1
```

# Intent Classifier MLOps Project

This project demonstrates text classification service. It includes:
- **Model Training**: Trains a machine learning model using Scikit-Learn (CountVectorizer + Multinomial Naive Bayes) to classify user intents.
- **Model Serving**: A Flask REST API to serve predictions.

### 1. Environment Setup
```bash
# Clone the repo and switch to it
git clone https://github.com/tagore8661/intent-classifier-mlops
cd intent-classifier-mlops

# Setup Virtual Environment
python -m venv .venv
source .venv/bin/activate  # Linux/Mac
# .venv\Scripts\activate   # Windows

# Install Dependencies
pip install -r requirements.txt
```

### 2. Model Training
Train the Naive Bayes classifier on the sample dataset.
```bash
python model/train.py
```
*Artifact created: `model/artifacts/intent_model.pkl`*

### 3. Local Development Server
Run the Flask development server on port 6000.
```bash
python app.py
```

### 4. Testing the API (Inference)
Use `curl` to pass inputs and get predictions from the model.
```bash
# Test a Complaint
curl -X POST http://localhost:6000/predict \
     -H "Content-Type: application/json" \
     -d '{"text": "I want to cancel my subscription"}'

# Test a Greeting
curl -X POST http://localhost:6000/predict \
     -H "Content-Type: application/json" \
     -d '{"text": "Hi, How are you?"}'
```

---

***📌 NOTE:***
## 🌿 Repository Branches

This repository contains `4 branches`, each demonstrating different deployment strategies:

-  **[main](https://github.com/tagore8661/intent-classifier-mlops)**: Base branch containing the core MLOps implementation with local model training and Flask API serving
-  **[virtual-machines](https://github.com/tagore8661/intent-classifier-mlops/tree/virtual-machines)**: Virtual machine deployment with user-data.sh script for automated VM setup and configuration
-  **[k8s](https://github.com/tagore8661/intent-classifier-mlops/tree/k8s)**: Kubernetes deployment with complete manifests including Dockerfile, deployment.yml, service.yml, ingress.yml, and namespace.yml for containerized deployment
-  **[kserve](https://github.com/tagore8661/intent-classifier-mlops/tree/kserve)**: KServe serverless deployment with intent-classifier-kserve.yml for autoscaling model serving on Kubernetes

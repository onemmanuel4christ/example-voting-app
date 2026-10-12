# Capstone 1 Deployment Report: Distributed Voting Application on AWS EKS

**Author:** Onyekachi Emmanuel   Onuoha
**Project:** DevOps Capstone 1 – Containerization, CI/CD, IaC & Kubernetes Orchestration  
**Cluster Name:** `voting-app-cluster-kachi`  
**Docker Hub Registry:** `kachdev`  

---

## Executive Summary

This report documents the end-to-end deployment of a multi-tier, distributed microservices voting application to **Amazon Web Services (AWS) Elastic Kubernetes Service (EKS)**. 

The project encompasses:
1. **Container Security & Optimization**: Hardening Dockerfiles with minimal base images and non-root users.
2. **Infrastructure as Code (IaC)**: Provisioning a production-ready AWS EKS cluster and node groups using **Terraform**.
3. **Automated CI/CD & DevSecOps**: Building, scanning (with **Trivy**), and publishing container images to **Docker Hub** using **GitHub Actions**.
4. **Kubernetes Orchestration**: Packaging and deploying microservices using a custom **Helm Chart** (`voting-app-chart`) and exposing frontends via **AWS Elastic LoadBalancers**.

---



## Containerization & Security Hardening

To establish container security best practices, I refactored the Dockerfiles across the codebase:

### Python Vote Service (`vote/Dockerfile`)
* Pinned to official slim base image `python:3.11.8-slim-bookworm`.
* Created dedicated system user and group (`appuser:appgroup`) to run without root privileges.
* Cleaned pip cache using `--no-cache-dir`.

### Node.js Result Service (`result/Dockerfile`)
* Pinned to lightweight `node:18.19.1-alpine`.
* Executed container processes using Alpine's built-in non-root `node` user.
* Enforced clean dependency installation with `npm ci && npm cache clean --force`.

### .NET Worker Service (`worker/Dockerfile`)
* Implemented a multi-stage build:
  * **Build stage**: `mcr.microsoft.com/dotnet/sdk:7.0.406` to restore dependencies and compile.
  * **Runtime stage**: `mcr.microsoft.com/dotnet/aspnet:7.0.16` for an optimized runtime footprint.
* Added non-root user `appuser` and set proper `/app` permissions.

### Build Context Optimization (`.dockerignore`)
Created specific `.dockerignore` files for `vote`, `result`, and `worker` to exclude build artifacts, git metadata, and local development caches (`node_modules`, `obj/`, `bin/`, `__pycache__`).

---

## 3. Infrastructure as Code with Terraform

I provisioned the cloud infrastructure on AWS using modular Terraform scripts in `terraform/`:

* **`providers.tf`**: Pinned AWS provider `~> 5.0` and Terraform `~> 1.3.0`.
* **`variables.tf`**: Parameterized region (`us-east-1`) and custom cluster name (`voting-app-cluster-kachi`).
* **`main.tf`**:
  * IAM Roles with least-privilege policies: `AmazonEKSClusterPolicy`, `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, and `AmazonEC2ContainerRegistryReadOnly`.
  * Managed Node Group scaling configuration: `desired_size = 2`, `min_size = 1`, `max_size = 3` using `t3.medium` instances.

### Key Challenge & Resolution: AWS EKS Availability Zone Constraint
During initial deployment, cluster creation failed with:
```
UnsupportedAvailabilityZoneException: Cannot create cluster 'voting-app-cluster' because EKS does not support creating control plane instances in us-east-1e
```
**Resolution**: Updated `main.tf` to inspect all VPC subnets and filter out `us-east-1e` from both the EKS control plane and node group configuration:
```hcl
data "aws_subnet" "default" {
  for_each = toset(data.aws_subnets.default.ids)
  id       = each.value
}

locals {
  eks_subnets = [
    for s in data.aws_subnet.default : s.id
    if s.availability_zone != "us-east-1e"
  ]
}
```

### Infrastructure Commands Executed:
```bash
cd terraform
terraform init
terraform plan
terraform apply -auto-approve
aws eks update-kubeconfig --region us-east-1 --name voting-app-cluster-kachi
```

---

## 4. Automated CI/CD Pipeline (GitHub Actions)

I automated the build, security auditing, and delivery process in [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml).

### Pipeline Workflow Steps:
1. **Trigger**: Executes automatically on every push to the `main` branch.
2. **Security Audit (Trivy)**: Scans repository filesystem dependencies for critical vulnerabilities before container compilation.
3. **Docker Hub Authentication**: Logs into Docker Hub using encrypted repository secrets (`DOCKER_USERNAME` and `DOCKER_PASSWORD`).
4. **Dual-Tag Build & Push**:
   * Builds and pushes `kachdev/voting-app-vote` with `:latest` and `:${{ github.sha }}`.
   * Builds and pushes `kachdev/voting-app-result` with `:latest` and `:${{ github.sha }}`.
   * Builds and pushes `kachdev/voting-app-worker` with `:latest` and `:${{ github.sha }}`.

### Key Challenge & Resolution: Git LFS / GitHub File Size Limits
During local terraform caching, the AWS provider plugin binary (`terraform-provider-aws_v5.100.0_x5.exe`, ~685 MB) was inadvertently staged, leading to GitHub blocking the push:
```
remote: error: GH001: Large files detected (>100.00 MB)
```
**Resolution**:
1. Added `.terraform/` and `*.tfstate*` to `.gitignore`.
2. Performed a soft reset (`git reset origin/main`) to eliminate the large binary from commit history.
3. Re-committed only configuration files and pushed cleanly.

---

## 5. Kubernetes Orchestration with Helm

To simplify application deployment and configuration management, I authored a custom Helm chart in `voting-app-chart/`.

### Helm Chart Structure:
* **`Chart.yaml`**: Metadata defining chart name and version.
* **`values.yaml`**: Centralized values defining the global registry namespace:
  ```yaml
  global:
    username: kachdev
  ```
* **`templates/all-services.yaml`**: Unified specification for:
  * Deployments for `vote`, `redis`, `worker`, `db`, and `result`.
  * ClusterIP Services for internal routing (`redis`, `db`).
  * LoadBalancer Services for public-facing frontends (`vote` on port 80, `result` on port 80 routing to containerPort 4000).

### Deployment Command:
```bash
helm upgrade --install voting-app ./voting-app-chart
```

### Key Challenge & Resolution: Image Tag Mismatch & Rollout
Initial pods encountered `ErrImagePull` because the manifests specified `:latest`, while the initial CI pipeline only published commit SHAs. 

**Resolution**:
1. Updated `.github/workflows/deploy.yml` to publish both `:${{ github.sha }}` and `:latest`.
2. Triggered a clean pipeline build.
3. Executed a rolling restart to force Kubernetes to pull the freshly published images:
```bash
kubectl rollout restart deployment vote result worker
```

---

## 6. Verification & Final Results

### Pod Status
All five microservice pods successfully reached `Running` status:

```bash
$ kubectl get pods
NAME                      READY   STATUS    RESTARTS   AGE
db-76f46dd747-z2tmk       1/1     Running   0          10m
redis-74f58cd5db-fzvnq    1/1     Running   0          11m
result-8b4558555-nqp9j    1/1     Running   0          20s
vote-6f56f4bbff-c8gpl     1/1     Running   0          5m
worker-59bc4444c-bznlm    1/1     Running   0          20s
```

### External Services & LoadBalancers
AWS Elastic Load Balancers were provisioned and validated:

```bash
$ kubectl get svc
NAME         TYPE           CLUSTER-IP       EXTERNAL-IP                                                               PORT(S)
db           ClusterIP      10.100.60.234    <none>                                                                    5432/TCP
kubernetes   ClusterIP      10.100.0.1       <none>                                                                    443/TCP
redis        ClusterIP      10.100.44.137    <none>                                                                    6379/TCP
result       LoadBalancer   10.100.69.124    aa8797ee470a64c5fa528c06f2f8db75-1411993242.us-east-1.elb.amazonaws.com   80:31149/TCP
vote         LoadBalancer   10.100.135.115   a90e949b0bb1e4376817878a2afef4b1-1128650376.us-east-1.elb.amazonaws.com   80:31345/TCP
```

* **Vote Web Application**: Fully operational on port `80`.
* **Result Web Application**: Real-time Socket.IO score updates functioning on port `80`.

---

## 7. How to Reproduce This Deployment

### Prerequisites:
* AWS CLI v2 configured with IAM admin rights
* Terraform >= 1.3.0
* kubectl & Helm v3
* Docker Desktop

### Quickstart Commands:
```bash
# 1. Clone repository
git clone https://github.com/onemmanuel4christ/example-voting-app.git
cd example-voting-app

# 2. Provision AWS EKS Cluster
cd terraform
terraform init
terraform apply -auto-approve
aws eks update-kubeconfig --region us-east-1 --name voting-app-cluster-kachi
cd ..

# 3. Deploy Application with Helm
helm upgrade --install voting-app ./voting-app-chart

# 4. Check Cluster Status
kubectl get pods
kubectl get svc
```

---

## Conclusion

This project successfully implements modern DevOps principles:
* **Security-first**: Rootless Docker containers and vulnerability scanning in CI.
* **Reproducibility**: Infrastructure defined purely through code (Terraform).
* **Automation**: CI/CD pipeline managing testing, packaging, and registry publishing.
* **Scalability**: Cloud-native orchestration via Kubernetes and Helm.

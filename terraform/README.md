# 🚀 Enterprise-Grade MLOps Platform on AWS

### Terraform + EKS + Multi-Environment Architecture

This repository contains Infrastructure as Code (IaC) for a production-style, multi-environment MLOps platform built on AWS using Terraform.

The objective is to simulate a real-world enterprise cloud platform setup with:

* Strict environment isolation (dev / stage / prod)
* Modular Terraform architecture
* Remote state management
* Production-ready EKS clusters
* Secure container and artifact storage
* CI/CD-ready structure

---

# 🏗 Architecture Overview

Each environment (dev, stage, prod) provisions its own:

* VPC (isolated CIDR range)
* Public & Private Subnets (Multi-AZ)
* NAT Gateway
* Amazon EKS Cluster (Kubernetes 1.35)
* Managed Node Group (AL2023)
* Amazon ECR Repository
* Amazon S3 Bucket (ML artifacts)
* Remote Terraform State (S3 backend with lockfile)

This simulates a real enterprise landing zone inside a single AWS account.

---

# 🌐 Environment Isolation Strategy

Each environment has:

| Environment | VPC CIDR    | State Key               | Cluster Name        |
| ----------- | ----------- | ----------------------- | ------------------- |
| DEV         | 10.0.0.0/16 | dev/terraform.tfstate   | mlops-dev-cluster   |
| STAGE       | 10.1.0.0/16 | stage/terraform.tfstate | mlops-stage-cluster |
| PROD        | 10.2.0.0/16 | prod/terraform.tfstate  | mlops-prod-cluster  |

Isolation is achieved through:

* Separate state files
* Separate VPCs
* Separate ECR repositories
* Separate S3 artifact buckets
* Environment-specific tagging

---

# 📁 Project Structure

```
mlops-platform/
│
├── modules/
│   ├── vpc/                # Reusable VPC module (environment-aware)
│   ├── eks/                # EKS wrapper module
│   ├── ecr/                # Container registry module
│   └── s3/                 # Artifact storage module
│
├── environments/
│   ├── dev/
│   ├── stage/
│   └── prod/
│       ├── backend.tf
│       ├── main.tf
│       ├── provider.tf
│       ├── variables.tf
│       ├── versions.tf
│       └── terraform.tfvars
│
└── .gitignore
```

---

# 🔐 Remote State Management

Terraform state is stored remotely using:

* Amazon S3
* `use_lockfile = true` (modern locking mechanism)

Each environment has its own state key:

```
dev/terraform.tfstate
stage/terraform.tfstate
prod/terraform.tfstate
```

Benefits:

* State isolation
* Safe parallel applies
* No local state dependency
* Reduced risk of corruption

DynamoDB is intentionally not used (modern S3 lockfile approach).

---

# ☸ Kubernetes Configuration

EKS Configuration:

* Kubernetes Version: 1.35
* Managed Node Groups
* AMI: AL2023_x86_64_STANDARD
* Capacity Type: ON_DEMAND
* IRSA enabled
* Private subnets for worker nodes
* Environment-based scaling

Production hardening includes:

* Environment-specific node sizing
* CIDR separation
* Strict tagging strategy

---

# 📦 Platform Components

## 🌐 Networking

* Dedicated VPC per environment
* Multi-AZ public & private subnets
* Internet Gateway
* NAT Gateway
* Route tables per subnet tier

## ☸ Kubernetes

* Amazon EKS (Managed Control Plane)
* Managed Node Groups
* IRSA enabled

## 📦 Container Registry

* Amazon ECR
* Image scanning enabled
* Immutable tags
* Lifecycle policies

## 🗂 Artifact Storage

* Amazon S3
* Versioning enabled
* Server-side encryption
* Public access blocked

---

# ⚙️ Prerequisites

* AWS Account
* IAM user or role with sufficient permissions
* AWS CLI configured
* Terraform >= 1.4
* kubectl
* Git

---

# 🔑 Authentication

Configure AWS credentials locally:

```bash
aws configure
```

No credentials are stored in this repository.

---

# 🚀 Deployment Steps

## Deploy DEV

```bash
cd environments/dev
terraform init
terraform plan
terraform apply
```

## Deploy STAGE

```bash
cd environments/stage
terraform init
terraform plan
terraform apply
```

## Deploy PROD

```bash
cd environments/prod
terraform init
terraform plan
terraform apply
```

---

# 🔥 Destroy When Not In Use

```bash
terraform destroy
```

⚠️ Always destroy non-production environments to avoid unnecessary costs.

---

# 💰 Cost Considerations

Each environment provisions:

* EKS control plane (billable)
* NAT Gateway (billable)
* EC2 instances (node groups)
* Elastic IP
* CloudWatch logs

Running all environments simultaneously will incur costs.

Recommended practice:

* Keep DEV active
* Destroy STAGE when not needed
* Apply PROD only when required

---

# 🧠 Design Principles

* Modular Terraform architecture
* Explicit module contracts
* Strict environment isolation
* Provider version pinning
* Remote backend with locking
* Production-style networking
* No hardcoded shared infrastructure
* Reusable environment-aware modules

---

# 🔒 Security Practices

* No credentials in repository
* `.terraform` ignored
* State file not committed
* S3 state encryption
* Public access blocked for artifact buckets
* IRSA enabled (no static AWS keys in pods)
* Environment-specific resource naming

---

# 📈 Next Roadmap (Platform Maturity)

Planned enhancements:

* EKS control plane logging
* Metrics server
* Horizontal Pod Autoscaler
* Karpenter (node autoscaling)
* AWS Load Balancer Controller
* Ingress-based routing
* CI/CD (GitHub Actions)
* Monitoring stack (Prometheus + Grafana)
* Cost optimization improvements

---

# 🎯 Objective

This project demonstrates:

* Enterprise-grade Terraform practices
* Multi-environment AWS architecture
* Production-style Kubernetes platform setup
* Secure MLOps-ready infrastructure
* Infrastructure automation best practices

Built as both:

* A learning platform
* A portfolio-ready cloud engineering project

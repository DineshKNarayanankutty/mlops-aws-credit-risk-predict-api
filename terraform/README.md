# MLOps AWS Infrastructure — Terraform

This repository contains the Terraform infrastructure code for the **MLOps Platform** on AWS. It provisions a full end-to-end MLOps stack including networking, compute, container registry, model registry, CI/CD pipelines, and monitoring — across three environments: `dev`, `stage`, and `prod`.

---

## Repository Structure

```
.
├── environments/
│   ├── dev/
│   │   ├── backend.tf
│   │   ├── main.tf
│   │   ├── provider.tf
│   │   ├── terraform.tfvars
│   │   ├── variables.tf
│   │   └── versions.tf
│   ├── stage/
│   │   ├── backend.tf
│   │   ├── main.tf
│   │   ├── provider.tf
│   │   ├── terraform.tfvars
│   │   ├── variables.tf
│   │   └── versions.tf
│   └── prod/
│       ├── backend.tf
│       ├── main.tf
│       ├── provider.tf
│       ├── terraform.tfvars
│       ├── variables.tf
│       └── versions.tf
└── modules/
    ├── vpc/
    ├── eks/
    ├── ecr/
    ├── s3/
    ├── sagemaker/
    ├── iam/
    ├── cicd/
    ├── alb_controller/
    └── monitoring/
```

---

## Architecture Overview

| Module | Purpose |
|---|---|
| `vpc` | VPC, public/private subnets, IGW, NAT Gateway |
| `eks` | EKS cluster, managed node groups, KMS-encrypted EBS, ALB backend SG |
| `ecr` | ECR repository with image scanning and lifecycle policy |
| `s3` | General-purpose S3 bucket with KMS encryption and access logging |
| `sagemaker` | SageMaker model artifacts bucket, model package group, execution role |
| `iam` | IRSA roles for inference, ALB controller, CodeBuild, CodePipeline, SageMaker |
| `cicd` | CodePipeline with GitHub source → ECR image build → SageMaker training stages |
| `alb_controller` | AWS Load Balancer Controller via Helm with optional IRSA role creation |
| `monitoring` | Prometheus, Grafana, metrics-server via Helm + optional CloudWatch Container Insights |

---

## Environment Differences

| Feature | dev | stage | prod |
|---|---|---|---|
| AZ count | 1 | 2 | 3 |
| NAT Gateway | Single | Single | Per-AZ |
| Node instance type | `t3.small` | `t3.medium` | Configurable |
| Inference node group | ❌ | ✅ | ✅ |
| Cluster autoscaler | ❌ | ❌ | ✅ |
| EKS public endpoint | ✅ | ❌ | ✅ |
| ALB Controller | ❌ | ✅ | ✅ |
| Monitoring stack | ❌ | ✅ | ✅ |
| CloudWatch Container Insights | ❌ | ❌ | ✅ |
| Model package group | ❌ | ✅ | ✅ |
| Log retention | 3 days | 7 days | 30 days |

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= `1.6.0`
- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate credentials
- An S3 bucket for Terraform remote state (`mlops-aws-credit-risk-s3`)
- A [CodeStar Connection](https://docs.aws.amazon.com/dtconsole/latest/userguide/connections.html) ARN for GitHub integration

### Provider Versions

| Provider | Version |
|---|---|
| `hashicorp/aws` | `~> 5.100` |
| `hashicorp/kubernetes` | `~> 2.35` |
| `hashicorp/helm` | `~> 2.13` |

---

## Remote State Backend

State is stored in S3 with native locking (`use_lockfile = true`) and encryption enabled. Each environment uses a separate state key:

| Environment | State Key |
|---|---|
| dev | `dev/terraform.tfstate` |
| stage | `stage/terraform.tfstate` |
| prod | `prod/terraform.tfstate` |

---

## Getting Started

### 1. Configure `terraform.tfvars`

Before deploying, update the placeholder values in the environment's `terraform.tfvars`:

```hcl
codestar_connection_arn   = "arn:aws:codestar-connections:..."
github_full_repository_id = "your-org/your-repo"
```

### 2. Initialize and Deploy

```bash
# Navigate to the desired environment
cd environments/dev   # or stage / prod

# Initialize Terraform with the remote backend
terraform init

# Preview changes
terraform plan

# Apply
terraform apply
```

---

## Module Details

### `vpc`
Provisions a VPC with environment-aware AZ count (1/2/3 for dev/stage/prod), public and private subnets, an Internet Gateway, and NAT Gateways (single for dev/stage, one per AZ for prod). Subnet CIDRs are sliced automatically based on the target AZ count.

### `eks`
Deploys an EKS cluster using the `terraform-aws-modules/eks` module with:
- **System** node group on all environments
- **Inference** node group (with `workload=inference` taint) on stage and prod
- KMS-encrypted EBS volumes for all nodes
- A dedicated ALB backend security group scoped to NodePort range
- Cluster autoscaler IRSA role (prod only)
- Full control plane logging with environment-based retention

### `ecr`
Creates an ECR repository with:
- `IMMUTABLE` image tags
- Scan on push enabled
- AES256 encryption
- Lifecycle policy to expire untagged images after 14 days

### `s3`
General-purpose S3 module with KMS encryption (creates key if not provided), versioning, access logging to a companion log bucket, lifecycle policy for noncurrent version expiry, and TLS-only bucket policy.

### `sagemaker`
Provisions the SageMaker model artifacts S3 bucket with KMS encryption and access logging, a SageMaker execution IAM role with scoped ECR and S3 access, and a model package group (skipped in dev).

### `iam`
Creates all IRSA and service roles:
- **Inference IRSA** — S3 read for model artifacts, ECR pull, KMS decrypt
- **CodeBuild** — CloudWatch logs, S3 artifacts, ECR push/pull, SageMaker training, IAM PassRole
- **CodePipeline** — S3 artifacts, CodeStar connection, CodeBuild invocation
- **SageMaker Training** — S3 read/write for training data and artifacts, ECR pull, KMS, CloudWatch logs
- **ALB Controller IRSA** — Full ELB/EC2/WAF management permissions

### `cicd`
Provisions a three-stage CodePipeline:
1. **Source** — GitHub via CodeStar connection
2. **Build** — Docker image build and push to ECR
3. **Train** — Triggers a SageMaker training job

Artifacts are stored in a KMS-encrypted S3 bucket with versioning, access logging, and a TLS-only bucket policy.

### `alb_controller`
Installs the AWS Load Balancer Controller via Helm. Supports optional IRSA role creation or accepting an existing role ARN. Configures a dedicated shared backend security group for ALB-to-node traffic.

### `monitoring`
Installs the monitoring stack via Helm with feature toggles for each component:
- **Prometheus** — with persistent volume and Alertmanager
- **Grafana** — with persistence and internal ALB service
- **metrics-server** — for HPA support on EKS
- **CloudWatch Container Insights** — EKS addon (prod only)

---

## Security Highlights

- All S3 buckets have public access fully blocked and TLS-only bucket policies
- EBS volumes on EKS nodes are KMS-encrypted
- SageMaker model artifacts are KMS-encrypted at rest
- CI/CD artifact buckets use KMS encryption with key rotation enabled
- EKS secrets are encrypted via a cluster-managed KMS key
- IRSA (IAM Roles for Service Accounts) used throughout — no static credentials on pods
- EKS API server endpoint access is private-only in stage

---

## Contributing

1. Create a feature branch from `main`
2. Make changes to the relevant module or environment
3. Run `terraform fmt` and `terraform validate` before committing
4. Open a pull request — the CI pipeline will run `terraform plan` automatically

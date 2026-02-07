# DevOps CI/CD Pipeline Project

A production-ready CI/CD pipeline deploying a Node.js backend and NGINX frontend to AWS EKS using Jenkins, Docker, Kubernetes, and Terraform.

## Project Structure

```
.
├── backend/              # Express.js backend API
│   ├── Dockerfile        # Backend container image
│   ├── package.json      # Node.js dependencies
│   ├── server.js         # Express server
│   └── .dockerignore     # Docker build exclusions
├── frontend/             # Static frontend application
│   ├── Dockerfile        # Frontend container image
│   ├── index.html        # Static HTML page
│   └── .dockerignore     # Docker build exclusions
├── k8s/                  # Kubernetes manifests
│   ├── backend-deploy.yml
│   ├── backend-service.yml
│   ├── frontend-deploy.yml
│   ├── frontend-service.yml
│   └── ingress.yml       # AWS ALB Ingress
├── terraform/            # Infrastructure as Code
│   ├── provider.tf       # AWS provider configuration
│   ├── backend.tf        # S3 remote state configuration
│   ├── main.tf           # VPC, subnets, EKS cluster
│   ├── node-group.tf     # EKS node group with IAM roles
│   ├── variables.tf      # Input variables
│   └── outputs.tf        # Output values
├── Jenkinsfile           # CI/CD pipeline definition
└── user-data.sh          # EC2 bootstrap script for Jenkins server
```

## Prerequisites

### Local Development

- Docker Desktop
- Node.js 18+
- kubectl CLI
- AWS CLI v2
- Terraform 1.0+
- Git

### AWS Account

- AWS account with appropriate IAM permissions
- S3 bucket for Terraform state (e.g., `tf-state-prod`)
- DynamoDB table for Terraform locks (e.g., `tf-locks`)
- ECR repository for Docker images

## Setup Instructions

### 1. Prepare AWS Infrastructure

#### Create S3 bucket for Terraform state:
```bash
aws s3 mb s3://tf-state-prod --region ap-south-1 --create-bucket-configuration LocationConstraint=ap-south-1
```

#### Create DynamoDB table for Terraform locks:
```bash
aws dynamodb create-table \
  --table-name tf-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-south-1
```

#### Create ECR repositories:
```bash
aws ecr create-repository --repository-name backend --region ap-south-1
aws ecr create-repository --repository-name frontend --region ap-south-1
```

### 2. Deploy Infrastructure with Terraform

```bash
cd terraform/

# Initialize Terraform (configures remote state)
terraform init

# Review planned changes
terraform plan

# Apply infrastructure (creates VPC, EKS cluster, node group)
terraform apply

# Save outputs
terraform output > deployment_outputs.txt
```

### 3. Configure kubectl

After EKS cluster is created, update kubeconfig:
```bash
aws eks update-kubeconfig --name devops-eks-cluster --region ap-south-1
```

Verify cluster access:
```bash
kubectl get nodes
```

### EKS Access & RBAC Setup

This cluster uses **CONFIG_MAP** authentication mode. RBAC access is managed via the `aws-auth` ConfigMap.

Add the Jenkins EC2 IAM Role to `aws-auth`:
```bash
kubectl edit configmap aws-auth -n kube-system
```

Add:
```yaml
- rolearn: arn:aws:iam::<ACCOUNT_ID>:role/Jenkins-EC2-Role
  username: jenkins
  groups:
    - system:masters
```

Note: `aws eks create-access-entry` will fail for clusters using CONFIG_MAP mode.

### 4. Install ALB Ingress Controller (required for Ingress)

```bash
# 1) Associate OIDC provider (IRSA prerequisite)
eksctl utils associate-iam-oidc-provider \
  --region ap-south-1 \
  --cluster devops-eks-cluster \
  --approve

# 2) Create IAM policy for the AWS Load Balancer Controller
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json

# 3) Create IAM ServiceAccount (IRSA)
eksctl create iamserviceaccount \
  --cluster devops-eks-cluster \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --attach-policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve

# 4) Install controller via Helm using the IRSA ServiceAccount
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=devops-eks-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

Verify installation:
```bash
kubectl get sa -n kube-system aws-load-balancer-controller
kubectl get deployment -n kube-system aws-load-balancer-controller
```

### 5. Local Testing (Optional)

#### Test Backend:
```bash
cd backend/

# Install dependencies
npm install

# Run locally
npm start

# In another terminal, test the API
curl http://localhost:3000/api
curl http://localhost:3000/health
```

#### Test Frontend:
```bash
cd frontend/

# Build the image
docker build -t frontend:local .

# Run the container
docker run -p 8080:80 frontend:local

# Open http://localhost:8080 in a browser
```

### 6. Configure Jenkins for CI/CD

#### Create Jenkins Credentials:

In Jenkins UI (Admin → Manage Jenkins → Manage Credentials):

1. **ECR_REGISTRY_URL** (Secret text)
   - Value: `<YOUR_AWS_ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com`

2. **aws-credentials** (IAM Role via EC2 Instance Profile). Use an attached IAM Role on the Jenkins EC2 instance instead of static keys. Do not store `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` in Jenkins. Required IAM policies for Jenkins EC2 Role: AmazonEKSClusterPolicy, AmazonEKSWorkerNodePolicy, AmazonEC2ContainerRegistryFullAccess, AmazonS3FullAccess (only if using S3 artifacts).

#### Create Pipeline Job:

1. New Item → Pipeline
2. Name: `devops-ci-cd-pipeline`
3. Definition: Pipeline script from SCM
4. SCM: Git
   - Repository URL: `<YOUR_GIT_REPO>`
   - Branch: `*/main`
5. Script Path: `Jenkinsfile`
6. Save and Build
7.

### 7. Deploy Applications to EKS

#### Option A: Manual Deployment

```bash
# Update image references in k8s manifests
# Replace <REGISTRY_URI> with your ECR repository URI

# Deploy all resources
kubectl apply -f k8s/

# Verify deployments
kubectl get deployments
kubectl get services
kubectl get ingress

# Get ALB DNS name
kubectl get ingress app-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

#### Option B: Jenkins Pipeline

Push code to Git repository with Jenkinsfile. Jenkins will:
1. Build Docker images
2. Push to ECR
3. Update Kubernetes manifests
4. Deploy to EKS cluster

## Application Access

After successful deployment:

```bash
# Get the ALB DNS endpoint
ALB_DNS=$(kubectl get ingress app-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Access frontend
curl http://$ALB_DNS/

# Access backend API
curl http://$ALB_DNS/api

# Check backend health
curl http://$ALB_DNS/api/health
```

## Monitoring and Logs

### Check Pod Status:
```bash
kubectl get pods
kubectl describe pod <pod-name>
```

### View Pod Logs:
```bash
# Backend logs
kubectl logs -l app=backend -f

# Frontend logs
kubectl logs -l app=frontend -f
```

### Scaling Deployments:
```bash
# Scale backend to 3 replicas
kubectl scale deployment backend-deployment --replicas=3

# Scale frontend to 3 replicas
kubectl scale deployment frontend-deployment --replicas=3
```

## Cleanup

### Delete Kubernetes Resources:
```bash
kubectl delete -f k8s/
```

### Destroy AWS Infrastructure:
```bash
cd terraform/
terraform destroy
```

## Environment Variables

### Backend (server.js)

- `PORT`: Server port (default: 3000)

### Terraform (terraform/variables.tf)

- `vpc_name`: VPC name
- `vpc_cidr`: VPC CIDR block (default: 10.0.0.0/16)
- `availability_zone_1`: First AZ (default: ap-south-1a)
- `availability_zone_2`: Second AZ (default: ap-south-1b)

## Troubleshooting

### EKS Cluster not accessible
```bash
# Verify cluster exists
aws eks describe-cluster --name devops-eks-cluster --region ap-south-1

# Update kubeconfig
aws eks update-kubeconfig --name devops-eks-cluster --region ap-south-1
```

### Ingress ADDRESS is empty
Check controller pods:
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

Verify ServiceAccount exists:
```bash
kubectl get sa -n kube-system aws-load-balancer-controller
```

Verify OIDC provider is associated (IRSA):
```bash
eksctl utils describe-iam-oidc-provider --cluster devops-eks-cluster --region ap-south-1
```

Verify subnets are tagged for ELB:
`kubernetes.io/role/elb=1` (public) and `kubernetes.io/role/internal-elb=1` (private).

### Pods in Pending state
```bash
# Check node capacity
kubectl describe nodes

# Check ingress controller status
kubectl get deployment -n kube-system aws-load-balancer-controller
```

### Images not pulling from ECR
```bash
# Verify ECR repository and images exist
aws ecr describe-repositories --region ap-south-1
aws ecr list-images --repository-name backend --region ap-south-1

# Check kubeconfig can access ECR
aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin <AWS_ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com
```

## Common Errors & Fixes

- `kubectl error: You must be logged in to the server` â†’ Fix via `aws-auth` ConfigMap mapping.
- `aws eks update-kubeconfig` works but `kubectl` is denied â†’ RBAC issue (missing role mapping).
- `aws-load-balancer-controller` READY 0/2 â†’ IRSA or ServiceAccount missing.
- Ingress ADDRESS empty â†’ Controller not running or ingress.class misconfigured.

## Best Practices Implemented

✅ IaC with Terraform for reproducible infrastructure
✅ Container images with health checks
✅ Kubernetes manifests with proper labels and selectors
✅ Service discovery with Kubernetes Services
✅ Ingress for external traffic routing
✅ Multi-az deployment with 2 replicas
✅ Private subnets for EKS nodes
✅ NAT Gateway for outbound traffic
✅ CORS enabled backend API
✅ CI/CD pipeline with Jenkins
✅ Proper logging and monitoring hooks
✅ Secrets management via AWS credentials

## Security Considerations

- Subnets use private/public configuration with NAT Gateway
- EKS cluster has proper IAM roles and policies
- Security groups restrict traffic appropriately
- Recommended: Use private registries and image scanning
- Recommended: Enable EKS audit logging
- Recommended: Use Kubernetes network policies

## Security Best Practices

- Avoid committing AWS credentials to Git.
- Prefer IAM Roles for EC2 and IRSA for Kubernetes controllers.

## Cost Optimization

- t3.medium instance type for node group (cost-effective)
- Auto-scaling configured (min: 1, max: 4 nodes)
- Use spot instances for additional savings (modify terraform)
- Clean up unused resources regularly

## Support & Documentation

- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Kubernetes Official Documentation](https://kubernetes.io/docs/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
- [Jenkins Pipeline Documentation](https://www.jenkins.io/doc/book/pipeline/)

---

**Last Updated:** February 2026
**Kubernetes Version:** 1.29
**AWS Region:** ap-south-1

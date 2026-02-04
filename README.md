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

### 4. Install ALB Ingress Controller (required for Ingress)

```bash
# Add AWS ELB controller Helm chart repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install ALB ingress controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=devops-eks-cluster
```

Verify installation:
```bash
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

2. **aws-credentials** (AWS Credentials)
   - AWS Access Key ID: `<YOUR_ACCESS_KEY>`
   - AWS Secret Access Key: `<YOUR_SECRET_KEY>`

#### Create Pipeline Job:

1. New Item → Pipeline
2. Name: `devops-ci-cd-pipeline`
3. Definition: Pipeline script from SCM
4. SCM: Git
   - Repository URL: `<YOUR_GIT_REPO>`
   - Branch: `*/main`
5. Script Path: `Jenkinsfile`
6. Save and Build

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

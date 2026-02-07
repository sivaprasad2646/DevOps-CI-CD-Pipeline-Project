pipeline {
  agent any

  // Build automatically on GitHub push webhook
  triggers {
    githubPush()
  }

  environment {
    AWS_REGION = 'ap-south-1'
    ECR_REGISTRY_URL = '772876499232.dkr.ecr.ap-south-1.amazonaws.com/devops-ci-cd-pipeline-peoject'
    IMAGE_TAG = "${BUILD_NUMBER}-${GIT_COMMIT.take(7)}"
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        echo "Repository checked out successfully"
      }
    }

    stage('Build Images') {
      steps {
        script {
          echo "Building Docker images..."
          sh '''
          docker build -t backend:${IMAGE_TAG} backend/
          docker build -t frontend:${IMAGE_TAG} frontend/
          docker tag backend:${IMAGE_TAG} backend:latest
          docker tag frontend:${IMAGE_TAG} frontend:latest
          '''
        }
      }
    }

    stage('Push to Registry') {
      steps {
        script {
          echo "Logging in to ECR and pushing images..."
          sh '''
          aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY_URL}
          docker tag backend:${IMAGE_TAG} ${ECR_REGISTRY_URL}/backend:${IMAGE_TAG}
          docker tag backend:latest ${ECR_REGISTRY_URL}/backend:latest
          docker push ${ECR_REGISTRY_URL}/backend:${IMAGE_TAG}
          docker push ${ECR_REGISTRY_URL}/backend:latest
          
          docker tag frontend:${IMAGE_TAG} ${ECR_REGISTRY_URL}/frontend:${IMAGE_TAG}
          docker tag frontend:latest ${ECR_REGISTRY_URL}/frontend:latest
          docker push ${ECR_REGISTRY_URL}/frontend:${IMAGE_TAG}
          docker push ${ECR_REGISTRY_URL}/frontend:latest
          '''
        }
      }
    }

    stage('Update K8s Manifests') {
      steps {
        script {
          echo "Updating Kubernetes manifests with new image tags..."
          sh '''
          sed -i "s|image: backend:1|image: ${ECR_REGISTRY_URL}/backend:${IMAGE_TAG}|g" k8s/backend-deploy.yml
          sed -i "s|image: frontend:1|image: ${ECR_REGISTRY_URL}/frontend:${IMAGE_TAG}|g" k8s/frontend-deploy.yml
          '''
        }
      }
    }

    stage('Deploy to EKS') {
      steps {
        script {
          echo "Applying Kubernetes manifests to EKS cluster..."
          withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-credentials']]) {
            sh '''
            aws eks update-kubeconfig --name devops-eks-cluster --region ${AWS_REGION}
            kubectl apply -f k8s/
            kubectl rollout status deployment/backend-deployment -n default --timeout=5m
            kubectl rollout status deployment/frontend-deployment -n default --timeout=5m
            '''
          }
        }
      }
    }

    stage('Verify Deployment') {
      steps {
        script {
          echo "Verifying deployment status..."
          sh '''
          kubectl get deployments
          kubectl get services
          kubectl get ingress
          kubectl get pods
          '''
        }
      }
    }
  }

  post {
    always {
      echo "Pipeline execution completed"
    }
    failure {
      echo "Pipeline failed! Check logs above for details"
    }
    success {
      echo "Deployment successful! Services are running on EKS"
    }
  }
}

#!/bin/bash
set -euxo pipefail

LOGFILE="/var/log/devops-install.log"
exec > >(tee -a $LOGFILE) 2>&1

echo "===== Starting DevOps setup ====="
sleep 20

# -----------------------------------
# Update system
# -----------------------------------
apt-get update -y
apt-get upgrade -y

# -----------------------------------
# Install base packages
# -----------------------------------
apt-get install -y \
  curl \
  wget \
  unzip \
  gnupg \
  ca-certificates \
  lsb-release \
  apt-transport-https \
  software-properties-common

# -----------------------------------
# Install Java (required for Jenkins)
# -----------------------------------
apt-get install -y openjdk-17-jdk

# -----------------------------------
# Install Docker
# -----------------------------------
echo "Installing Docker..."
curl -fsSL https://get.docker.com | bash
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu || true

# -----------------------------------
# Install Jenkins (LATEST LTS .deb)
# -----------------------------------
echo "Installing latest Jenkins LTS..."

cd /tmp
JENKINS_VERSION="2.479.1"
wget https://pkg.jenkins.io/debian-stable/binary/jenkins_${JENKINS_VERSION}_all.deb

systemctl stop jenkins || true
dpkg -i jenkins_${JENKINS_VERSION}_all.deb || true
apt-get --fix-broken install -y

systemctl daemon-reload
systemctl enable jenkins
systemctl restart jenkins

# -----------------------------------
# Install kubectl
# -----------------------------------
echo "Installing kubectl..."
curl -LO https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# -----------------------------------
# Install AWS CLI v2
# -----------------------------------
echo "Installing AWS CLI v2..."
cd /tmp
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# -----------------------------------
# Add swap (prevents Jenkins crashes)
# -----------------------------------
echo "Adding swap memory..."
fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# -----------------------------------
# Final verification
# -----------------------------------
echo "===== INSTALLATION COMPLETE ====="
docker --version || true
java --version || true
kubectl version --client || true
aws --version || true
jenkins --version || true

echo "Jenkins password:"
cat /var/lib/jenkins/secrets/initialAdminPassword || true

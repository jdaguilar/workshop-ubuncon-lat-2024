#!/bin/bash

# Function to print messages with formatting
function info() {
    echo -e "\e[32m* $1\e[0m"
}

function warn() {
    echo -e "\e[33m* WARNING: $1\e[0m"
}

function error() {
    echo -e "\e[31m* ERROR: $1\e[0m"
    exit 1
}

# Install microk8s
info "Installing Snap MicroK8S..."
sudo snap install microk8s --channel=1.28-strict/stable

# Set alias for kubectl
info "Setting alias 'kubectl' to microk8s.kubectl"
sudo snap alias microk8s.kubectl kubectl

# Add user to microk8s group
info "Adding user ${USER} to microk8s group..."
sudo usermod -a -G snap_microk8s $USER || error "Failed to add user to group"

# Create and manage ~/.kube directory
info "Creating and setting ownership of '~/.kube' directory..."
mkdir -p ~/.kube
sudo chown -f -R $USER ~/.kube
sudo chmod -R a+r ~/.kube || error "Failed to manage ~/.kube directory"

# Wait for microk8s to be ready
info "Waiting for microk8s to be ready..."
sudo microk8s status --wait-ready || error "Microk8s is not ready"

# Generate kubeconfig
info "Generating Kubernetes configuration file..."
sudo microk8s config | tee ~/.kube/config || error "Failed to generate kubeconfig"

# Enable RBAC
info "Enabling RBAC..."
sudo microk8s enable rbac || error "Failed to enable RBAC"

# Enable storage options
info "Enabling storage and hostpath-storage..."
sudo microk8s enable storage hostpath-storage || error "Failed to enable storage options"

# Enable metallb and get IP address
info "Enabling metallb and configuring..."

# Check if jq is installed
if
    ! jq -V
then
    warn "jq is not installed. Load balancing configuration might fail."
fi
IPADDR=$(ip -4 -j route get 2.2.2.2 | jq -r '.[] | .prefsrc')

if [[ -z "$IPADDR" ]]; then
    warn "Failed to retrieve IP address. Load balancing might not work."
else
    sudo microk8s enable metallb:"$IPADDR-$IPADDR" || error "Failed to enable metallb"
fi

# Install Snap AWS-CLI (assuming classic mode)
info "Installing Snap AWS-CLI..."
sudo snap install aws-cli --classic || error "Failed to install AWS-CLI"

# Install Snap Spark Client
info "Installing Snap Spark Client..."
sudo snap install spark-client --channel 3.4/edge || error "Failed to install Spark Client"

# Create Spark namespace
info "Creating namespace 'spark'..."
sudo kubectl create namespace spark

# Create service account and configure Spark settings

# Check if spark-client.service-account-registry command exists
if ! command -v spark-client.service-account-registry &>/dev/null; then
    error "spark-client.service-account-registry command not found. Skipping Spark configuration."
fi

info "Creating service account for Spark..."
spark-client.service-account-registry create \
    --username spark --namespace spark

info "Getting service account configuration..."
spark-client.service-account-registry get-config \
    --username spark --namespace spark

# View resources
info "View service accounts"
sudo kubectl get serviceaccounts -n spark

info "View roles"
sudo kubectl get roles -n spark

info "View role bindings"
sudo kubectl get rolebindings -n spark

info "Add Extra Settings to Service Account"

read -p "Set AWS Access Key (default: minio_user): " AWS_ACCESS_KEY
[[ -z "$AWS_ACCESS_KEY" ]] && AWS_ACCESS_KEY="minio_user"

read -p "Set AWS Secret Key (default: minio_password): " AWS_SECRET_KEY
[[ -z "$AWS_SECRET_KEY" ]] && AWS_SECRET_KEY="minio_password"

read -p "Set AWS S3 Endpoint (default: http://$IPADDR:9000): " AWS_S3_ENDPOINT
[[ -z "$AWS_S3_ENDPOINT" ]] && AWS_S3_ENDPOINT="http://$IPADDR:9000"


spark-client.service-account-registry add-config \
    --username spark --namespace spark \
    --conf spark.eventLog.enabled=true \
    --conf spark.eventLog.dir=s3a://logs/spark-events/ \
    --conf spark.history.fs.logDirectory=s3a://logs/spark-events/ \
    --conf spark.hadoop.fs.s3a.aws.credentials.provider=org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider \
    --conf spark.hadoop.fs.s3a.connection.ssl.enabled=false \
    --conf spark.hadoop.fs.s3a.path.style.access=true \
    --conf spark.hadoop.fs.s3a.access.key=$AWS_ACCESS_KEY \
    --conf spark.hadoop.fs.s3a.endpoint=$AWS_S3_ENDPOINT \
    --conf spark.hadoop.fs.s3a.secret.key=$AWS_SECRET_KEY \
    --conf spark.kubernetes.namespace=spark

spark-client.service-account-registry get-config \
  --username spark --namespace spark

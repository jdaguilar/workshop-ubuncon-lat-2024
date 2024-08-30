#!/usr/bin/env bash

set -euo pipefail

# Global variable
export MINIO_PROFILE_NAME="minio-local"

# Function definitions
print_info() { echo -e "\e[32m* $1\e[0m"; }
print_warn() { echo -e "\e[33m* WARNING: $1\e[0m"; }
print_error() {
    echo -e "\e[31m* ERROR: $1\e[0m"
    exit 1
}

install_microk8s() {
    print_info "Installing Snap MicroK8S..."
    sudo snap install microk8s --channel=1.28-strict/stable

    print_info "Setting alias 'kubectl' to microk8s.kubectl"
    sudo snap alias microk8s.kubectl kubectl

    print_info "Adding user ${USER} to microk8s group..."
    sudo usermod -a -G snap_microk8s "$USER" || print_error "Failed to add user to group"

    print_info "Creating and setting ownership of '~/.kube' directory..."
    mkdir -p ~/.kube
    sudo chown -f -R "$USER" ~/.kube
    sudo chmod -R a+r ~/.kube || print_error "Failed to manage ~/.kube directory"

    print_info "Waiting for microk8s to be ready..."
    sudo microk8s status --wait-ready || print_error "Microk8s is not ready"

    print_info "Generating Kubernetes configuration file..."
    sudo microk8s config >~/.kube/config || print_error "Failed to generate kubeconfig"

    print_info "Enabling RBAC..."
    sudo microk8s enable rbac || print_error "Failed to enable RBAC"

    print_info "Enabling storage and hostpath-storage..."
    sudo microk8s enable storage hostpath-storage || print_error "Failed to enable storage options"
}

configure_metallb() {
    print_info "Enabling metallb and configuring..."

    if ! command -v jq &>/dev/null; then
        print_warn "jq is not installed. Load balancing configuration might fail."
    fi

    local ipaddr
    ipaddr=$(ip -4 -j route get 2.2.2.2 | jq -r '.[] | .prefsrc')

    if [[ -z "$ipaddr" ]]; then
        print_warn "Failed to retrieve IP address. Load balancing might not work."
    else
        sudo microk8s enable metallb:"$ipaddr-$ipaddr" || print_error "Failed to enable metallb"
    fi
}

install_additional_tools() {
    print_info "Installing Snap AWS-CLI..."
    sudo snap install aws-cli --classic || print_error "Failed to install AWS-CLI"

    print_info "Installing Snap Spark Client..."
    sudo snap install spark-client --channel 3.4/edge || print_error "Failed to install Spark Client"
}

configure_spark() {

    print_info "Creating namespace 'spark'..."

    kubectl get namespace | grep -q "^spark " || kubectl create namespace spark

    if ! command -v spark-client.service-account-registry &>/dev/null; then
        print_error "spark-client.service-account-registry command not found. Skipping Spark configuration."
    fi

    print_info "Creating service account for Spark..."

    kubectl get serviceaccount -n spark | grep -q "^spark " || spark-client.service-account-registry create --username spark --namespace spark

    print_info "Getting service account configuration..."
    spark-client.service-account-registry get-config --username spark --namespace spark

    print_info "View service accounts"
    kubectl get serviceaccounts -n spark

    print_info "View roles"
    kubectl get roles -n spark

    print_info "View role bindings"
    kubectl get rolebindings -n spark
}

deploy_minio_microk8s() {
    print_info "Enabling MinIO through microk8s"

    sudo cp /var/snap/microk8s/common/addons/core/addons/minio/enable tmp_minio_fix/backups/enable.backup
    sudo cp tmp_minio_fix/enable /var/snap/microk8s/common/addons/core/addons/minio/enable
    sudo chmod 755 /var/snap/microk8s/common/addons/core/addons/minio/enable
    sudo chmod 755 tmp_minio_fix/backups/enable.backup

    sudo microk8s enable minio

    export AWS_ACCESS_KEY=$(kubectl get secret -n minio-operator microk8s-user-1 -o jsonpath='{.data.CONSOLE_ACCESS_KEY}' | base64 -d)
    export AWS_SECRET_KEY=$(kubectl get secret -n minio-operator microk8s-user-1 -o jsonpath='{.data.CONSOLE_SECRET_KEY}' | base64 -d)

    # Wait for the MinIO service to be ready
    while ! kubectl get service minio -n minio-operator &>/dev/null; do
        print_info "Waiting for MinIO service to be ready..."
        sleep 10
    done

    export AWS_S3_ENDPOINT=$(kubectl get service minio -n minio-operator -o jsonpath='{.spec.clusterIP}')

    # Configure AWS CLI profile for MinIO
    aws configure set aws_access_key_id "$AWS_ACCESS_KEY" --profile "$MINIO_PROFILE_NAME"
    aws configure set aws_secret_access_key "$AWS_SECRET_KEY" --profile "$MINIO_PROFILE_NAME"
    aws configure set region "us-west-2" --profile "$MINIO_PROFILE_NAME"
    aws configure set endpoint_url "http://$AWS_S3_ENDPOINT" --profile "$MINIO_PROFILE_NAME"

    print_info "AWS CLI configuration for MinIO has been set under the profile '$MINIO_PROFILE_NAME'"
    print_info "To use this profile, add --profile $MINIO_PROFILE_NAME to your AWS CLI commands"

    local minio_ui_ip minio_ui_port minio_ui_url
    minio_ui_ip=$(kubectl get service microk8s-console -n minio-operator -o jsonpath='{.spec.clusterIP}')
    minio_ui_port=$(kubectl get service microk8s-console -n minio-operator -o jsonpath='{.spec.ports[0].port}')
    minio_ui_url=$minio_ui_ip:$minio_ui_port
    echo "MinIO UI URL: $minio_ui_url"
}

# Main execution
main() {
    install_microk8s
    configure_metallb
    install_additional_tools
    configure_spark
    deploy_minio_microk8s
}

main "$@"

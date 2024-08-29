#!/usr/bin/env bash

set -euo pipefail

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

deploy_minio() {
    local minio_deployment
    read -rp "Choose MinIO deployment option (1 for microk8s, 2 for docker): " minio_deployment

    case "$minio_deployment" in
    1)
        deploy_minio_microk8s
        ;;
    2)
        deploy_minio_docker
        ;;
    *)
        print_warn "Invalid choice. Defaulting to docker deployment."
        deploy_minio_docker
        ;;
    esac
}

deploy_minio_microk8s() {
    print_info "Enabling MinIO through microk8s"

    sudo cp /var/snap/microk8s/common/addons/core/addons/minio/enable tmp_minio_fix/backups/enable.backup
    sudo cp tmp_minio_fix/enable /var/snap/microk8s/common/addons/core/addons/minio/enable
    sudo chmod 755 /var/snap/microk8s/common/addons/core/addons/minio/enable

    sudo microk8s enable minio

    export AWS_ACCESS_KEY=$(kubectl get secret -n minio-operator microk8s-user-1 -o jsonpath='{.data.CONSOLE_ACCESS_KEY}' | base64 -d)
    export AWS_SECRET_KEY=$(kubectl get secret -n minio-operator microk8s-user-1 -o jsonpath='{.data.CONSOLE_SECRET_KEY}' | base64 -d)
    export AWS_S3_ENDPOINT=$(kubectl get service minio -n minio-operator -o jsonpath='{.spec.clusterIP}')

    configure_aws_cli

    local minio_ui_ip minio_ui_port minio_ui_url
    minio_ui_ip=$(kubectl get service microk8s-console -n minio-operator -o jsonpath='{.spec.clusterIP}')
    minio_ui_port=$(kubectl get service microk8s-console -n minio-operator -o jsonpath='{.spec.ports[0].port}')
    minio_ui_url=$minio_ui_ip:$minio_ui_port
    echo "MinIO UI URL: $minio_ui_url"

    create_s3_buckets
}

deploy_minio_docker() {
    print_info "Skipping microk8s MinIO deployment"

    read -rp "Set AWS Access Key (default: minio_user): " AWS_ACCESS_KEY
    AWS_ACCESS_KEY=${AWS_ACCESS_KEY:-minio_user}

    read -rp "Set AWS Secret Key (default: minio_password): " AWS_SECRET_KEY
    AWS_SECRET_KEY=${AWS_SECRET_KEY:-minio_password}

    local ipaddr
    ipaddr=$(ip -4 -j route get 2.2.2.2 | jq -r '.[] | .prefsrc')
    read -rp "Set AWS S3 Endpoint (default: http://$ipaddr:9000): " AWS_S3_ENDPOINT
    AWS_S3_ENDPOINT=${AWS_S3_ENDPOINT:-"http://$ipaddr:9000"}

    export AWS_ACCESS_KEY AWS_SECRET_KEY AWS_S3_ENDPOINT
}

configure_aws_cli() {
    local profile_name="minio-local"
    aws configure set profile.$profile_name.aws_access_key_id "$AWS_ACCESS_KEY"
    aws configure set profile.$profile_name.aws_secret_access_key "$AWS_SECRET_KEY"
    aws configure set profile.$profile_name.region "us-west-2"
    aws configure set profile.$profile_name.endpoint_url "http://$AWS_S3_ENDPOINT"

    print_info "AWS CLI configuration for MinIO has been set under the profile '$profile_name'"
    print_info "To use this profile, add --profile $profile_name to your AWS CLI commands"
}

create_s3_buckets() {
    local profile_name="minio-local"
    local buckets=("raw" "curated" "artifacts" "logs")
    for bucket in "${buckets[@]}"; do
        if aws s3 ls "s3://$bucket" --profile $profile_name --endpoint-url "http://$AWS_S3_ENDPOINT" 2>&1 | grep -q 'NoSuchBucket'; then
            aws s3 mb "s3://$bucket" --profile $profile_name --endpoint-url "http://$AWS_S3_ENDPOINT"
        else
            echo "Bucket s3://$bucket already exists. Skipping creation."
        fi
    done

    # aws s3 cp minioserver/data s3://raw --recursive --profile $profile_name --endpoint-url "http://$AWS_S3_ENDPOINT"
}

configure_spark_settings() {
    spark-client.service-account-registry add-config \
        --username spark --namespace spark \
        --conf spark.eventLog.enabled=true \
        --conf spark.eventLog.dir=s3a://logs/spark-events/ \
        --conf spark.history.fs.logDirectory=s3a://logs/spark-events/ \
        --conf spark.hadoop.fs.s3a.aws.credentials.provider=org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider \
        --conf spark.hadoop.fs.s3a.connection.ssl.enabled=false \
        --conf spark.hadoop.fs.s3a.path.style.access=true \
        --conf spark.hadoop.fs.s3a.access.key="$AWS_ACCESS_KEY" \
        --conf spark.hadoop.fs.s3a.endpoint="$AWS_S3_ENDPOINT" \
        --conf spark.hadoop.fs.s3a.secret.key="$AWS_SECRET_KEY" \
        --conf spark.kubernetes.namespace=spark

    spark-client.service-account-registry get-config \
        --username spark --namespace spark
}

# Main execution
main() {
    install_microk8s
    configure_metallb
    install_additional_tools
    configure_spark
    deploy_minio
    configure_spark_settings
}

main "$@"

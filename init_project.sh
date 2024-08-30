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

configure_spark_settings() {

    export AWS_ACCESS_KEY=$(kubectl get secret -n minio-operator microk8s-user-1 -o jsonpath='{.data.CONSOLE_ACCESS_KEY}' | base64 -d)
    export AWS_SECRET_KEY=$(kubectl get secret -n minio-operator microk8s-user-1 -o jsonpath='{.data.CONSOLE_SECRET_KEY}' | base64 -d)
    export AWS_S3_ENDPOINT=$(kubectl get service minio -n minio-operator -o jsonpath='{.spec.clusterIP}')

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

    spark-client.service-account-registry get-config \
        --username spark --namespace spark > properties.conf
}

create_s3_buckets() {
    local buckets=("raw" "curated" "artifacts" "logs")

    for bucket in "${buckets[@]}"; do

        if echo $(aws s3 ls "s3://$bucket" --profile $MINIO_PROFILE_NAME 2>&1) | grep -q 'NoSuchBucket'; then
            aws s3 mb "s3://$bucket" --profile $MINIO_PROFILE_NAME
        else
            echo "Bucket s3://$bucket already exists. Skipping creation."
        fi
    done

    # Special case for logs
    aws s3api put-object --bucket=logs --key=spark-events/ --profile=$MINIO_PROFILE_NAME
}

# Main execution
main() {
    create_s3_buckets
    configure_spark_settings

    print_info "Setup complete."
}

main "$@"

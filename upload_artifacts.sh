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

upload_initial_data() {
    print_info "Uploading initial data to artifacts bucket..."
    aws s3 cp minioserver/artifacts s3://artifacts --recursive --profile $MINIO_PROFILE_NAME
}

# Main execution
main() {
    upload_initial_data
}

main "$@"

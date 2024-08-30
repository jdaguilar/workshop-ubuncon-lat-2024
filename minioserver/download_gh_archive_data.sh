#!/bin/bash

# Global variable
export MINIO_PROFILE_NAME="minio-local"

# Function to download and upload data for a specific date and hour
download_and_upload_data() {
  local date="$1"
  local hour="$2"
  local base_url="http://data.gharchive.org/$date"
  local year=$(date -d "$date" +"%Y")
  local month=$(date -d "$date" +"%m")
  local day=$(date -d "$date" +"%d")

  # Construct the full URL and S3 path
  url="${base_url}-${hour}.json.gz"
  s3_path="s3://raw/gh_archive/year=${year}/month=${month}/day=${day}/hour=${hour}"

  # Create partitioned folder structure
  folder="data/gh_archive/year=${year}/month=${month}/day=${day}/hour=${hour}"
  mkdir -p "$folder"

  # Download the file silently
  wget -q -P "$folder" "$url"

  # Upload the file to S3 silently
  aws s3 cp "${folder}/$(basename "$url")" "${s3_path}/" --profile $MINIO_PROFILE_NAME --quiet
}

# Function to handle downloads and uploads for all hours of a given date
download_and_upload_date() {
  local date="$1"
  local total_hours=24
  local completed=0

  for hour in {0..23}; do
    download_and_upload_data "$date" "$hour"
    ((completed++))

    # Calculate percentage
    local percentage=$((completed * 100 / total_hours))

    # Create progress bar
    printf "\rProgress: [%-50s] %d%%" $(printf '#%.0s' $(seq 1 $((percentage / 2)))) $percentage
  done
  echo # New line after progress bar is complete
}

# Check if a range of dates is provided
if [ "$#" -eq 2 ]; then
  start_date="$1"
  end_date="$2"

  current_date="$start_date"
  while [ "$(date -d "$current_date" +%Y%m%d)" -le "$(date -d "$end_date" +%Y%m%d)" ]; do
    download_and_upload_date "$current_date"
    current_date=$(date -I -d "$current_date + 1 day")
  done
elif [ "$#" -eq 1 ]; then
  # Single date provided
  download_and_upload_date "$1"
else
  echo "Usage: $0 <start_date> [end_date]"
  exit 1
fi

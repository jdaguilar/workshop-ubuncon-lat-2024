#!/bin/bash

# Function to download data for a specific date and hour
download_data() {
  local date="$1"
  local hour="$2"
  local base_url="http://data.gharchive.org/$date"
  local year=$(date -d "$date" +"%Y")
  local month=$(date -d "$date" +"%m")
  local day=$(date -d "$date" +"%d")

  # Construct the full URL
  url="${base_url}-${hour}.json.gz"

  # Create partitioned folder structure
  folder="data/gh_archive/year=${year}/month=${month}/day=${day}/hour=${hour}"
  mkdir -p "$folder"

  # Download the file into the appropriate folder
  wget -P "$folder" "$url" &
}

# Function to handle downloads for all hours of a given date
download_date() {
  local date="$1"
  for hour in {0..23}; do
    download_data "$date" "$hour"
  done
  wait # Wait for all background jobs to complete before proceeding
}

# Check if a range of dates is provided
if [ "$#" -eq 2 ]; then
  start_date="$1"
  end_date="$2"

  current_date="$start_date"
  while [ "$(date -d "$current_date" +%Y%m%d)" -le "$(date -d "$end_date" +%Y%m%d)" ]; do
    download_date "$current_date"
    current_date=$(date -I -d "$current_date + 1 day")
  done
elif [ "$#" -eq 1 ]; then
  # Single date provided
  download_date "$1"
else
  echo "Usage: $0 <start_date> [end_date]"
  exit 1
fi

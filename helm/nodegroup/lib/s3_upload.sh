#!/bin/bash

# s3_upload takes the first argument as the full local file path and uploads it to s3
# at the location defined by the local variable $s3_path
s3_upload() {

  local local_file=$1
  local s3_file=$2
  local tag="s3_upload"

  # puts the snapshot somewhere safe while it's being built.
  temp_token=$(redis_cli GET "snapshot-temp-token")

  # prepare headers and signature
  the_date=$(date -R)
  # shellcheck disable=SC2154
  s3_path="/$BUCKET/$NETWORK/${temp_token}/${this_node}-${height}/$s3_file"
  content_type="application/octet-stream"
  # shellcheck disable=SC1117
  signable_bytes="PUT\n\n${content_type}\n${the_date}\n${s3_path}"
  signature=$(echo -en "$signable_bytes" | openssl sha1 -hmac "$AWS_SECRET" -binary | base64)

  # upload the local file
  log "$tag: uploading $local_file to $s3_path"
  curl -X PUT -T "$local_file" \
    -H "Host: s3.amazonaws.com" \
    -H "Date: $the_date" \
    -H "Content-Type: $content_type" \
    -H "Authorization: AWS $AWS_KEY:$signature" \
    "http://s3.amazonaws.com$s3_path"

}

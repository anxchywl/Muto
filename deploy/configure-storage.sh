#!/bin/sh
set -eu

: "${S3_ENDPOINT_URL:?S3_ENDPOINT_URL is required}"
: "${S3_BUCKET:?S3_BUCKET is required}"
: "${S3_ACCESS_KEY_ID:?S3_ACCESS_KEY_ID is required}"
: "${S3_SECRET_ACCESS_KEY:?S3_SECRET_ACCESS_KEY is required}"

repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
lifecycle_file=${IMAGE_LIFECYCLE_FILE:-$repo_dir/deploy/image-lifecycle.json}
export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$S3_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="${S3_REGION:-us-east-1}"

public_grants=$(aws --endpoint-url "$S3_ENDPOINT_URL" s3api get-bucket-acl \
  --bucket "$S3_BUCKET" \
  --query "Grants[?Grantee.URI!=\`null\`].Grantee.URI" \
  --output text)
[ -z "$public_grants" ] || {
  echo "image bucket has a public or authenticated-user ACL" >&2
  exit 1
}

aws --endpoint-url "$S3_ENDPOINT_URL" s3api put-bucket-lifecycle-configuration \
  --bucket "$S3_BUCKET" \
  --lifecycle-configuration "file://$lifecycle_file"
aws --endpoint-url "$S3_ENDPOINT_URL" s3api head-bucket --bucket "$S3_BUCKET"
echo "private image bucket and staging lifecycle verified"

#!/usr/bin/env bash
# bootstrap.sh
# Run ONCE before any terraform init/apply.
# Creates S3 state buckets + DynamoDB lock table for all 3 environments.
# Usage: bash bootstrap.sh <aws-account-id> [aws-region]

set -euo pipefail

ACCOUNT_ID="${1:?Usage: bash bootstrap.sh <aws-account-id> [aws-region]}"
REGION="${2:-us-east-1}"
PROJECT="hxp"
LOCK_TABLE="${PROJECT}-terraform-locks"

echo "==> Bootstrapping Terraform state for account ${ACCOUNT_ID} in ${REGION}"

for ENV in dev staging prod; do
  BUCKET="${PROJECT}-terraform-state-${ENV}"

  echo ""
  echo "--- Environment: ${ENV} ---"

  # Create bucket (ignore error if already exists)
  if aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
    echo "  Bucket ${BUCKET} already exists, skipping"
  else
    aws s3api create-bucket \
      --bucket "${BUCKET}" \
      --region "${REGION}" \
      $([ "${REGION}" != "us-east-1" ] && echo "--create-bucket-configuration LocationConstraint=${REGION}" || echo "")
    echo "  Created bucket: ${BUCKET}"
  fi

  # Enable versioning
  aws s3api put-bucket-versioning \
    --bucket "${BUCKET}" \
    --versioning-configuration Status=Enabled
  echo "  Enabled versioning on ${BUCKET}"

  # Enable encryption
  aws s3api put-bucket-encryption \
    --bucket "${BUCKET}" \
    --server-side-encryption-configuration '{
      "Rules": [{
        "ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"},
        "BucketKeyEnabled": true
      }]
    }'
  echo "  Enabled encryption on ${BUCKET}"

  # Block public access
  aws s3api put-public-access-block \
    --bucket "${BUCKET}" \
    --public-access-block-configuration \
      "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
  echo "  Blocked public access on ${BUCKET}"
done

# Create DynamoDB lock table (shared across all envs)
echo ""
echo "--- DynamoDB lock table ---"
if aws dynamodb describe-table --table-name "${LOCK_TABLE}" --region "${REGION}" 2>/dev/null; then
  echo "  Table ${LOCK_TABLE} already exists, skipping"
else
  aws dynamodb create-table \
    --table-name "${LOCK_TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}"
  echo "  Created DynamoDB lock table: ${LOCK_TABLE}"

  aws dynamodb wait table-exists --table-name "${LOCK_TABLE}" --region "${REGION}"
  echo "  Table is active"
fi

echo ""
echo "==> Bootstrap complete!"
echo ""
echo "Next steps:"
echo "  cd infrastructure/terraform/environments/dev"
echo "  terraform init"
echo "  terraform plan"
echo "  terraform apply"

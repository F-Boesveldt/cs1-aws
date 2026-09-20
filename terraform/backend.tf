# Create the S3 bucket and DynamoDB lock table manually once, then fill in
# the bucket name below. Backend blocks cannot reference variables, so the
# region is hardcoded here even though the rest of the config uses var.region.
#
# aws s3api create-bucket --bucket <uniquename> --region us-east-1
# aws dynamodb create-table --table-name tfstate-lock \
#   --attribute-definitions AttributeName=LockID,AttributeType=S \
#   --key-schema AttributeName=LockID,KeyType=HASH \
#   --billing-mode PAY_PER_REQUEST --region us-east-1

terraform {
  backend "s3" {
    bucket         = "" # TODO: fill in after creating the S3 bucket above
    key            = "cs1.terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "tfstate-lock"
    encrypt        = true
  }
}

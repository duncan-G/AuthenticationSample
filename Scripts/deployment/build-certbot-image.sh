#!/usr/bin/env bash
set -euo pipefail

TAG=${1:-latest}
AWS_PROFILE=${2:-terraform-setup}
AWS_REGION=${3:-us-west-1}
APP_NAME=${4:-auth-sample}

export AWS_PROFILE="$AWS_PROFILE" AWS_REGION="$AWS_REGION"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
REPO_NAME="$APP_NAME/certbot"
FULL_IMAGE_NAME="$ECR_REGISTRY/$REPO_NAME:$TAG"

# Get ECR login token
echo "🔐 Getting ECR login token..."
aws ecr get-login-password --region "$AWS_REGION" --profile "$AWS_PROFILE" | \
    docker login --username AWS --password-stdin "$ECR_REGISTRY"

# Create ECR repository if it doesn't exist
echo "📦 Creating ECR repository: $REPO_NAME"
if ! aws ecr describe-repositories --repository-names "$REPO_NAME" --profile "$AWS_PROFILE" --region "$AWS_REGION" &> /dev/null; then
    aws ecr create-repository \
        --repository-name "$REPO_NAME" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION"
    echo "✅ ECR repository $REPO_NAME created"
else
    echo "⚠️  ECR repository $REPO_NAME already exists"
fi

# Build the certbot image
echo "🔨 Building certbot Docker image..."
cd Infrastructure/certbot
docker build -t "$REPO_NAME:$TAG" .

if [ $? -eq 0 ]; then
    echo "✅ Certbot image built successfully"
else
    echo "❌ Failed to build certbot image"
    exit 1
fi

# Tag the image for ECR
docker tag "$REPO_NAME:$TAG" "$FULL_IMAGE_NAME"

# Push the image to ECR
echo "📤 Pushing certbot image to ECR..."
docker push "$FULL_IMAGE_NAME"

if [ $? -eq 0 ]; then
    echo "✅ Pushed $FULL_IMAGE_NAME"
    echo "📋 ECR Image URI: $FULL_IMAGE_NAME"
else
    echo "❌ Failed to push certbot image to ECR"
    exit 1
fi 
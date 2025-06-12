# Terraform CI/CD Pipeline Setup

Simple setup guide for deploy/teardown pipeline with OIDC authentication.

## 🏗️ Setup Steps

### 1. Configure AWS Variables

```bash
# Get your AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Set your GitHub repository
GITHUB_ORG="your-github-username"
GITHUB_REPO="your-repo-name"
GITHUB_REPO_FULL="${GITHUB_ORG}/${GITHUB_REPO}"

echo "AWS Account: ${AWS_ACCOUNT_ID}"
echo "GitHub Repo: ${GITHUB_REPO_FULL}"
```

### 2. Create OIDC Provider

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### 3. Create IAM Policy

```bash
cat > terraform-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "iam:*",
        "ssm:*",
        "time:*"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name TerraformGitHubActionsOIDCPolicy \
  --policy-document file://terraform-policy.json
```

### 4. Create Trust Policy

```bash
cat > trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": [
            "repo:${GITHUB_REPO_FULL}:ref:refs/heads/main",
            "repo:${GITHUB_REPO_FULL}:ref:refs/heads/develop",
            "repo:${GITHUB_REPO_FULL}:pull_request"
          ]
        }
      }
    }
  ]
}
EOF
```

### 5. Create IAM Role

```bash
aws iam create-role \
  --role-name github-actions-terraform \
  --assume-role-policy-document file://trust-policy.json

aws iam attach-role-policy \
  --role-name github-actions-terraform \
  --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/TerraformGitHubActionsOIDCPolicy"

echo "✅ Setup complete!"
echo "Role ARN: arn:aws:iam::${AWS_ACCOUNT_ID}:role/github-actions-terraform"
```

## 🔐 GitHub Secret

Add this secret to your GitHub repository (Settings → Secrets → Actions):

| Secret | Value |
|--------|-------|
| `AWS_ACCOUNT_ID` | Your AWS Account ID (from step 1) |

## 🚀 Usage

### Manual Actions:
- **Actions** → "Terraform Infrastructure" → "Run workflow"
- Choose action: `plan`, `deploy`, or `destroy`
- Choose environment: `staging` or `production`

### Automatic Actions:
- **Pull Request** → Shows terraform plan with changes
- **Push to main** → Only runs terraform plan (no auto-deploy for safety)

## 🏃‍♂️ Local Development

```bash
cd deployments
terraform init
terraform workspace select staging  # or production
terraform plan
terraform apply
```

## 📋 Infrastructure Resources

This terraform configuration creates:
- **VPC** with public and private subnets
- **EC2 instances** (public worker, private manager)  
- **Security groups** for Docker Swarm communication
- **IAM roles** with SSM and CloudWatch permissions
- **Docker Swarm** cluster setup via user data scripts

That's it! 🎉 
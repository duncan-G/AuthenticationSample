# Terraform CI/CD Pipeline Setup

Simple setup guide for deploy/teardown pipeline with OIDC authentication.

## 🔐 Prerequisites

### AWS IAM Identity Center Setup Required

Before running this setup, configure IAM Identity Center with the appropriate permissions using the AWS Console.

#### Step 1: Enable IAM Identity Center

1. **Go to AWS Console** → **IAM Identity Center** → **Enable**
2. **Choose organization instance** (recommended) if you have AWS Organizations
3. **Choose identity source:**
   - **IAM Identity Center** - Create users directly in Identity Center
   - **Active Directory** - Connect existing AD
   - **External identity provider** - Connect SAML/OIDC provider

#### Step 2: Create Permission Set

1. **Go to IAM Identity Center** → **Permission sets** → **Create permission set**
2. **Choose Custom permission set** → **Next**
3. **Permission set name:** `TerraformPipelineSetup`
4. **Description:** "Minimal permissions for terraform pipeline setup"
5. **Session duration:** 1 hour (or as needed)
6. **Permissions policies** → **Create a custom permissions policy**
7. **Click JSON tab** and paste the contents from `setup-pipeline-permissions.json`
8. **Click Next** → **Create permission set**

#### Step 3: Create or Add User

**Option A: Create new user in Identity Center**
1. **Go to Users** → **Add user**
2. **Username:** `terraform-pipeline-user`
3. **Fill in required details** → **Create user**

**Option B: Use existing user** (if using external identity provider)

#### Step 4: Assign User to Account with Permission Set

1. **Go to AWS accounts** → **Select your account** → **Assign users or groups**
2. **Select Users** → Choose your user → **Next**
3. **Select permission sets** → Choose `TerraformPipelineSetup` → **Next**
4. **Submit**

#### Step 5: Configure AWS CLI with SSO

1. **Get your SSO start URL:**
   - Go to **IAM Identity Center** → **Dashboard**
   - Copy the **AWS access portal URL**

2. **Configure AWS CLI:**
```bash
aws configure sso --profile terraform-setup
# SSO session name: terraform-setup
# SSO start URL: [Your AWS access portal URL from step 1]
# SSO region: us-west-1 (or your IAM Identity Center region)
# SSO registration scopes: sso:account:access
# Account ID: [Your AWS Account ID]
# Role name: TerraformPipelineSetup
# CLI default client Region: us-west-1
# CLI default output format: json
```

3. **Login to SSO:**
```bash
aws sso login --profile terraform-setup
```

**Required permissions (from setup-pipeline-permissions.json):**
- `sts:GetCallerIdentity` - Get AWS account ID
- `iam:*OpenIDConnectProvider*` - Create/manage GitHub OIDC provider
- `iam:CreatePolicy`, `iam:GetPolicy` - Create terraform execution policy
- `iam:CreateRole`, `iam:GetRole`, `iam:AttachRolePolicy` - Create GitHub Actions role

**Security Benefits:**
- ✅ **Principle of least privilege** - Only permissions needed for pipeline setup
- ✅ **Minimal attack surface** - Limited scope if credentials compromised  
- ✅ **Auditable** - Clear understanding of what the setup can access

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

**💡 Automated Setup:** You can run all the above steps automatically using:
```bash
AWS_PROFILE=terraform-setup ./setup-pipeline.sh
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
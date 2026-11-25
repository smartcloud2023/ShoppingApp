# ECR Build & Push Pipeline with HashiCorp Vault

`.github/workflows/ecr-build-push.yml` builds the Docker image for each of the 24
services and pushes it to AWS ECR. Nothing is stored in GitHub secrets.

## How a run gets its secrets

```text
GitHub Actions job
  │ 1. asks GitHub for an OIDC token (permissions: id-token: write)
  ▼
Vault  https://group3assessment.online   (auth/jwt, role ecommerce-ci)
  │ 2. checks the token: issuer, audience, repo and branch
  │ 3. returns a 10-minute Vault token with read-only policy ecommerce-ci
  │ 4. job reads secret/ecommerce/ci → AWS_ROLE_ARN, AWS_REGION, ECR_REPO_PREFIX
  ▼
AWS STS
  │ 5. job assumes AWS_ROLE_ARN with the same GitHub OIDC token
  ▼
Amazon ECR   <prefix>/<service>:latest and :<8-char sha>
```

There is no long-lived credential anywhere: no Vault token, no AWS key, no GitHub
secret. Vault only answers for `digitalwitchdemo/ecommerce-final-project` on `main`.

## One-time setup

### 1. Vault (from Master-Node, in the vault-roles project)

```bash
cd ~/hashicorp-vault-role
ansible-playbook site.yml --tags github-oidc
```

This turns on KV v2 at `secret/`, JWT auth at `auth/jwt` trusting GitHub,
the `ecommerce-ci` policy and role, and writes `secret/ecommerce/ci`.
The Vault nodes need outbound HTTPS to `token.actions.githubusercontent.com`.

Check it:

```bash
export VAULT_ADDR=https://group3assessment.online
vault login
vault read auth/jwt/role/ecommerce-ci
vault kv get secret/ecommerce/ci
```

### 2. AWS: GitHub OIDC provider (skip if it already exists)

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com
```

### 3. AWS: the role the pipeline assumes

Name it `github-actions-ecr-push` (that is the ARN stored in Vault).
Trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::060647991200:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:digitalwitchdemo/ecommerce-final-project:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

Permissions policy (the prefix matches `ECR_REPO_PREFIX` in Vault, `ecommerce`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["ecr:GetAuthorizationToken"],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:CreateRepository",
        "ecr:DescribeRepositories",
        "ecr:BatchCheckLayerAvailability",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer"
      ],
      "Resource": "arn:aws:ecr:us-west-1:060647991200:repository/ecommerce/*"
    }
  ]
}
```

### 4. GitHub

Nothing to add. Optional repository **variables** (not secrets) if you ever move Vault:

| Variable | Default |
|---|---|
| `VAULT_ADDR` | `https://group3assessment.online` |
| `VAULT_ROLE` | `ecommerce-ci` |

If an old `AWS_ROLE_ARN` secret exists under Settings → Secrets and variables →
Actions, delete it.

### 5. Test

Actions → **Build and Push Images to ECR** → **Run workflow** on `main`.
Images appear in ECR as `ecommerce/<service>`, tagged `latest` and the short SHA.

## Adding another secret

```bash
vault kv patch secret/ecommerce/ci MY_TOKEN=-     # value read from stdin
```

Then add `secret/data/ecommerce/ci MY_TOKEN | MY_TOKEN ;` to the `secrets:` block
of the "Read pipeline secrets from Vault" step.

## Troubleshooting

| Error in the Vault step | Cause |
|---|---|
| `error validating token: invalid audience (aud) claim` | `jwtGithubAudience` and the role's `bound_audiences` differ |
| `claim "ref" does not match any associated bound claim values` | Run was not on `main` |
| `error fetching keys` / timeout | Vault nodes can't reach `token.actions.githubusercontent.com` |
| `permission denied` reading the secret | Path isn't `secret/data/ecommerce/ci` or policy not applied |

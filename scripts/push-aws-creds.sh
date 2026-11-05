#!/usr/bin/env bash
# Copies the CURRENT temporary AWS credentials of your local AWS profile to the Jenkins host, where the
# pipeline's AWS CLI picks them up (see AWS_SHARED_CREDENTIALS_FILE in jenkins/docker-compose.yml).
# Needed when the sandbox's organization policy only allows the portal's own session, not the instance role.
# Credentials are temporary: re-run this when they expire (before a build, check the expiry first).
#   1) In CloudShell: aws configure export-credentials --format env   (copy the 3 export lines)
#   2) Paste them into your terminal, then: scripts/push-aws-creds.sh <jenkins-ip> [ssh-key]
#   (or, with no pasted exports, it reads the credentials of AWS_PROFILE, default 'sandbox')
set -euo pipefail
HOST="${1:?usage: push-aws-creds.sh <jenkins-ip> [ssh-key]}"
KEY="${2:-$HOME/.ssh/jenkins-keypair}"
PROFILE="${AWS_PROFILE:-sandbox}"

# Use credentials already exported in this shell (paste CloudShell's `export ...` lines), else the profile's.
if [ -z "${AWS_ACCESS_KEY_ID:-}" ]; then
  eval "$(aws configure export-credentials --profile "$PROFILE" --format env)"
fi
: "${AWS_ACCESS_KEY_ID:?no credentials found (paste the export lines or set AWS_PROFILE)}"

{
  echo "[default]"
  echo "aws_access_key_id=$AWS_ACCESS_KEY_ID"
  echo "aws_secret_access_key=$AWS_SECRET_ACCESS_KEY"
  [ -z "${AWS_SESSION_TOKEN:-}" ] || echo "aws_session_token=$AWS_SESSION_TOKEN"
} | ssh -i "$KEY" "ec2-user@$HOST" \
  'sudo mkdir -p /opt/secure-cicd/secrets && sudo tee /opt/secure-cicd/secrets/aws_credentials >/dev/null && sudo chmod 600 /opt/secure-cicd/secrets/aws_credentials'

echo "Pushed credentials for profile '$PROFILE' to $HOST. Verifying from inside Jenkins's environment:"
ssh -i "$KEY" "ec2-user@$HOST" \
  'sudo env AWS_SHARED_CREDENTIALS_FILE=/opt/secure-cicd/secrets/aws_credentials aws sts get-caller-identity --query Arn --output text'

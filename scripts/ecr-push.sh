#!/usr/bin/env bash
# Tags + pushes the scanned image to ECR (immutable, versioned tag) and records its digest.
# Usage: ecr-push.sh <local-image-ref>      Required env: AWS_REGION ECR_REGISTRY ECR_REPOSITORY IMAGE_TAG
source "$(dirname "$0")/_common.sh"
LOCAL="${1:?usage: ecr-push.sh <local-image>}"
need AWS_REGION ECR_REGISTRY ECR_REPOSITORY IMAGE_TAG
REMOTE="$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG"

aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY" >/dev/null
docker tag "$LOCAL" "$REMOTE"
docker push "$REMOTE"

DIGEST="$(aws ecr describe-images --region "$AWS_REGION" --repository-name "$ECR_REPOSITORY" \
          --image-ids imageTag="$IMAGE_TAG" --query 'imageDetails[0].imageDigest' --output text)"
[ -n "$DIGEST" ] && [ "$DIGEST" != "None" ] || die "could not read digest for $REMOTE"
echo "$REMOTE@$DIGEST" > "$REPORT_DIR/image-uri.txt"
log "Pushed $REMOTE ($DIGEST)"
docker logout "$ECR_REGISTRY" >/dev/null 2>&1 || true

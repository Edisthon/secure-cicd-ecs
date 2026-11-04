#!/usr/bin/env bash
# Post-validation cleanup: keep the newest KEEP ACTIVE task-definition revisions (and always the one
# the service is using), deregister the rest, then try to delete the INACTIVE ones.
# ECR images are cleaned by the repository lifecycle policy (terraform/modules/ecr), which keeps
# MORE images (10) than we keep revisions (default 5), so a kept revision never points at a purged image.
# Set DRY_RUN=true to only print what would happen.
source "$(dirname "$0")/_common.sh"
need AWS_REGION ECS_CLUSTER ECS_SERVICE ECS_TASK_FAMILY
export AWS_DEFAULT_REGION="$AWS_REGION"
KEEP="${KEEP_REVISIONS:-5}"
DRY_RUN="${DRY_RUN:-false}"

IN_USE="$(aws ecs describe-services --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" \
           --query 'services[0].taskDefinition' --output text)"
log "In use by the service: $IN_USE"

mapfile -t ACTIVE < <(aws ecs list-task-definitions --family-prefix "$ECS_TASK_FAMILY" --status ACTIVE \
                        --sort DESC --query 'taskDefinitionArns[]' --output text | tr '\t' '\n')
log "ACTIVE revisions: ${#ACTIVE[@]} (keeping newest $KEEP)"

: > "$REPORT_DIR/ecs-cleanup.txt"
idx=0
for arn in "${ACTIVE[@]}"; do
  idx=$((idx+1))
  [ -n "$arn" ] || continue
  if [ "$idx" -le "$KEEP" ] || [ "$arn" = "$IN_USE" ]; then continue; fi
  echo "deregister $arn" | tee -a "$REPORT_DIR/ecs-cleanup.txt"
  [ "$DRY_RUN" = "true" ] || aws ecs deregister-task-definition --task-definition "$arn" >/dev/null
done

# Deleting INACTIVE revisions is best effort (the API is newer than some CLI versions).
if [ "$DRY_RUN" != "true" ]; then
  mapfile -t INACTIVE < <(aws ecs list-task-definitions --family-prefix "$ECS_TASK_FAMILY" --status INACTIVE \
                            --query 'taskDefinitionArns[]' --output text | tr '\t' '\n')
  for ((i=0; i<${#INACTIVE[@]}; i+=10)); do
    batch=("${INACTIVE[@]:i:10}")
    [ -n "${batch[0]}" ] || continue
    aws ecs delete-task-definitions --task-definitions "${batch[@]}" >/dev/null 2>&1 \
      && echo "deleted ${#batch[@]} INACTIVE revisions" | tee -a "$REPORT_DIR/ecs-cleanup.txt" \
      || log "delete-task-definitions not available/allowed - revisions stay INACTIVE (harmless)"
  done
fi

if [ -n "${ECR_REPOSITORY:-}" ]; then
  aws ecr describe-images --repository-name "$ECR_REPOSITORY" \
    --query 'sort_by(imageDetails,&imagePushedAt)[].{tag:imageTags[0],pushed:imagePushedAt,scan:imageScanStatus.status}' \
    --output table | tee "$REPORT_DIR/ecr-images-after-cleanup.txt"
fi

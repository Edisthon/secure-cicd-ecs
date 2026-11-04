#!/usr/bin/env bash
# Renders ecs/taskdef.template.json -> ecs/rendered/taskdef-<IMAGE_TAG>.json and validates it.
# Required env: ECS_TASK_FAMILY ECS_CONTAINER_NAME IMAGE_URI IMAGE_TAG AWS_REGION LOG_GROUP
#               EXECUTION_ROLE_ARN TASK_ROLE_ARN   (optional: TASK_CPU=256 TASK_MEMORY=512)
source "$(dirname "$0")/_common.sh"
need ECS_TASK_FAMILY ECS_CONTAINER_NAME IMAGE_URI IMAGE_TAG AWS_REGION LOG_GROUP EXECUTION_ROLE_ARN TASK_ROLE_ARN
export TASK_CPU="${TASK_CPU:-256}" TASK_MEMORY="${TASK_MEMORY:-512}"

TEMPLATE="${TASKDEF_TEMPLATE:-ecs/taskdef.template.json}"
OUT_DIR="${TASKDEF_OUT_DIR:-ecs/rendered}"
OUT="$OUT_DIR/taskdef-${IMAGE_TAG}.json"
mkdir -p "$OUT_DIR"

# Only substitute the variables we list, so nothing else in the template is touched.
VARS='${ECS_TASK_FAMILY} ${ECS_CONTAINER_NAME} ${IMAGE_URI} ${IMAGE_TAG} ${AWS_REGION} ${LOG_GROUP} ${EXECUTION_ROLE_ARN} ${TASK_ROLE_ARN} ${TASK_CPU} ${TASK_MEMORY}'
envsubst "$VARS" < "$TEMPLATE" | jq '.' > "$OUT"

# Validation: no unresolved placeholders, and only keys that register-task-definition accepts.
if grep -q '\${' "$OUT"; then die "unresolved placeholder left in $OUT"; fi
ALLOWED='["family","taskRoleArn","executionRoleArn","networkMode","containerDefinitions","volumes","placementConstraints","requiresCompatibilities","cpu","memory","tags","pidMode","ipcMode","proxyConfiguration","inferenceAccelerators","ephemeralStorage","runtimePlatform"]'
BAD="$(jq -r --argjson ok "$ALLOWED" 'keys - $ok | join(",")' "$OUT")"
[ -z "$BAD" ] || die "keys not accepted by register-task-definition: $BAD"
jq -e '.containerDefinitions[0].image | test("@sha256:|:[A-Za-z0-9_.-]+$")' "$OUT" >/dev/null || die "image reference looks invalid"

log "Rendered $OUT"
echo "$OUT" > "$REPORT_DIR/rendered-taskdef-path.txt"
jq '{family, image: .containerDefinitions[0].image, cpu, memory}' "$OUT"

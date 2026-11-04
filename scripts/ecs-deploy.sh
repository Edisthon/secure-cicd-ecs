#!/usr/bin/env bash
# ECS deployment helper.
#   ecs-deploy.sh register <taskdef.json>   register a new task definition revision (prints ARN)
#   ecs-deploy.sh update   <taskdef-arn>    point the service at that revision (rolling update)
#   ecs-deploy.sh wait                      wait until the rollout is COMPLETED (or fails)
#   ecs-deploy.sh verify                    hit the ALB and assert the new build is serving traffic
#   ecs-deploy.sh rollback <taskdef.json>   register + update + wait from a rendered file in Git
# Required env: AWS_REGION ECS_CLUSTER ECS_SERVICE   (verify also needs ALB_NAME, IMAGE_TAG)
source "$(dirname "$0")/_common.sh"
need AWS_REGION ECS_CLUSTER ECS_SERVICE
export AWS_DEFAULT_REGION="$AWS_REGION"

describe_service() {
  aws ecs describe-services --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" --output json
}

cmd_register() {
  local file="${1:?taskdef json}"
  local arn
  arn="$(aws ecs register-task-definition --cli-input-json "file://$file" \
          --query 'taskDefinition.taskDefinitionArn' --output text)"
  echo "$arn" > "$REPORT_DIR/taskdef-arn.txt"
  aws ecs describe-task-definition --task-definition "$arn" --output json \
    > "$REPORT_DIR/ecs-taskdef-registered.json"
  log "Registered $arn"
  echo "$arn"
}

cmd_update() {
  local arn="${1:?task definition ARN}"
  describe_service | jq -r '.services[0].taskDefinition' > "$REPORT_DIR/taskdef-previous-arn.txt"
  log "Previous revision: $(cat "$REPORT_DIR/taskdef-previous-arn.txt")"
  local extra=()
  [ -z "${DESIRED_COUNT:-}" ] || extra=(--desired-count "$DESIRED_COUNT")
  aws ecs update-service --cluster "$ECS_CLUSTER" --service "$ECS_SERVICE" \
    --task-definition "$arn" ${extra[@]+"${extra[@]}"} \
    --query 'service.deployments[].{status:status,td:taskDefinition,desired:desiredCount,state:rolloutState}' \
    --output table
}

cmd_wait() {
  log "Waiting for the rolling deployment (circuit breaker will roll back on failure)"
  local tries=0
  while [ "$tries" -lt 60 ]; do
    local state
    state="$(describe_service | jq -r '.services[0].deployments[] | select(.status=="PRIMARY") | .rolloutState')"
    log "rolloutState=$state"
    case "$state" in
      COMPLETED) break ;;
      FAILED)    describe_service > "$REPORT_DIR/ecs-service-after.json"; die "deployment FAILED (ECS rolled back to the previous revision)" ;;
    esac
    tries=$((tries+1)); sleep 15
  done
  [ "${state:-}" = "COMPLETED" ] || die "timed out waiting for rollout"
  aws ecs wait services-stable --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE"
  describe_service > "$REPORT_DIR/ecs-service-after.json"
  aws ecs list-tasks --cluster "$ECS_CLUSTER" --service-name "$ECS_SERVICE" --output json > "$REPORT_DIR/ecs-tasks.json"
  log "Service stable:"
  jq -r '.services[0] | "  taskDefinition: \(.taskDefinition)\n  running/desired: \(.runningCount)/\(.desiredCount)"' "$REPORT_DIR/ecs-service-after.json"
}

cmd_verify() {
  need ALB_NAME IMAGE_TAG
  local dns
  dns="$(aws elbv2 describe-load-balancers --names "$ALB_NAME" --query 'LoadBalancers[0].DNSName' --output text)"
  log "Checking http://$dns"
  local i=0
  while [ "$i" -lt 12 ]; do
    if body="$(curl -fsS --max-time 5 "http://$dns/version")" && [ "$(echo "$body" | jq -r .version)" = "$IMAGE_TAG" ]; then
      curl -fsS --max-time 5 "http://$dns/health" | tee "$REPORT_DIR/post-deploy-health.json"; echo
      echo "$body" > "$REPORT_DIR/post-deploy-version.json"
      log "Live: $body"
      return 0
    fi
    log "not serving $IMAGE_TAG yet ($(echo "${body:-no response}" | head -c 80)), retrying"
    i=$((i+1)); sleep 10
  done
  die "ALB is not serving build $IMAGE_TAG"
}

case "${1:-}" in
  register) shift; cmd_register "$@" ;;
  update)   shift; cmd_update "$@" ;;
  wait)     cmd_wait ;;
  verify)   cmd_verify ;;
  rollback) shift; arn="$(cmd_register "$1" | tail -1)"; cmd_update "$arn"; cmd_wait ;;
  *) die "usage: $0 register|update|wait|verify|rollback ..." ;;
esac

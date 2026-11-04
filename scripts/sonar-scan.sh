#!/usr/bin/env bash
# SAST (SonarQube). Runs the scanner container and WAITS for the Quality Gate;
# the scanner exits non-zero when the gate is red (sonar.qualitygate.wait=true).
source "$(dirname "$0")/_common.sh"
need SONAR_HOST_URL SONAR_TOKEN

IMAGE="${SONAR_SCANNER_IMAGE:-sonarsource/sonar-scanner-cli:11}"
VERSION="${IMAGE_TAG:-local}"

log "Running SonarScanner against $SONAR_HOST_URL (project version $VERSION)"
# --network host: SonarQube is published on the Jenkins host's :9000, so localhost works from the scanner.
docker run --rm --network host \
  -e SONAR_HOST_URL -e SONAR_TOKEN \
  -v "$PWD:/usr/src" "$IMAGE" \
  -Dsonar.projectVersion="$VERSION" \
  -Dsonar.qualitygate.wait=true \
  -Dsonar.qualitygate.timeout=300

# Keep a record of the gate decision for the evidence pack.
AUTH="$SONAR_TOKEN:"
curl -fsS -u "$AUTH" "$SONAR_HOST_URL/api/qualitygates/project_status?projectKey=${SONAR_PROJECT_KEY:-secure-cicd-ecs}" \
  -o "$REPORT_DIR/sonar-quality-gate.json" || log "could not fetch gate JSON (non-fatal)"
log "Quality Gate passed"

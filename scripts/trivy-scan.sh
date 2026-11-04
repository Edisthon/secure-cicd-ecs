#!/usr/bin/env bash
# Container image scan (Trivy). Writes JSON + text reports, then GATES on HIGH/CRITICAL.
# Usage: trivy-scan.sh <local-image-ref>
source "$(dirname "$0")/_common.sh"
IMAGE_REF="${1:?usage: trivy-scan.sh <image>}"

TRIVY_IMAGE="${TRIVY_IMAGE:-aquasec/trivy:latest}"
CACHE="${TRIVY_CACHE_DIR:-/var/jenkins_home/.cache/trivy}"
SEVERITY="${TRIVY_SEVERITY:-HIGH,CRITICAL}"
mkdir -p "$CACHE"

run_trivy() {
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$CACHE:/root/.cache/trivy" -v "$PWD:/work" \
    "$TRIVY_IMAGE" image --timeout 15m --scanners vuln,secret \
    --severity "$SEVERITY" --ignore-unfixed \
    --ignorefile /work/security/.trivyignore "$@" "$IMAGE_REF"
}

log "Trivy: writing JSON report for $IMAGE_REF"
run_trivy --format json --output "/work/$REPORT_DIR/trivy-image.json" --exit-code 0

log "Trivy: gating on $SEVERITY (fixed vulnerabilities only)"
set -o pipefail
if run_trivy --format table --exit-code 1 2>&1 | tee "$REPORT_DIR/trivy-image.txt"; then
  log "Image scan passed"
else
  log "IMAGE SCAN GATE FAILED: $SEVERITY findings present - see $REPORT_DIR/trivy-image.txt"
  exit 1
fi

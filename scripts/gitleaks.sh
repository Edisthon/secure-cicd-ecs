#!/usr/bin/env bash
# Secret scan (Gitleaks). Scans git history + working tree. Exit 1 on ANY finding.
# Pattern borrowed from the AOMS shared library step omsSecretScan (containerised, redacted output).
source "$(dirname "$0")/_common.sh"

IMAGE="${GITLEAKS_IMAGE:-zricethezav/gitleaks:v8.18.4}"
CONFIG="security/.gitleaks.toml"

log "Running Gitleaks ($IMAGE)"
set +e
docker run --rm -v "$PWD:/repo" "$IMAGE" detect \
  --source=/repo --config="/repo/$CONFIG" \
  --redact --verbose --exit-code 1 \
  --report-format json --report-path "/repo/$REPORT_DIR/gitleaks-report.json"
rc=$?
set -e

if [ "$rc" -ne 0 ]; then
  log "SECRETS DETECTED - see $REPORT_DIR/gitleaks-report.json (values are redacted)"
  exit 1
fi
log "No secrets detected"

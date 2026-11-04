#!/usr/bin/env bash
# SCA (OWASP Dependency-Check). Fails on any dependency with CVSS >= 7.0 (High or Critical).
# requirements.txt is installed into a scratch dir first so Dependency-Check can read each package's
# dist-info metadata (its Python analyzers work on installed distributions).
source "$(dirname "$0")/_common.sh"

DC_IMAGE="${DC_IMAGE:-owasp/dependency-check:latest}"
PY_IMAGE="${PY_IMAGE:-python:3.13-slim}"
FAIL_CVSS="${FAIL_CVSS:-7}"
DC_DATA="${DC_DATA_DIR:-/var/jenkins_home/.dependency-check-data}"
SCRATCH=".sca-deps"

rm -rf "$SCRATCH" "$REPORT_DIR/dependency-check"
mkdir -p "$SCRATCH" "$REPORT_DIR/dependency-check" "$DC_DATA"
# The scanner image runs as a non-root user; the data dir must be writable by it.
chmod -R a+rwX "$DC_DATA" "$REPORT_DIR/dependency-check"

log "Resolving pinned dependencies from app/requirements.txt"
docker run --rm -v "$PWD:/src" "$PY_IMAGE" \
  pip install --no-cache-dir --no-deps --target /src/$SCRATCH -r /src/app/requirements.txt >/dev/null

NVD_ARGS=()
if [ -n "${NVD_API_KEY:-}" ] && [ "${NVD_API_KEY}" != "none" ]; then
  NVD_ARGS=(--nvdApiKey "$NVD_API_KEY")
else
  log "WARNING: no NVD_API_KEY - the first database download can take 20+ minutes"
fi

log "Running Dependency-Check (fail on CVSS >= $FAIL_CVSS)"
set +e
docker run --rm \
  -v "$PWD:/src" -v "$DC_DATA:/usr/share/dependency-check/data" \
  "$DC_IMAGE" \
  --scan /src/$SCRATCH --project "secure-cicd-ecs" \
  --format HTML --format JSON --format SARIF \
  --out /src/$REPORT_DIR/dependency-check \
  --failOnCVSS "$FAIL_CVSS" --disableAssembly \
  --suppression /src/security/dependency-check-suppressions.xml \
  ${NVD_ARGS[@]+"${NVD_ARGS[@]}"}
rc=$?
set -e
rm -rf "$SCRATCH"

if [ "$rc" -eq 1 ]; then
  log "SCA GATE FAILED: dependency with CVSS >= $FAIL_CVSS - see $REPORT_DIR/dependency-check/"
  exit 1
elif [ "$rc" -ne 0 ]; then
  log "SCA TOOL ERROR (exit $rc): the scan itself failed (not a CVSS finding) - see the log above"
  exit 1
fi
log "SCA gate passed"

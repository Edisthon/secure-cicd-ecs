#!/usr/bin/env bash
# Builds reports/security-summary.md from whatever scan reports exist. Never fails the build.
source "$(dirname "$0")/_common.sh"
OUT="$REPORT_DIR/security-summary.md"
{
  echo "# Security scan summary"
  echo
  echo "Build: ${BUILD_URL:-local}  |  Image tag: ${IMAGE_TAG:-n/a}  |  Commit: ${GIT_COMMIT:-n/a}"
  echo
  echo "| Control | Tool | Result |"
  echo "| --- | --- | --- |"

  if [ -f "$REPORT_DIR/gitleaks-report.json" ]; then
    n=$(jq 'length' "$REPORT_DIR/gitleaks-report.json" 2>/dev/null || echo "?")
    echo "| Secret scan | Gitleaks | $n finding(s) |"
  else echo "| Secret scan | Gitleaks | no findings file (clean or not run) |"; fi

  if [ -f "$REPORT_DIR/sonar-quality-gate.json" ]; then
    s=$(jq -r '.projectStatus.status' "$REPORT_DIR/sonar-quality-gate.json" 2>/dev/null || echo "?")
    echo "| SAST | SonarQube | Quality Gate: $s |"
  else echo "| SAST | SonarQube | not available |"; fi

  if [ -f "$REPORT_DIR/dependency-check/dependency-check-report.json" ]; then
    c=$(jq '[.dependencies[]?.vulnerabilities[]? | select(.severity=="CRITICAL")] | length' "$REPORT_DIR/dependency-check/dependency-check-report.json")
    h=$(jq '[.dependencies[]?.vulnerabilities[]? | select(.severity=="HIGH")] | length' "$REPORT_DIR/dependency-check/dependency-check-report.json")
    echo "| SCA | OWASP Dependency-Check | CRITICAL=$c HIGH=$h |"
  else echo "| SCA | OWASP Dependency-Check | not available |"; fi

  if [ -f "$REPORT_DIR/trivy-image.json" ]; then
    c=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' "$REPORT_DIR/trivy-image.json")
    h=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH")] | length' "$REPORT_DIR/trivy-image.json")
    echo "| Image scan | Trivy | CRITICAL=$c HIGH=$h |"
  else echo "| Image scan | Trivy | not available |"; fi

  if [ -f "$SBOM_DIR/sbom.cdx.json" ]; then
    echo "| SBOM | Syft (CycloneDX) | $(jq '.components | length' "$SBOM_DIR/sbom.cdx.json") components |"
  else echo "| SBOM | Syft | not generated |"; fi
} > "$OUT"
cat "$OUT"

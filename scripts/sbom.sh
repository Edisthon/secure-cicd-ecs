#!/usr/bin/env bash
# SBOM generation (Syft): CycloneDX (primary deliverable) + SPDX.
# Usage: sbom.sh <local-image-ref>
source "$(dirname "$0")/_common.sh"
IMAGE_REF="${1:?usage: sbom.sh <image>}"
SYFT_IMAGE="${SYFT_IMAGE:-anchore/syft:latest}"

log "Syft: generating SBOMs for $IMAGE_REF"
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "$PWD:/work" "$SYFT_IMAGE" \
  "docker:$IMAGE_REF" \
  -o "cyclonedx-json=/work/$SBOM_DIR/sbom.cdx.json" \
  -o "spdx-json=/work/$SBOM_DIR/sbom.spdx.json"

COMPONENTS="$(jq '.components | length' "$SBOM_DIR/sbom.cdx.json")"
[ "$COMPONENTS" -gt 0 ] || die "SBOM contains no components"
log "SBOM written: $SBOM_DIR/sbom.cdx.json ($COMPONENTS components)"

#!/usr/bin/env bash
# Shared helpers, sourced by the other scripts.
set -euo pipefail

REPORT_DIR="${REPORT_DIR:-reports}"
SBOM_DIR="${SBOM_DIR:-sbom}"
mkdir -p "$REPORT_DIR" "$SBOM_DIR"

log()  { printf '[%s] %s\n' "$(basename "${0:-script}")" "$*"; }
die()  { printf '[%s] ERROR: %s\n' "$(basename "${0:-script}")" "$*" >&2; exit 1; }
need() { for v in "$@"; do [ -n "${!v:-}" ] || die "required variable $v is not set"; done; }

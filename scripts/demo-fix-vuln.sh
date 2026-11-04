#!/usr/bin/env bash
# Lab step "verify success after fix": removes the vulnerable pin so the next build goes green.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
sed -i '/^PyYAML==5.3$/d' app/requirements.txt
git add app/requirements.txt
git commit -m "fix: remove vulnerable PyYAML==5.3 (pipeline should pass again)"
echo "Now: git push   -> expect all gates GREEN and an ECS deployment"

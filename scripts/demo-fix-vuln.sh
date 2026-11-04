#!/usr/bin/env bash
# Lab step "verify success after fix": removes the vulnerable pin so the next build goes green.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
sed -i '/^PyJWT==1.7.1$/d' app/requirements.txt
git add app/requirements.txt
git commit -m "fix: remove vulnerable PyJWT==1.7.1 (pipeline should pass again)"
echo "Now: git push   -> expect all gates GREEN and an ECS deployment"

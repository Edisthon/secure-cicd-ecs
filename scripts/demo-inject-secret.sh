#!/usr/bin/env bash
# Optional: proves the Gitleaks gate. Commits a FAKE AWS key on a throw-away branch (assembled at runtime
# so the key never appears in this file). Delete the branch afterwards.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
git checkout -B demo/leaked-secret
P1="AKIA"; P2="J5Q2W7N3B4K7P6XT"
printf 'AWS_ACCESS_KEY_ID=%s%s\n' "$P1" "$P2" > app/leaked.env
git add -f app/leaked.env
git commit -m "demo: commit a fake AWS key (Gitleaks must block)"
echo "Now: git push -u origin demo/leaked-secret   -> expect the Secret Scan gate to FAIL"
echo "Clean up: git checkout main && git branch -D demo/leaked-secret && git push origin --delete demo/leaked-secret"

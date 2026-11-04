#!/usr/bin/env bash
# Lab step "inject a vulnerable dependency": adds PyJWT 1.7.1 (HIGH CVE-2022-29217, fixed in 2.4.0; pure-Python wheel so it installs cleanly)
# on a throw-away branch. Push it and the pipeline MUST block. Run demo-fix-vuln.sh for the green run.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
git checkout -B demo/vulnerable-dependency
echo "PyJWT==1.7.1" >> app/requirements.txt
git add app/requirements.txt
git commit -m "demo: inject vulnerable dependency PyJWT==1.7.1 (pipeline must block)"
echo "Now: git push -u origin demo/vulnerable-dependency   -> expect the SCA / image-scan gate to FAIL"

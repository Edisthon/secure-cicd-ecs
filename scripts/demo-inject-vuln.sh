#!/usr/bin/env bash
# Lab step "inject a vulnerable dependency": adds PyYAML 5.3 (critical CVE-2020-14343, fixed in 5.4)
# on a throw-away branch. Push it and the pipeline MUST block. Run demo-fix-vuln.sh for the green run.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
git checkout -B demo/vulnerable-dependency
echo "PyYAML==5.3" >> app/requirements.txt
git add app/requirements.txt
git commit -m "demo: inject vulnerable dependency PyYAML==5.3 (pipeline must block)"
echo "Now: git push -u origin demo/vulnerable-dependency   -> expect the SCA / image-scan gate to FAIL"

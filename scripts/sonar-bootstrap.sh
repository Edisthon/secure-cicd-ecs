#!/usr/bin/env bash
# FALLBACK ONLY - the ansible/roles/sonarqube role does this automatically (ansible/site.yml).
# One-off: creates the "Secure-Gate" quality gate in SonarQube and assigns it to this project.
# The gate is RED when any vulnerability / blocker / critical issue exists or a security rating worse than A.
# Usage: SONAR_HOST_URL=http://localhost:9000 SONAR_ADMIN_TOKEN=<admin token> scripts/sonar-bootstrap.sh
set -euo pipefail
: "${SONAR_HOST_URL:?}" "${SONAR_ADMIN_TOKEN:?}"
KEY="${SONAR_PROJECT_KEY:-secure-cicd-ecs}"; GATE="Secure-Gate"
api() { curl -fsS -u "$SONAR_ADMIN_TOKEN:" -X POST "$SONAR_HOST_URL/api/$1" "${@:2}"; }

api qualitygates/create --data-urlencode "name=$GATE" >/dev/null || echo "gate exists, continuing"
cond() { api qualitygates/create_condition --data-urlencode "gateName=$GATE" --data-urlencode "metric=$1" \
           --data-urlencode "op=$2" --data-urlencode "error=$3" >/dev/null || echo "condition $1 exists"; }
cond vulnerabilities GT 0
cond blocker_violations GT 0
cond critical_violations GT 0
cond security_rating GT 1
cond security_hotspots_reviewed LT 100
api projects/create --data-urlencode "name=$KEY" --data-urlencode "project=$KEY" >/dev/null || echo "project exists"
api qualitygates/select --data-urlencode "gateName=$GATE" --data-urlencode "projectKey=$KEY"
echo "Quality gate $GATE assigned to $KEY"

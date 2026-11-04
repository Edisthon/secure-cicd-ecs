#!/usr/bin/env bash
# GitOps record of what is deployed: commits the rendered task definition + image.yaml to the
# env/<ENVIRONMENT> branch (an orphan branch holding ONLY deployment state, so it never triggers
# builds). Git history is the audit trail; rollback = `git revert` + scripts/ecs-deploy.sh rollback.
# Pattern adapted from the AOMS shared library step armsGitopsDeploy.
# Required env: GH_USER GH_TOKEN REPO_URL ENVIRONMENT IMAGE_TAG IMAGE_URI TASKDEF_FILE SOURCE_COMMIT
source "$(dirname "$0")/_common.sh"
need GH_USER GH_TOKEN REPO_URL ENVIRONMENT IMAGE_TAG IMAGE_URI TASKDEF_FILE SOURCE_COMMIT
[[ "$IMAGE_TAG" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || die "invalid image tag"
[ -f "$TASKDEF_FILE" ] || die "$TASKDEF_FILE not found"

BRANCH="env/$ENVIRONMENT"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
TASKDEF_ABS="$(cd "$(dirname "$TASKDEF_FILE")" && pwd)/$(basename "$TASKDEF_FILE")"

# Token reaches git through an askpass helper, never a URL or command line.
printf '#!/bin/sh\ncase "$1" in Username*) echo "%s";; *) echo "$GH_TOKEN";; esac\n' "$GH_USER" > "$WORK/askpass"
chmod 700 "$WORK/askpass"
export GIT_ASKPASS="$WORK/askpass" GIT_TERMINAL_PROMPT=0 GH_TOKEN

git clone --quiet "$REPO_URL" "$WORK/repo"
cd "$WORK/repo" || exit 1
git config user.name "Secure CI/CD Jenkins"; git config user.email "jenkins@secure-cicd.invalid"

if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  git fetch --quiet origin "$BRANCH"; git checkout --quiet -B "$BRANCH" "origin/$BRANCH"
else
  git checkout --quiet --orphan "$BRANCH"; git rm -rfq . || true
  printf '# Deployment state for %s (written by Jenkins). Do not edit by hand.\n' "$ENVIRONMENT" > README.md
fi

for attempt in 1 2 3 4 5; do
  mkdir -p "deployments/$ENVIRONMENT"
  cp "$TASKDEF_ABS" "deployments/$ENVIRONMENT/taskdef.json"
  printf 'image:\n  tag: "%s"\n  uri: "%s"\nbuild:\n  commit: "%s"\n  url: "%s"\n' \
    "$IMAGE_TAG" "$IMAGE_URI" "$SOURCE_COMMIT" "${BUILD_URL:-unknown}" > "deployments/$ENVIRONMENT/image.yaml"
  git add -A
  if git diff --cached --quiet; then log "nothing to commit - $ENVIRONMENT already records $IMAGE_TAG"; exit 0; fi
  git commit --quiet -m "deploy($ENVIRONMENT): $IMAGE_TAG [skip ci]" -m "Source: $SOURCE_COMMIT" -m "Build: ${BUILD_URL:-unknown}"
  if git push --quiet origin "HEAD:refs/heads/$BRANCH"; then
    log "Recorded $IMAGE_TAG on $BRANCH ($(git rev-parse --short HEAD)); roll back with: git revert <commit>"
    exit 0
  fi
  log "push raced with another build (attempt $attempt), retrying"
  git fetch --quiet origin "$BRANCH"; git reset --quiet --hard "origin/$BRANCH"
done
die "could not push $BRANCH after 5 attempts"

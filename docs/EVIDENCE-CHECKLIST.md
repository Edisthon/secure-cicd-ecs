# Evidence checklist

Tick each item and store the file under `evidence/<run>/` (see `evidence/README.md`). Screenshots go in `docs/screenshots/`.

## Pipeline and config
- [ ] `Jenkinsfile`, `jenkins-shared-library/`, `scripts/` (in repo)
- [ ] ECS task definition **template**: `ecs/taskdef.template.json`
- [ ] ECS task definition **rendered revision JSON**: `ecs/rendered/taskdef-<tag>.json` from the green build (`example/` shows the shape)

## Failing gate (injected vulnerability)
- [ ] Screenshot: Jenkins stage view with SCA / Trivy / Security Gate red, deploy stages not run
- [ ] Console log lines: `SECURITY GATE FAILED ...`
- [ ] `reports/dependency-check/dependency-check-report.html`, `reports/trivy-image.txt`, `reports/security-summary.md` from that build
- [ ] Proof nothing deployed (ECR image count and ECS task definition revision unchanged)

## Passing gate (after fix)
- [ ] Screenshot: Jenkins stage view all green
- [ ] Reports: Gitleaks (`gitleaks-report.json` absent or empty), `sonar-quality-gate.json` (status OK), Dependency-Check, Trivy
- [ ] **SBOM**: `sbom/sbom.cdx.json` (+ `sbom.spdx.json`)
- [ ] Screenshot: SonarQube project showing the Quality Gate passed

## ECR and ECS
- [ ] Screenshot/CLI: ECR repository with versioned tags, scan results, lifecycle policy
- [ ] `reports/ecs-taskdef-registered.json` and `reports/ecs-service-after.json` (new revision, running = desired)
- [ ] Screenshot: ECS service Deployments tab showing the new task definition revision
- [ ] `reports/post-deploy-version.json` / `curl http://<alb>/version` returns the new tag

## Logs and monitoring
- [ ] Screenshot: CloudWatch Logs `/ecs/secure-cicd-app` with new-build log lines (`trace_id` fields)
- [ ] Screenshot: CloudWatch alarms and the `secure-cicd-deployments` dashboard after the deploy
- [ ] Screenshot or email: deployment-event notification from SNS

## Cleanup
- [ ] `reports/ecs-cleanup.txt` and `reports/ecr-images-after-cleanup.txt`
- [ ] GitOps: the `env/dev` branch showing the `deploy(dev): <tag>` commit

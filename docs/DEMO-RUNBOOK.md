# Demo runbook: prove the gates block, then pass

Do this on a throw-away branch of the Multibranch job. Capture a screenshot or log at each marked step (see `EVIDENCE-CHECKLIST.md`).

## 0. Baseline
Run the pipeline on `main`. Expected: all stages green, ECS service updated, `/version` shows the new tag.
Save this as the **baseline success** (it also proves the clean dependency set).

## 1. Inject a vulnerable dependency (must FAIL)
```bash
scripts/demo-inject-vuln.sh          # adds PyJWT==1.7.1 (HIGH CVE-2022-29217, fixed in 2.4.0) on demo/vulnerable-dependency
git push -u origin demo/vulnerable-dependency
```
Expected in Jenkins:
- **SCA - Dependency-Check** fails (CVSS >= 7) and **Image Scan - Trivy** fails (CRITICAL/HIGH with a fix).
- **Security Gate** stops the build: "SECURITY GATE FAILED ... Nothing was pushed or deployed."
- No new image in ECR, no new task definition revision, the ECS service is unchanged.
- `reports/dependency-check/*.html`, `reports/trivy-image.txt` and `reports/security-summary.md` are archived.

Verify nothing deployed:
```bash
aws ecr describe-images --repository-name secure-cicd-app --query 'length(imageDetails)'   # unchanged
aws ecs describe-services --cluster secure-cicd-cluster --services secure-cicd-service \
  --query 'services[0].taskDefinition'                                                       # unchanged revision
```

## 2. Fix it (must PASS)
```bash
scripts/demo-fix-vuln.sh && git push
```
Expected: every gate green; image pushed; new task definition revision; service rolls to it; `/version` equals the new tag.

```bash
aws ecs describe-services --cluster secure-cicd-cluster --services secure-cicd-service \
  --query 'services[0].{td:taskDefinition,running:runningCount,desired:desiredCount,deployments:deployments[].{status:status,rollout:rolloutState}}'
curl http://<alb_dns_name>/version
```

## 3. Optional: secret gate
```bash
scripts/demo-inject-secret.sh && git push -u origin demo/leaked-secret
```
Expected: **Secret Scan - Gitleaks** fails (the value is redacted in the log), Security Gate stops the build.
Clean up the branch afterwards. A secret that reached history must be rotated, not just deleted.

## 4. Show the alarms reflect the new deployment
- CloudWatch dashboard `secure-cicd-deployments`: running-task count steps during the rollout.
- Generate some traffic: `for i in $(seq 1 200); do curl -s http://<alb>/checkout >/dev/null; done` (5% return 500).
- Alarms `secure-cicd-http-5xx-rate`, `secure-cicd-latency-p95`, `secure-cicd-running-tasks-low` are in the console and keyed on the service, so they cover the new revision automatically.
- Deployment events arrive on the SNS topic (email subscription must be confirmed).
- Logs: CloudWatch > Log groups > `/ecs/secure-cicd-app`, filter `{ $.level = "ERROR" }`.

## 5. Roll back from Git (GitOps)
```bash
git fetch origin env/dev && git checkout env/dev
git log --oneline            # one deploy(dev) commit per release
git revert <bad deploy commit>
scripts/ecs-deploy.sh rollback deployments/dev/taskdef.json   # AWS_REGION, ECS_CLUSTER, ECS_SERVICE exported
```

## 6. Clean up
Re-run the pipeline with `RUN_CLEANUP=true` (keeps 5 task-definition revisions). ECR keeps the newest 10 tagged images and expires untagged ones after a day (lifecycle policy in Terraform). Capture `reports/ecs-cleanup.txt` and `reports/ecr-images-after-cleanup.txt`.

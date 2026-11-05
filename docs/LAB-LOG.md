# Lab log (kept up to date as we go)

Running record of what was built, what broke, and what proves it. Add an entry **right after** each step, not at the end.
The README summarises this file; `EVIDENCE-CHECKLIST.md` is the submission checklist; `DEMO-RUNBOOK.md` has the demo steps.

## How we capture evidence
- Screenshots: `docs/screenshots/NN-short-name.png` (NN = running number, never reuse). Reference each one from the entry below.
- Jenkins keeps every build and its artifacts, so a past build can still be screenshotted later (open it from the job's build list).
- After a build, download its artifacts into `evidence/<NN>-<name>/` (reports, SBOM, rendered task definition) plus the console log as `console.txt`.
- Every entry: **What** (one line), **Command or action**, **Result**, **Evidence** (file or screenshot).

## Environment
| Item | Value |
| --- | --- |
| AWS account / region | 182399707265 (sandbox, 2nd lease; the first lease, 904570587823, expired and was wiped) / eu-west-1 |
| Provisioning | Terraform `terraform/environments/dev` (VPC, ECR, ECS Fargate + ALB, CloudWatch, IAM, Jenkins host) |
| Configuration | Ansible `site.yml` (Docker host prep, SonarQube, Jenkins via Configuration-as-Code) |
| CI | Jenkins multibranch job `secure-cicd-ecs`, shared library `secure-pipeline-lib` |
| Tools | Gitleaks, SonarQube (SAST), OWASP Dependency-Check (SCA), Trivy (image), Syft (SBOM) |
| Deploy | ECS rolling update, circuit breaker with rollback; GitOps record on branch `env/dev` |

## Progress
| # | Step | Status | Evidence |
| --- | --- | --- | --- |
| 1 | Provision AWS infrastructure (Terraform) | done | S01, S02 |
| 2 | Configure Jenkins + SonarQube (Ansible) | done | S03 |
| 3 | First pipeline runs, real findings fixed | done | S04-S06 |
| 4 | Baseline green run + deployment to ECS | done (build #5) | S07-S10 |
| 5 | Demo: injected vulnerable dependency BLOCKS | done (build #2, 595e652) | S11-S13 |
| 6 | Demo: fix, gate PASSES, new revision deployed | done (build #3, 335553f) | S14-S16 |
| 7 | Optional: secret gate (Gitleaks) | done (build #1, 0d4d657) | S17-S18 |
| 8 | Logs, alarms, dashboard after the deploy | done | S19-S24 |
| 9 | GitOps rollback test | done (revision 6) | S25-S28 |
| 10 | Cleanup of old ECR images / ECS revisions | todo | |
| 11 | Architecture diagram + final README polish | todo | |
| 12 | `terraform destroy` | todo | |

## Entries

### 1. Provisioning (done)
- **What:** Terraform created the network (VPC, 2 public subnets, ALB and task security groups), ECR (immutable tags, scan on push, lifecycle policy), ECS Fargate cluster/service behind an ALB, CloudWatch (log group, 6 alarms, dashboard, SNS), IAM roles, then the Jenkins EC2 host with a fixed IP.
- **Commands:** `terraform init -upgrade`, `terraform plan -out tfplan`, `terraform apply tfplan` from `terraform/environments/dev`, with `AWS_PROFILE=sandbox`.
- **Result:** 38 resources created, then 7 more for the Jenkins host. Outputs: ALB DNS name, ECR URL, cluster/service names, Jenkins URL and SSH command.
- **Evidence to capture:** S01 terminal showing `Apply complete` and the outputs; S02 EC2 console with the Jenkins instance `running`.

### 2. Jenkins and SonarQube via Ansible (done)
- **What:** `ansible-playbook -i inventory.generated.ini site.yml --ask-vault-pass` prepares the host, starts SonarQube, sets its admin password, creates a token, the `Secure-Gate` quality gate and the project, then builds and starts Jenkins with credentials, the shared library and the multibranch job (Configuration-as-Code).
- **Result:** play recap with 0 failed. Jenkins login page reachable on port 8080; job `secure-cicd-ecs` created.
- **Evidence to capture:** S03 the play recap; later, SonarQube gate conditions (via an SSH tunnel to port 9000).

### 3. Issues found and fixed on the way (keep this; it shows the gates working)
| When | Symptom | Root cause | Fix |
| --- | --- | --- | --- |
| Provisioning | Jenkins instance disappeared after apply | Encrypted root volume could not launch under the sandbox's service control policy | `encrypt_root_volume = false` (variable in `modules/jenkins_host`) |
| Provisioning | ALB rule for the Jenkins host would be removed on every apply | Inline security-group rules are authoritative | `ignore_changes = [ingress]` on the ALB security group |
| Ansible | Jenkins image build failed | Wrong tool name (`jenkins-plugin-manager`) then wrong plugin id (`timestamps`) | `jenkins-plugin-cli`; plugin id `timestamper` |
| Build #1-#2 | SCA stage never finished | Dependency-Check runs as non-root and could not write to its root-owned data folder | `chmod -R a+rwX` on the data folder in `scripts/dependency-check.sh` |
| Build #3 | SCA ran 51 min, then "Error generating the report" | First NVD download (about 419,000 records) is throttled; report folder also not writable. Script reported any failure as a "gate failure" | Database is cached after the first run; report folder made writable; tool errors now reported separately |
| Build #3 | **SAST gate FAILED** (rating D, 2 vulnerabilities) | Real findings: S2245 weak PRNG (`random`) and S4502 CSRF note on a stateless API | `secrets.randbelow`; documented `NOSONAR` with reason |
| Build #3 | **Image scan gate FAILED** (5 HIGH) | `msgpack`, `setuptools`, `urllib3` shipped with pip in the base image | Production stage removes pip/setuptools/wheel |
| Build #4 | Deploy to ECS failed at RegisterTaskDefinition | Jenkins role lacked `ecs:TagResource` | Scoped permission added in `modules/jenkins_access`; pipeline now fails fast on registration errors |
| Build #5 | Summary shows SAST "not available" | Gate JSON fetched from `localhost:9000`, not reachable inside the Jenkins container | Fetched via a host-network container |
| Lease change | Key stopped working ("InvalidClientTokenId"); Jenkins and all resources gone | The sandbox lease expired and the account was wiped; a new account was assigned | New IAM user + key; old Terraform state moved aside; Terraform + Ansible re-run; account ID in the vault updated |
| New account | Terraform failed on `ssm:GetParameter` / `ec2:DescribeAvailabilityZones`; every service denied for an IAM-user key | Organization service control policy only allowed the portal's own session at first | Temporary credentials from CloudShell for Terraform; later the policy was loosened and IAM-user keys worked |
| New account | Jenkins instance role denied (`explicit deny in a service control policy`) | Same policy also blocked the instance role | Temporary workaround script `scripts/push-aws-creds.sh`; removed once the policy was relaxed |
| Build #2 (new account) | Push to ECR failed with `ExpiredToken` | The temporary credentials file had expired | File removed; Jenkins uses its instance role again |

Evidence to capture: S04 Jenkins stage view of build #3 (red SAST/SCA/Trivy, Security Gate stopping, deploy stages skipped); S05 the console lines `QUALITY GATE STATUS: FAILED` and `IMAGE SCAN GATE FAILED`; S06 the build #4 console line with `AccessDeniedException`. All three builds are still in Jenkins history.

### 4. Baseline green run (done)
- First account: build #5, commit 18c695c. Re-done in the new account: build #3, commit 91a522b (same result, all stages green, `/version` = `3-91a522b`).
- **Result:** unit tests 10 passed; Gitleaks 0 findings; SonarQube gate PASSED; Dependency-Check and Trivy CRITICAL=0 HIGH=0; Syft SBOM with 2853 components; image `5-18c695c` pushed to ECR by digest; task definition revision 2 registered; rolling update completed with 2/2 tasks; ALB answered `/health` and `/version` = `5-18c695c`; deployment recorded on `env/dev`.
- **Evidence to capture:** S07 stage view all green; S08 ECR repository (tags, scan results); S09 ECS service Deployments tab (revision 2, 2/2 running); S10 `curl http://<alb>/version` in a terminal. Download build #5 artifacts into `evidence/01-baseline-green/`.

### 5. Injected vulnerable dependency is blocked (done)
- **What:** branch `demo/vulnerable-dependency` adds `PyJWT==1.7.1` to `app/requirements.txt` (`scripts/demo-inject-vuln.sh`).
- **Result (build #2, 595e652):** Gitleaks 0 findings, SonarQube gate passed, **Trivy failed: CRITICAL=1, HIGH=5**, all from `PyJWT-1.7.1` (fixed versions 2.12.0 to 2.14.0; critical is CVE-2026-102268, authentication bypass). Security Gate stopped the build: `Nothing was pushed or deployed`. Push, render, deploy and GitOps stages did not run.
- **Finding worth reporting:** Dependency-Check (SCA) reported CRITICAL=0 HIGH=0 for the same dependency. It matches packages to CVEs by CPE and does not always match Python packages; Trivy matches by package ecosystem and caught it. This is why the pipeline runs more than one scanner.
- **Proof nothing deployed:** ECR holds only `3-91a522b` and `4-c704cec` (no `2-595e652`); the service was untouched by this build.
- **Evidence:** S11 stage view, S12 console (Trivy table and gate error), S13 terminal with the ECS and ECR checks; log in `evidence/02-blocked/`.

### 6. Fix and re-run: gate passes (done)
- **What:** `scripts/demo-fix-vuln.sh` removes the `PyJWT==1.7.1` pin and commits.
- **Result (build #3, 335553f):** all scans clean (Trivy CRITICAL=0 HIGH=0), image `3-335553f` pushed by digest, task definition revision 4 registered, rolling deployment `COMPLETED` (about 3 minutes), live `/version` = `3-335553f`, GitOps record on `env/dev` (e50f8a2). Cleanup stage skipped (`RUN_CLEANUP` not set).
- **Evidence:** S14 all-green stage view, S15 console, S16 `curl /version`; log in `evidence/03-fixed/`.

### 7. Secret gate (done)
- **What:** `scripts/demo-inject-secret.sh` commits a fake AWS key in `app/leaked.env` on branch `demo/leaked-secret` (key assembled at runtime, never in a tracked script).
- **Result (build #1, 0d4d657):** Gitleaks rule `aws-access-token` found 1 leak in `app/leaked.env` (value redacted in the log); Security Gate failed the build; nothing pushed or deployed.
- **Evidence:** S17 stage view, S18 console; log in `evidence/04-secret-blocked/`.
- **Cleanup:** delete the demo branch afterwards (`git push origin --delete demo/leaked-secret`).

### 8. Logs, alarms and dashboard (done)
- **What:** generated traffic against the ALB (`/checkout` in a loop; the app fails about 5% of calls on purpose) and checked the CloudWatch dashboard `secure-cicd-deployments`, the log group `/ecs/secure-cicd-app`, the 6 alarms and the SNS topic `secure-cicd-alerts`.
- **Dashboard:** requests peak at about 63, with a visible 5xx blip; CPU and memory move during the loop and the deploy; running tasks stay at 2 (S19).
- **Logs:** structured JSON from the app with `trace_id` and `span_id`: an INFO `Starting checkout process`, then an ERROR `Checkout failed! Database connection lost.`, and the matching `GET /checkout ... 500` access line (S20).
- **Alarms:** 6 alarms, all OK at rest (S21): `http-5xx-rate`, `app-error-logs`, `running-tasks-low`, `latency-p95`, `unhealthy-targets` and one more.
- **Alert path, proven end to end:** `secure-cicd-http-5xx-rate` (metric expression `100 * errors / MAX([errors, requests])`, threshold 5, one 300 s period) went **OK to ALARM at 15:25:09 UTC** (datapoint 50.0), and back **ALARM to OK at 15:32:09 UTC** (datapoint 2.86). Both emails arrived from AWS Notifications (S23, S24). The SNS subscription is Confirmed (S22).
- **Lesson:** the first loop ran while the SNS subscription was still *pending confirmation*, so that alarm sent nothing. Confirm the subscription email right after `terraform apply`.
- **Note:** at very low traffic one failed request is a 50% error rate, so the 5xx alarm is noisy on an idle service. A real setup would add a minimum request count.
- **Evidence:** S19 dashboard, S20 app logs, S21 alarm list, S22 SNS Confirmed, S23 ALARM email, S24 OK email.

### 9. GitOps rollback (done)
- **What:** prove a release can be undone from Git. Branch `env/dev` holds one commit per deploy (rendered task definition + `image.yaml`); the live record was `5-244b0d0` (commit 09c3492, ECS revision 5, from `main`).
- **Actions:** `git revert 09c3492` on `env/dev` in a separate worktree (the branch is an orphan holding only deployment state), push; then `scripts/ecs-deploy.sh rollback` with the reverted `deployments/dev/taskdef.json`. The first run stopped because `jq` was missing in WSL (the register step had already run), so after `apt-get install jq` the run was finished with `ecs-deploy.sh update <revision 6 ARN>` and `ecs-deploy.sh wait`.
- **Result:** the rollback registered task definition **revision 6** from the old record (image pinned by digest), the service moved 5 to 6 as a rolling update, `rolloutState=COMPLETED`, 2/2 tasks running, in about 3 minutes. Expected live version after rollback: `3-335553f` (S28 shows the `/version` output).
- **Why it works:** the task definition in Git pins the image by digest and ECR tags are immutable, so redeploying the old record gives exactly the old build. The rollback creates a new revision rather than reusing an old one.
- **Evidence:** S25 `/version` before (`5-244b0d0`), S26 the revert on `env/dev`, S27 the rollback run, S28 `/version` after; ECS outputs in `evidence/05-rollback/`.
- **Note:** the real fix for a bad release is still a new commit through the pipeline; rollback is the emergency path.

### 10-12. To do (fill in as we go)
Follow `DEMO-RUNBOOK.md`. For each step add an entry here with the result and the screenshot numbers.

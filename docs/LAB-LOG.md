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
| AWS account / region | 904570587823 (sandbox) / eu-west-1 |
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
| 5 | Demo: injected vulnerable dependency BLOCKS | todo | |
| 6 | Demo: fix, gate PASSES, new revision deployed | todo | |
| 7 | Optional: secret gate (Gitleaks) | todo | |
| 8 | Logs, alarms, dashboard after the deploy | todo | |
| 9 | GitOps rollback test | todo | |
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

Evidence to capture: S04 Jenkins stage view of build #3 (red SAST/SCA/Trivy, Security Gate stopping, deploy stages skipped); S05 the console lines `QUALITY GATE STATUS: FAILED` and `IMAGE SCAN GATE FAILED`; S06 the build #4 console line with `AccessDeniedException`. All three builds are still in Jenkins history.

### 4. Baseline green run (done: build #5, commit 18c695c)
- **Result:** unit tests 10 passed; Gitleaks 0 findings; SonarQube gate PASSED; Dependency-Check and Trivy CRITICAL=0 HIGH=0; Syft SBOM with 2853 components; image `5-18c695c` pushed to ECR by digest; task definition revision 2 registered; rolling update completed with 2/2 tasks; ALB answered `/health` and `/version` = `5-18c695c`; deployment recorded on `env/dev`.
- **Evidence to capture:** S07 stage view all green; S08 ECR repository (tags, scan results); S09 ECS service Deployments tab (revision 2, 2/2 running); S10 `curl http://<alb>/version` in a terminal. Download build #5 artifacts into `evidence/01-baseline-green/`.

### 5-12. To do (fill in as we go)
Follow `DEMO-RUNBOOK.md`. For each step add an entry here with the result and the screenshot numbers.

# Provision and test - step by step

Run order matters: **AWS infrastructure first, then Jenkins, then the first pipeline run.** Commands assume a Linux shell
(WSL Ubuntu on your Windows machine is fine) and region `eu-west-1`. Nothing here has been run yet - if a step errors,
keep the error text; it is the input for the next fix.

## 0. Laptop prerequisites
- `aws sts get-caller-identity` works (profile or SSO configured for the lab account)
- `terraform -version` >= 1.5, `git`, `gh` (optional), Ansible (`pip install ansible boto3 botocore jmespath`; on Windows use WSL Ubuntu)
- The SSH private key matching Mod7's `Jenkins_keypair`
- Your public IP: `curl -s https://checkip.amazonaws.com`

## 1. Find out what Mod7 left running
```bash
cd Mod7/jenkins-lab/environments/dev && terraform output
```
- Outputs show a Jenkins IP -> reuse it (go to step 2).
- Nothing / errors -> recreate only what Jenkins needs (skips the monitoring and logging servers you don't need):
  `terraform apply -target=module.network -target=module.ssh_key -target=module.jenkins_server`
  then run the Mod7 Ansible `docker` role against it so Docker and docker-compose exist.
- If SSH times out, your public IP changed: re-run `terraform apply` there (the SSH rule uses your IP at apply time).

## 2. Provision the Mod9 AWS infrastructure (Terraform)
```bash
cd Mod9/secure-cicd-ecs/terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars      # set allowed_ingress_cidrs = ["<your-ip>/32"], alert_email
terraform init && terraform validate && terraform plan -out tfplan
terraform apply tfplan
terraform output                                   # keep: ECR URL, ALB DNS, jenkins_instance_profile
```
Creates ECR (immutable, scan on push, lifecycle), VPC + 2 public subnets, ALB, ECS cluster + service (0 tasks until the first deploy),
task roles, log group, 6 alarms + deployment-event rule + dashboard, and the Jenkins role/instance profile.
**Confirm the SNS subscription email** AWS sends to `alert_email`.

> **The ALB only accepts the IPs in `allowed_ingress_cidrs`.** The pipeline's "verify" step runs `curl` against the ALB **from the Jenkins host**,
> so after step 3 (when you know the Jenkins public IP) add it and re-apply:
> `allowed_ingress_cidrs = ["<your-ip>/32", "<jenkins-ip>/32"]` then `terraform apply` (takes seconds). Re-do this if the Jenkins IP changes.

## 3. Prepare the Jenkins host (Ansible: `aws-prep.yml`)
Replaces the manual resize / disk / IAM / metadata-hop-limit steps. Needs the AWS CLI and boto3 on your laptop.
```bash
cd Mod9/secure-cicd-ecs/ansible
ansible-galaxy collection install -r requirements.yml
ID=$(aws ec2 describe-instances --region eu-west-1 --filters "Name=tag:name,Values=Jenkins-Controller" \
     "Name=instance-state-name,Values=running,stopped" --query 'Reservations[0].Instances[0].InstanceId' --output text)
ansible-playbook aws-prep.yml -e jenkins_instance_id=$ID \
  -e jenkins_instance_profile=$(terraform -chdir=../terraform/environments/dev output -raw jenkins_instance_profile) \
  -e ssh_key_path=~/.ssh/jenkins-keypair
```
It sets the instance to t3.large, attaches the instance profile, sets IMDS hop limit 2 (so the AWS CLI inside the Jenkins container
gets credentials), grows the EBS volume to 40 GB, waits for SSH, and writes `inventory.generated.ini` with the new public IP
(the IP changes after the stop/start). If the instance tag filter finds nothing, pass the instance id from the console.
Also set `instance_type = "t3.large"` for the Jenkins module in Mod7 so a later Mod7 apply does not shrink it.

## 4. Configure everything on the host (Ansible: `site.yml`)
Replaces manual SonarQube setup, `scripts/sonar-bootstrap.sh`, and clicking through Jenkins.
```bash
cp group_vars/all/vault.yml.example group_vars/all/vault.yml     # fill in the values, then:
ansible-vault encrypt group_vars/all/vault.yml
# edit group_vars/all/main.yml: github_owner (and github_repo if you named it differently)
ansible-playbook site.yml --ask-vault-pass
```
What it does, in order (all idempotent, safe to re-run):
1. **host_prep** - `vm.max_map_count`, grows the filesystem, same-path `/var/jenkins_home`, copies the compose project.
2. **sonarqube** - starts SonarQube + Postgres, waits for UP, changes the default admin password, creates (or reuses) the `jenkins` token,
   creates the `Secure-Gate` quality gate with its conditions, creates the project and assigns the gate.
3. **jenkins** - writes secrets as files (mounted at `/run/secrets`, never in the environment), renders the Configuration-as-Code file
   (admin user, the four credentials, the `secure-pipeline-lib` shared library with path `jenkins-shared-library`, and the Multibranch job),
   builds and starts Jenkins, and creates the GitHub push webhook.

Verify on the host (`ssh -i <key> ec2-user@<ip>`):
```bash
docker ps                                              # jenkins, sonarqube, sonar-db all Up
docker exec jenkins aws sts get-caller-identity        # shows the secure-cicd-jenkins role
docker exec jenkins docker ps                          # Docker socket works
curl -s localhost:9000/api/system/status               # {"status":"UP"}
```
Then open `http://<ip>:8080` and log in as `admin` with `vault_jenkins_admin_password`. Under Credentials you should see
`aws-account-id`, `sonar-token`, `nvd-api-key`, `github-gitops-token`; under Manage Jenkins > System, the `secure-pipeline-lib` library;
and a Multibranch job that scans the repo. (SonarQube stays private: for the UI use `ssh -L 9000:localhost:9000 ...`.)
This replaces the Mod7 Jenkins container; old jobs and credentials are not migrated.

## 5. Push the repo
The job and library point at GitHub, so the code must be there (Ansible does not need it pushed first, but the first scan does).
```bash
cd Mod9/secure-cicd-ecs
git init -b main && git add . && git status          # confirm: no .env, tfstate, *.tfvars, vault.yml, inventory.generated.ini
git commit -m "Mod9: secure CI/CD pipeline for ECS"
gh repo create <owner>/secure-cicd-ecs --private --source=. --push      # or create on github.com and add the remote
```
In Jenkins press **Scan Repository Now** on the job (or push a commit; the webhook triggers it).

## 6. Things Ansible does not do
- Your AWS credentials, the `jenkins-keypair` private key, and the vault password stay on your laptop.
- The GitHub PAT must already exist (scopes: `repo`, plus `admin:repo_hook` if you keep `manage_github_webhook: true`).
- The first SonarQube **security hotspots** (if any) must be reviewed in the UI by a person; that is a deliberate human step.

## 7. First run on `main` (the baseline)
It should go green. What to expect and watch for:
| Stage | Notes |
| --- | --- |
| Unit Tests | first Docker pulls, a few minutes |
| Dependency-Check | **slow the first time** (NVD download; faster with the key). Cached afterwards |
| SonarQube | waits up to 5 minutes for the gate; first analysis can show hotspots to review in the UI (`security_hotspots_reviewed`) - review or mark them safe, then re-run |
| Trivy | downloads its DB; Docker Hub/ghcr rate limits show as `TOOMANYREQUESTS` - re-run |
| Security Gate -> Deploy | a failure here means a real finding: read `reports/security-summary.md` |
Verify the deployment:
```bash
aws ecs describe-services --region eu-west-1 --cluster secure-cicd-cluster --services secure-cicd-service \
  --query 'services[0].{td:taskDefinition,running:runningCount,desired:desiredCount}'
curl http://$(terraform output -raw alb_dns_name)/version      # returns the build tag, e.g. {"version":"1-ab12cd3"}
```
If tasks won't start: `aws ecs list-tasks --desired-status STOPPED ...` then `describe-tasks` and read `stoppedReason`
(common: cannot pull from ECR = task security group/egress or no public IP; failing health check = port 8080 / `/health`).

## 8. The lab's tests (see DEMO-RUNBOOK.md)
1. `scripts/demo-inject-vuln.sh`, push the branch -> **must fail**, nothing pushed/deployed. Save screenshots + reports.
2. `scripts/demo-fix-vuln.sh`, push -> **must pass**, ECS updated.
3. Optional: `scripts/demo-inject-secret.sh` -> Gitleaks fails.
4. Generate traffic and show alarms/logs/dashboard; run a build with `RUN_CLEANUP=true`.
Collect everything on the `docs/EVIDENCE-CHECKLIST.md` list **before** destroying anything.

## 9. Tear down (when evidence is captured)
```bash
cd terraform/environments/dev && terraform destroy       # ALB + Fargate cost money while up
# then stop or destroy the Mod7 Jenkins host if you are done with it
```
Rotate or delete the Sonar, GitHub and NVD tokens you created for the lab.

## Then: documentation and diagram
While testing, keep screenshots as you go. Afterwards the final write-up (architecture diagram, pipeline flow, evidence, lessons learned)
is built from `README.md` + `evidence/`.

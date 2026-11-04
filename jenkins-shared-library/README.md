# secure-pipeline-lib (Jenkins shared library)

Thin Groovy steps over the repo's `scripts/` (the logic lives in shell so it can be run and tested
outside Jenkins). Style and defaults follow the AOMS `Jenkins-Shared-Libraries` repo
(`omsSecretScan`, `omsTrivyImageScan`, `sonarQubeQualityGate`, `omsPushImageToECR`, `armsGitopsDeploy`).

Register it in Jenkins: **Manage Jenkins > System > Global Trusted Pipeline Libraries**
- Name: `secure-pipeline-lib`   Default version: `main`
- Retrieval: Modern SCM > GitHub > this repository
- **Library Path: `jenkins-shared-library`** (the library lives in a sub-folder of this repo)

| Step | Wraps | Gate |
| --- | --- | --- |
| `secGitleaks()` | `scripts/gitleaks.sh` | any secret fails |
| `secSonarScan()` | `scripts/sonar-scan.sh` | Quality Gate must be OK |
| `secDependencyCheck()` | `scripts/dependency-check.sh` | CVSS >= 7 fails |
| `secTrivyImageScan(image)` | `scripts/trivy-scan.sh` | HIGH/CRITICAL (fixed) fails |
| `secGenerateSbom(image)` | `scripts/sbom.sh` | fails only if no SBOM produced |
| `secSecurityGate()` | `scripts/summarize-findings.sh` | fails the build if any scan failed |
| `ecrPushImage(image)` | `scripts/ecr-push.sh` | - |
| `ecsRenderTaskDef()` | `scripts/ecs-render-taskdef.sh` | invalid JSON/keys fail |
| `ecsDeploy()` | `scripts/ecs-deploy.sh` | rollout FAILED / not serving new build fails |
| `ecsCleanup()` | `scripts/ecs-cleanup.sh` | - |
| `gitopsRecordDeploy()` | `scripts/gitops-record.sh` | - |

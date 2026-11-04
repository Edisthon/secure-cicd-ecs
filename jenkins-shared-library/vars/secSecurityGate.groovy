/**
 * Final security gate. Scan stages run inside catchError so ALL of them execute and ALL reports are
 * produced; this step then turns any recorded failure into a hard stop BEFORE anything is pushed
 * to ECR or deployed to ECS.
 */
def call(Map config = [:]) {
    sh 'scripts/summarize-findings.sh || true'
    def result = currentBuild.currentResult
    if (result != 'SUCCESS') {
        error "SECURITY GATE FAILED (build result: ${result}). Review reports/security-summary.md and the failed scan stage(s). Nothing was pushed or deployed."
    }
    echo 'Security gate passed: no Critical/High findings and no secrets.'
}

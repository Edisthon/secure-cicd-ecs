/**
 * GitOps record: commits the rendered task definition + image.yaml to the env/<environment> branch.
 * Needs a Jenkins "Username with password" credential (GitHub PAT) - default id 'github-gitops-token'.
 * Never fails the build: a problem here marks the stage UNSTABLE.
 */
def call(Map config = [:]) {
    def credId = config.credentialsId ?: 'github-gitops-token'
    def environment = config.environment ?: 'dev'
    catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
        withCredentials([usernamePassword(credentialsId: credId, usernameVariable: 'GH_USER', passwordVariable: 'GH_TOKEN')]) {
            withEnv([
                "ENVIRONMENT=${environment}",
                "REPO_URL=${env.GIT_URL}",
                "SOURCE_COMMIT=${env.GIT_COMMIT}",
            ]) {
                sh 'scripts/gitops-record.sh'
            }
        }
    }
}

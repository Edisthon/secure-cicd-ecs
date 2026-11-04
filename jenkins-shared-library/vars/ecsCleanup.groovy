/** Deregisters old task-definition revisions (keeps KEEP_REVISIONS, default 5). ECR images expire via the lifecycle policy. */
def call(Map config = [:]) {
    withEnv(["KEEP_REVISIONS=${config.keep ?: 5}", "DRY_RUN=${config.dryRun ?: false}"]) {
        sh 'scripts/ecs-cleanup.sh'
    }
}

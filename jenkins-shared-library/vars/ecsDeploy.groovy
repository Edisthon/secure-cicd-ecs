/**
 * Registers a new task-definition revision from env.TASKDEF_FILE, points the ECS service at it
 * (rolling update, circuit breaker enabled in Terraform), waits for the rollout and verifies the new
 * build serves traffic through the ALB.
 *   ecsDeploy()                  // register + update + wait + verify
 *   ecsDeploy(verify: false)     // skip the ALB check
 */
def call(Map config = [:]) {
    def file = config.taskDefFile ?: env.TASKDEF_FILE
    if (!file) { error 'ecsDeploy: taskDefFile is required (or run ecsRenderTaskDef first)' }
    def arn = sh(returnStdout: true, script: "scripts/ecs-deploy.sh register '${file}' | tail -1").trim()
    env.TASKDEF_ARN = arn
    sh "scripts/ecs-deploy.sh update '${arn}'"
    sh 'scripts/ecs-deploy.sh wait'
    if (config.containsKey('verify') ? config.verify : true) {
        sh 'scripts/ecs-deploy.sh verify'
    }
}

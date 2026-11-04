/** Renders ecs/taskdef.template.json to ecs/rendered/taskdef-<IMAGE_TAG>.json; sets env.TASKDEF_FILE. */
def call(Map config = [:]) {
    sh 'scripts/ecs-render-taskdef.sh'
    env.TASKDEF_FILE = readFile('reports/rendered-taskdef-path.txt').trim()
}

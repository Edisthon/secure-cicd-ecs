/** Secret scan with Gitleaks (containerised). Fails the step on any finding. See scripts/gitleaks.sh. */
def call(Map config = [:]) {
    sh 'scripts/gitleaks.sh'
}

/**
 * SCA with OWASP Dependency-Check. Fails on CVSS >= failCvss (default 7 = High + Critical).
 *   secDependencyCheck(failCvss: 7)
 * Optional env: NVD_API_KEY (use 'none' to skip).
 */
def call(Map config = [:]) {
    withEnv(["FAIL_CVSS=${config.failCvss ?: 7}"]) {
        sh 'scripts/dependency-check.sh'
    }
}

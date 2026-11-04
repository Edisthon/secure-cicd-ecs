/**
 * SAST with SonarQube. Runs the scanner container and waits for the Quality Gate (fails when red).
 * Needs credentials in env: SONAR_HOST_URL, SONAR_TOKEN.
 */
def call(Map config = [:]) {
    sh 'scripts/sonar-scan.sh'
}

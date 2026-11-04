/**
 * Image scan with Trivy. Writes reports/trivy-image.{json,txt} and FAILS on HIGH/CRITICAL findings
 * that have a fix available.
 *   secTrivyImageScan(image: env.LOCAL_IMAGE)
 *   secTrivyImageScan(image: env.LOCAL_IMAGE, severity: 'CRITICAL')
 */
def call(Map config = [:]) {
    def image = config.image ?: env.LOCAL_IMAGE
    if (!image) { error 'secTrivyImageScan: image is required (or set env.LOCAL_IMAGE)' }
    withEnv(["TRIVY_SEVERITY=${config.severity ?: 'HIGH,CRITICAL'}"]) {
        sh "scripts/trivy-scan.sh '${image}'"
    }
}

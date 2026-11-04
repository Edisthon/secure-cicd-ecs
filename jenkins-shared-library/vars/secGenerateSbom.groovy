/** SBOM with Syft: sbom/sbom.cdx.json (CycloneDX) and sbom/sbom.spdx.json. */
def call(Map config = [:]) {
    def image = config.image ?: env.LOCAL_IMAGE
    if (!image) { error 'secGenerateSbom: image is required (or set env.LOCAL_IMAGE)' }
    sh "scripts/sbom.sh '${image}'"
}

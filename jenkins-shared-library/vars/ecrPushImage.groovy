/**
 * Pushes the (already scanned) local image to ECR under the immutable versioned tag env.IMAGE_TAG and
 * records the digest-pinned reference in env.IMAGE_URI. AWS access comes from the Jenkins instance
 * profile (no long-lived keys). Required env: AWS_REGION, ECR_REGISTRY, ECR_REPOSITORY, IMAGE_TAG.
 */
def call(Map config = [:]) {
    def image = config.image ?: env.LOCAL_IMAGE
    if (!image) { error 'ecrPushImage: image is required (or set env.LOCAL_IMAGE)' }
    sh "scripts/ecr-push.sh '${image}'"
    env.IMAGE_URI = readFile('reports/image-uri.txt').trim()
    echo "ecrPushImage: ${env.IMAGE_URI}"
}

// Secure CI/CD pipeline: scans gate the build, then ECR -> ECS (Fargate) rolling deployment.
// Logic lives in scripts/ and is exposed as steps by jenkins-shared-library/ (see its README).
@Library('secure-pipeline-lib') _

pipeline {
    agent any

    options {
        timestamps()
        timeout(time: 75, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20', artifactNumToKeepStr: '10'))
    }

    parameters {
        booleanParam(name: 'GITOPS_RECORD', defaultValue: true,  description: 'Commit the rendered task definition to the env/dev branch after a successful deploy')
        booleanParam(name: 'RUN_CLEANUP',   defaultValue: false, description: 'Deregister old task-definition revisions after a validated deploy')
    }

    environment {
        // ---- AWS / ECS (names match terraform/environments/dev) ----
        AWS_REGION         = 'eu-west-1'
        AWS_ACCOUNT_ID     = credentials('aws-account-id')          // Secret text
        ECR_REPOSITORY     = 'secure-cicd-app'
        ECR_REGISTRY       = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        ECS_CLUSTER        = 'secure-cicd-cluster'
        ECS_SERVICE        = 'secure-cicd-service'
        ECS_TASK_FAMILY    = 'secure-cicd-app'
        ECS_CONTAINER_NAME = 'app'
        LOG_GROUP          = '/ecs/secure-cicd-app'
        ALB_NAME           = 'secure-cicd-alb'
        EXECUTION_ROLE_ARN = "arn:aws:iam::${AWS_ACCOUNT_ID}:role/secure-cicd-task-execution"
        TASK_ROLE_ARN      = "arn:aws:iam::${AWS_ACCOUNT_ID}:role/secure-cicd-task"
        DESIRED_COUNT      = '2'
        // ---- scanners ----
        SONAR_HOST_URL     = 'http://localhost:9000'
        SONAR_TOKEN        = credentials('sonar-token')              // Secret text
        NVD_API_KEY        = credentials('nvd-api-key')              // Secret text ('none' if you have no key)
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_SHORT = env.GIT_COMMIT.take(7)
                    env.IMAGE_TAG = "${env.BUILD_NUMBER}-${env.GIT_SHORT}"      // immutable, versioned tag
                    env.LOCAL_IMAGE = "${env.ECR_REPOSITORY}:${env.IMAGE_TAG}"
                    currentBuild.displayName = "#${env.BUILD_NUMBER} ${env.GIT_SHORT}"
                }
                sh 'mkdir -p reports sbom ecs/rendered && chmod +x scripts/*.sh'
            }
        }

        stage('Unit Tests') {
            steps {
                // pytest runs inside the Dockerfile "test" stage; a failure stops the pipeline here.
                dir('app') {
                    sh "docker build --target test -t ${ECR_REPOSITORY}-test:${IMAGE_TAG} ."
                }
            }
        }

        stage('Security Scans (code)') {
            parallel {
                stage('Secret Scan - Gitleaks') {
                    steps { catchError(buildResult: 'FAILURE', stageResult: 'FAILURE') { secGitleaks() } }
                }
                stage('SAST - SonarQube') {
                    steps { catchError(buildResult: 'FAILURE', stageResult: 'FAILURE') { secSonarScan() } }
                }
                stage('SCA - Dependency-Check') {
                    steps { catchError(buildResult: 'FAILURE', stageResult: 'FAILURE') { secDependencyCheck(failCvss: 7) } }
                }
            }
        }

        stage('Build Image') {
            steps {
                dir('app') {
                    sh "docker build --target production --build-arg APP_VERSION=${IMAGE_TAG} -t ${LOCAL_IMAGE} ."
                }
            }
        }

        stage('Security Scans (image)') {
            parallel {
                stage('Image Scan - Trivy') {
                    steps { catchError(buildResult: 'FAILURE', stageResult: 'FAILURE') { secTrivyImageScan(image: env.LOCAL_IMAGE) } }
                }
                stage('SBOM - Syft') {
                    steps { catchError(buildResult: 'FAILURE', stageResult: 'FAILURE') { secGenerateSbom(image: env.LOCAL_IMAGE) } }
                }
            }
        }

        // Everything above ran so every report exists. Any failure stops the pipeline HERE,
        // before an image is pushed to ECR or anything is deployed.
        stage('Security Gate') {
            steps { secSecurityGate() }
        }

        stage('Push to ECR') {
            steps { ecrPushImage(image: env.LOCAL_IMAGE) }
        }

        stage('Render Task Definition') {
            steps { ecsRenderTaskDef() }
        }

        stage('Deploy to ECS') {
            steps { ecsDeploy() }
        }

        stage('GitOps Record') {
            when { expression { params.GITOPS_RECORD } }
            steps { gitopsRecordDeploy(environment: 'dev') }
        }

        stage('Cleanup Old Revisions') {
            when { expression { params.RUN_CLEANUP } }
            steps { ecsCleanup(keep: 5) }
        }
    }

    post {
        always {
            sh 'scripts/summarize-findings.sh || true'
            archiveArtifacts artifacts: 'reports/**, sbom/**, ecs/rendered/**', allowEmptyArchive: true, fingerprint: true
            sh "docker image rm -f ${LOCAL_IMAGE} ${ECR_REPOSITORY}-test:${IMAGE_TAG} || true"
            sh 'rm -rf .sca-deps .scannerwork || true'
        }
        success { echo "Deployed ${env.IMAGE_TAG} to ${env.ECS_SERVICE}. Evidence archived on this build." }
        failure { echo 'Pipeline failed. Check the failed scan stage and reports/security-summary.md - nothing was deployed if the Security Gate failed.' }
    }
}

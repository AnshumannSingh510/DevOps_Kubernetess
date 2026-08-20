// Jenkinsfile — CI/CD pipeline for the devops-demo application.
//
// Required Jenkins Credentials (Manage Jenkins -> Credentials -> System -> Global credentials):
//   dockerhub-credentials   (Username with password) - Docker Hub username + access token
//   github-credentials      (Username with password OR SSH key) - push access to GitOps repo
//   sonarqube-token         (Secret text) - SonarQube user token
//
// Required Jenkins Global Tool / System configuration:
//   Manage Jenkins -> System -> SonarQube servers -> name "LocalSonarQube", URL http://sonarqube:9000
//   (token supplied via the sonarqube-token credential above)

pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '15'))
        timeout(time: 45, unit: 'MINUTES')
    }

    environment {
        APP_NAME          = "devops-demo"
        DOCKER_IMAGE      = "${env.DOCKERHUB_USERNAME ?: 'local'}/${APP_NAME}"
        IMAGE_TAG         = "${env.BUILD_NUMBER}-${env.GIT_COMMIT?.take(7) ?: 'dev'}"
        K8S_NAMESPACE     = "devops-demo"
        SONARQUBE_ENV     = "LocalSonarQube"
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_COMMIT_SHORT = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
                    env.IMAGE_TAG = "${env.BUILD_NUMBER}-${env.GIT_COMMIT_SHORT}"
                }
                echo "Building ${APP_NAME}:${env.IMAGE_TAG}"
            }
        }

        stage('Build') {
            steps {
                dir('app') {
                    sh 'mvn -B -ntp clean compile'
                }
            }
        }

        stage('Unit Tests') {
            steps {
                dir('app') {
                    sh 'mvn -B -ntp test'
                }
            }
            post {
                always {
                    junit testResults: 'app/target/surefire-reports/*.xml', allowEmptyResults: true
                }
                failure {
                    echo 'Unit tests failed - pipeline will stop here.'
                }
            }
        }

        stage('Code Coverage') {
            steps {
                dir('app') {
                    sh 'mvn -B -ntp jacoco:report'
                }
            }
            post {
                always {
                    publishHTML(target: [
                        reportDir: 'app/target/site/jacoco',
                        reportFiles: 'index.html',
                        reportName: 'JaCoCo Coverage Report',
                        keepAll: true,
                        alwaysLinkToLastBuild: true,
                        allowMissing: true
                    ])
                }
            }
        }

        stage('SonarQube Analysis') {
            steps {
                dir('app') {
                    withSonarQubeEnv("${SONARQUBE_ENV}") {
                        withCredentials([string(credentialsId: 'sonarqube-token', variable: 'SONAR_TOKEN')]) {
                            sh """
                                mvn -B -ntp sonar:sonar \
                                  -Dsonar.projectKey=${APP_NAME} \
                                  -Dsonar.token=\$SONAR_TOKEN
                            """
                        }
                    }
                }
            }
        }

        stage('Quality Gate') {
            steps {
                // Fails the build automatically if the SonarQube Quality Gate is not "OK".
                timeout(time: 10, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Docker Build') {
            steps {
                dir('app') {
                    sh "docker build -t ${DOCKER_IMAGE}:${env.IMAGE_TAG} -t ${DOCKER_IMAGE}:latest ."
                }
            }
        }

        stage('Docker Image Security Scan') {
            steps {
                // Trivy is used here because it runs as a single container with no
                // separate service to stand up. The build fails on HIGH/CRITICAL
                // vulnerabilities that already have a fix available.
                sh """
                    docker run --rm \
                      -v /var/run/docker.sock:/var/run/docker.sock \
                      aquasec/trivy:latest image \
                      --severity HIGH,CRITICAL \
                      --ignore-unfixed \
                      --exit-code 1 \
                      ${DOCKER_IMAGE}:${env.IMAGE_TAG}
                """
            }
        }

        stage('Push Docker Image') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub-credentials',
                                                   usernameVariable: 'DOCKERHUB_USER',
                                                   passwordVariable: 'DOCKERHUB_PASS')]) {
                    sh """
                        echo "\$DOCKERHUB_PASS" | docker login -u "\$DOCKERHUB_USER" --password-stdin
                        docker push ${DOCKER_IMAGE}:${env.IMAGE_TAG}
                        docker push ${DOCKER_IMAGE}:latest
                        docker logout
                    """
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                sh """
                    kubectl apply -f k8s/namespace.yaml
                    kubectl apply -f k8s/configmap.yaml
                    kubectl apply -f k8s/secret.yaml
                    kubectl apply -f k8s/service.yaml
                    kubectl -n ${K8S_NAMESPACE} set image deployment/${APP_NAME} ${APP_NAME}=${DOCKER_IMAGE}:${env.IMAGE_TAG} --record || \
                      kubectl apply -f k8s/deployment.yaml
                    kubectl -n ${K8S_NAMESPACE} rollout status deployment/${APP_NAME} --timeout=180s
                """
            }
        }

        stage('Smoke Test') {
            steps {
                sh """
                    kubectl -n ${K8S_NAMESPACE} get pods -l app=${APP_NAME}
                    kubectl -n ${K8S_NAMESPACE} get svc ${APP_NAME}
                    kubectl -n ${K8S_NAMESPACE} run smoke-test-${env.BUILD_NUMBER} \
                        --rm -i --restart=Never --image=curlimages/curl:8.10.1 -- \
                        curl -sf http://${APP_NAME}.${K8S_NAMESPACE}.svc.cluster.local:8080/api/health
                """
            }
        }

        stage('Update GitOps Deployment') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'github-credentials',
                                                   usernameVariable: 'GIT_USER',
                                                   passwordVariable: 'GIT_TOKEN')]) {
                    sh """
                        sed -i "s|image: .*devops-demo:.*|image: ${DOCKER_IMAGE}:${env.IMAGE_TAG}|" k8s/deployment.yaml
                        git config user.email "jenkins-ci@local"
                        git config user.name "jenkins-ci"
                        git add k8s/deployment.yaml
                        git commit -m "ci: update devops-demo image to ${env.IMAGE_TAG} [skip ci]" || echo "No changes to commit"
                        git push https://\$GIT_USER:\$GIT_TOKEN@\$(git config --get remote.origin.url | sed 's#https://##') HEAD:main
                    """
                }
                echo 'ArgoCD will detect this commit and reconcile the cluster automatically (see argocd/application.yaml).'
            }
        }

        stage('Verify Deployment') {
            steps {
                sh """
                    kubectl -n ${K8S_NAMESPACE} rollout status deployment/${APP_NAME} --timeout=120s
                    kubectl -n ${K8S_NAMESPACE} get pods -l app=${APP_NAME} -o wide
                """
            }
        }
    }

    post {
        success {
            echo "Pipeline succeeded: ${APP_NAME}:${env.IMAGE_TAG} is live in namespace ${K8S_NAMESPACE}."
        }
        failure {
            echo "Pipeline failed. Check the stage logs above. No broken image was left as 'latest' in the cluster beyond the rollout that already completed successfully."
        }
        always {
            sh 'docker system prune -f --filter "until=24h" || true'
        }
    }
}

// CI/CD pipeline for the Java Maven Calculator Web App.
//
// Stage order follows a typical company pipeline - cheap checks first, fail fast:
//   Checkout -> Validate & Lint -> Build -> Unit Test -> SonarQube Analysis -> Quality Gate
//   -> Package -> Integration Test -> Publish to Artifactory
//   -> Deploy to QA -> Performance Test (on QA) -> Approval -> Deploy to Production
//
// Jenkins needs (see README "2. CI/CD with Jenkins"):
//   - JDK 17+ and Maven on the agent (curl too, for the smoke tests)
//   - Plugins: Pipeline, Git, JUnit, Credentials Binding, SonarQube Scanner, Pipeline Stage View
//   - Credentials (Username with password): artifactory-creds, tomcat-creds
//   - Manage Jenkins -> System -> SonarQube servers: a server named "sonarqube"

pipeline {
    agent any

    parameters {
        booleanParam(name: 'RUN_SONAR', defaultValue: true, description: 'Run SonarQube analysis and Quality Gate')
    }

    environment {
        // ---- change these to your servers ----
        ARTIFACTORY_URL  = 'http://localhost:8082/artifactory'
        QA_TOMCAT        = 'http://localhost:8080'
        PROD_TOMCAT      = 'http://localhost:8080'
        // QA and Production can be the same Tomcat for a demo: the app is deployed under different paths
        QA_CONTEXT       = 'calculator-qa'
        PROD_CONTEXT     = 'calculator'
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        disableConcurrentBuilds()
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Validate & Lint') {
            steps {
                // validate: pom.xml is correct; checkstyle:check: code follows checkstyle.xml rules
                sh 'mvn -B validate checkstyle:check'
            }
        }

        stage('Build') {
            steps {
                sh 'mvn -B clean compile'
            }
        }

        stage('Unit Test') {
            steps {
                // also writes the JaCoCo coverage report used by SonarQube
                sh 'mvn -B test'
            }
            post {
                always {
                    junit 'target/surefire-reports/*.xml'
                }
            }
        }

        stage('SonarQube Analysis') {
            when { expression { params.RUN_SONAR } }
            steps {
                withSonarQubeEnv('sonarqube') {
                    sh 'mvn -B sonar:sonar'
                }
            }
        }

        stage('Quality Gate') {
            when { expression { params.RUN_SONAR } }
            steps {
                // needs a SonarQube webhook to http://<jenkins>/sonarqube-webhook/
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Package') {
            steps {
                sh 'mvn -B package -DskipTests'
            }
            post {
                success {
                    archiveArtifacts artifacts: 'target/calculator.war', fingerprint: true
                }
            }
        }

        stage('Integration Test') {
            steps {
                // starts Jetty on port 9999, runs *IT.java against it, stops Jetty
                sh 'mvn -B verify -DskipUTs'
            }
            post {
                always {
                    junit 'target/failsafe-reports/*.xml'
                }
            }
        }

        stage('Publish to Artifactory') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'artifactory-creds',
                        usernameVariable: 'ARTIFACTORY_USERNAME', passwordVariable: 'ARTIFACTORY_PASSWORD')]) {
                    sh 'mvn -B -s settings-artifactory.xml deploy -DskipTests -Dartifactory.url=$ARTIFACTORY_URL'
                }
            }
        }

        stage('Deploy to QA') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'tomcat-creds',
                        usernameVariable: 'TOMCAT_USERNAME', passwordVariable: 'TOMCAT_PASSWORD')]) {
                    sh 'mvn -B cargo:redeploy -Dtomcat.url=$QA_TOMCAT/manager/text -Dtomcat.path=$QA_CONTEXT'
                }
                // smoke test: the app answers after deployment
                sh 'curl -sf --retry 10 --retry-delay 3 --retry-all-errors $QA_TOMCAT/$QA_CONTEXT/api/calculator/ping'
            }
        }

        stage('Performance Test') {
            steps {
                // JMeter load test against the app running on QA; fails if any request fails
                sh '''
                    QA_HOST=$(echo $QA_TOMCAT | sed -E 's#https?://##; s#:.*##')
                    QA_PORT=$(echo $QA_TOMCAT | sed -E 's#https?://[^:]*:?##')
                    mvn -B verify -Pperformance -DskipTests \
                        -Dperf.host=$QA_HOST -Dperf.port=${QA_PORT:-80} -Dperf.context=$QA_CONTEXT
                '''
            }
            post {
                always {
                    archiveArtifacts artifacts: 'target/jmeter/reports/**', allowEmptyArchive: true
                }
            }
        }

        stage('Approval') {
            steps {
                timeout(time: 30, unit: 'MINUTES') {
                    input message: 'QA and performance tests passed. Deploy to Production?', ok: 'Deploy'
                }
            }
        }

        stage('Deploy to Production') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'tomcat-creds',
                        usernameVariable: 'TOMCAT_USERNAME', passwordVariable: 'TOMCAT_PASSWORD')]) {
                    sh 'mvn -B cargo:redeploy -Dtomcat.url=$PROD_TOMCAT/manager/text -Dtomcat.path=$PROD_CONTEXT'
                }
                sh 'curl -sf --retry 10 --retry-delay 3 --retry-all-errors $PROD_TOMCAT/$PROD_CONTEXT/api/calculator/ping'
            }
        }
    }

    post {
        success {
            echo "Deployed: ${env.PROD_TOMCAT}/${env.PROD_CONTEXT}/api/calculator/ping"
        }
        failure {
            echo 'Pipeline failed - check the red stage above.'
        }
    }
}

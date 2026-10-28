# A Java Maven Calculator Web App
A Java calculator REST API, built by Maven, CI/CD by Jenkins.

> Tested with: JDK 17 / 21 / 27, Maven 3.8.7+ (Ubuntu apt) and latest, Tomcat 10.1 (Ubuntu apt) and Tomcat 11,
> Jenkins 2.541, SonarQube Community 26.x, JFrog Artifactory OSS 7.x.
> The app uses Jakarta EE (`jakarta.*`, Jersey 3.1), so it needs **Tomcat 10.1 or newer** — it will not run on Tomcat 9 or older.

API (context path `/calculator`):
- `/calculator/api/calculator/ping`
- `/calculator/api/calculator/add?x=8&y=26`
- `/calculator/api/calculator/sub?x=12&y=8`
- `/calculator/api/calculator/mul?x=11&y=8`
- `/calculator/api/calculator/div?x=12&y=12`

## 1. The CI/CD pipeline

The `Jenkinsfile` runs these stages, in the same order as a typical company pipeline:
cheap checks first (fail fast), then build the artifact once, test it, store it, and promote it QA -> Production.

| # | Stage | Command | What it does | Fails when |
|---|-------|---------|--------------|------------|
| 1 | Checkout | `git clone ...` | Gets the code | - |
| 2 | Validate & Lint | `mvn -B validate checkstyle:check` | Checks pom.xml and code style (`checkstyle.xml`) | Any lint violation |
| 3 | Build | `mvn -B clean compile` | Compiles the code | Compile error |
| 4 | Unit Test | `mvn -B test` | Runs `*Test.java` + JaCoCo coverage | A unit test fails |
| 5 | SonarQube Analysis | `mvn -B sonar:sonar` | Sends code + coverage to SonarQube | Scanner error |
| 6 | Quality Gate | `waitForQualityGate` (Jenkins) | Waits for SonarQube's pass/fail | Quality Gate is red |
| 7 | Package | `mvn -B package -DskipTests` | Builds `target/calculator.war` | - |
| 8 | Integration Test | `mvn -B verify -DskipUTs` | Starts Jetty on 9999, runs `*IT.java` over HTTP | An integration test fails |
| 9 | Publish to Artifactory | `mvn -B -s settings-artifactory.xml deploy -DskipTests` | Uploads the WAR to JFrog Artifactory | Upload error |
| 10 | Deploy to QA | `mvn -B cargo:redeploy -Dtomcat.path=calculator-qa` + `curl` smoke test | Deploys to Tomcat at `/calculator-qa` | App not reachable |
| 11 | Performance Test | `mvn -B verify -Pperformance -DskipTests -Dperf.context=calculator-qa` | JMeter load test against QA | Any request fails |
| 12 | Approval | `input` (Jenkins) | A person clicks **Deploy** | Rejected / 30 min timeout |
| 13 | Deploy to Production | `mvn -B cargo:redeploy -Dtomcat.path=calculator` + `curl` smoke test | Deploys the same WAR to `/calculator` | App not reachable |

Why this order:
- **Lint, build, unit test, SonarQube** take seconds and catch most problems — run them first.
- **Package once**, then every later stage uses that same WAR (build once, deploy many).
- **Performance test needs a running app**, so it runs after *Deploy to QA*, never before.
- **Production** only gets a WAR that passed every stage and was approved by a person.

QA and Production can be two Tomcat servers, or one Tomcat with two paths (`/calculator-qa` and `/calculator`) for a demo.

## 2. Servers you need

| Server | What | Port | Suggested EC2 |
|--------|------|------|---------------|
| Jenkins | Jenkins + JDK + Maven (runs the pipeline) | 8080 | t3.medium |
| Tomcat | Tomcat 10.1 (QA + Production) | 8080 | t3.small |
| SonarQube | SonarQube Community (Docker) | 9000 | t3.medium (4 GB) |
| Artifactory | JFrog Artifactory OSS + PostgreSQL (Docker) | 8082 | t3.medium (4 GB) |

Jenkins and Tomcat both use port 8080, so put them on different servers. Open the ports in the security groups.

### 2.1 Jenkins server (Ubuntu)
```console
sudo apt update
sudo apt install openjdk-21-jdk maven git curl -y
java -version
mvn -v
```
Install Jenkins (https://www.jenkins.io/doc/book/installing/linux/), then install these plugins
(Manage Jenkins -> Plugins): **Pipeline, Git, JUnit, Credentials Binding, SonarQube Scanner, Pipeline Stage View**.

### 2.2 Tomcat server (Ubuntu)
```console
sudo apt update
sudo apt install openjdk-21-jdk -y
sudo apt install tomcat10 tomcat10-admin -y
sudo systemctl status tomcat10
```
Add users in `sudo vi /etc/tomcat10/tomcat-users.xml`, inside `<tomcat-users> ... </tomcat-users>`:
```xml
  <!-- for you, in the browser: http://<tomcat-ip>:8080/manager/html -->
  <role rolename="manager-gui"/>
  <user username="admin" password="<choose-a-password>" roles="manager-gui"/>
  <!-- for Jenkins / Maven deployments (text API: /manager/text) -->
  <role rolename="manager-script"/>
  <user username="deployer" password="<choose-a-password>" roles="manager-script"/>
```
```console
sudo systemctl restart tomcat10
```
Ubuntu's Tomcat Manager accepts remote connections by default. If you use Tomcat from tomcat.apache.org instead,
edit `webapps/manager/META-INF/context.xml` and change `allow="127.0.0.0/8,::1/128"` to the Jenkins server IP (CIDR, e.g. `172.31.5.10/32`).

### 2.3 SonarQube server (Docker)
```console
sudo sysctl -w vm.max_map_count=524288     # required by SonarQube's Elasticsearch on Linux
docker run -d --name sonarqube -p 9000:9000 sonarqube:community -Dsonar.validateWebhooks=false
```
- Open http://<sonar-ip>:9000, log in `admin` / `admin`, set a new password.
- **Token**: My Account -> Security -> Generate Token (type *Global Analysis Token*). Copy it.
- **Webhook** (needed by the Quality Gate stage): Administration -> Configuration -> Webhooks -> Create,
  URL `http://<jenkins-ip>:8080/sonarqube-webhook/`.

`-Dsonar.validateWebhooks=false` lets SonarQube call a Jenkins on a private IP (e.g. `172.31.x.x`); without it, SonarQube
rejects private webhook URLs and the Quality Gate stage waits until it times out. Alternatively, use Jenkins' public URL.

### 2.4 Artifactory server (Docker)
JFrog Artifactory OSS is free. Recent versions need PostgreSQL, so `artifactory/docker-compose.yml` starts both:
```console
cd artifactory
docker compose up -d
```
Wait 1-3 minutes, open http://<artifactory-ip>:8082, log in `admin` / `password`, set a new password.
Then create the Maven repositories (`libs-release-local`, `libs-snapshot-local`, `maven-remote`, `libs-release`, `libs-snapshot`):
- in the UI: Quick Setup / Create Repositories -> choose **Maven**, or
- from the terminal:
```console
ARTIFACTORY_USERNAME=admin ARTIFACTORY_PASSWORD=<password> ./create-maven-repos.sh http://<artifactory-ip>:8082
```

## 3. Configure Jenkins

### 3.1 Credentials
Manage Jenkins -> Credentials -> System -> Global credentials -> Add Credentials:

| ID | Kind | Value |
|----|------|-------|
| `artifactory-creds` | Username with password | Artifactory admin user / password |
| `tomcat-creds` | Username with password | `deployer` / its password (the `manager-script` user) |
| `sonar-token` | Secret text | the SonarQube token |

### 3.2 SonarQube server
Manage Jenkins -> System -> SonarQube servers -> Add SonarQube:
Name **`sonarqube`**, Server URL `http://<sonar-ip>:9000`, Server authentication token `sonar-token`.

### 3.3 Point the Jenkinsfile at your servers
Edit the `environment` block at the top of `Jenkinsfile`:
```groovy
ARTIFACTORY_URL  = 'http://<artifactory-ip>:8082/artifactory'
QA_TOMCAT        = 'http://<tomcat-ip>:8080'
PROD_TOMCAT      = 'http://<tomcat-ip>:8080'      // or a second Tomcat
```

### 3.4 Create the pipeline job
New Item -> name `calculator-cicd` -> **Pipeline** -> Pipeline section:
Definition **Pipeline script from SCM**, SCM **Git**, Repository URL = your repo, Branch `*/main`, Script Path `Jenkinsfile`.

Click **Build Now**. The first build adds the **Build with Parameters** option (`RUN_SONAR` lets you skip SonarQube).
The pipeline stops at **Approval** — open the build, click **Deploy** to release to Production.

Where to see results:
- Test results: build page -> **Tests** (unit + integration)
- WAR file: build page -> **Build Artifacts**; and in Artifactory -> `libs-snapshot-local/com/itdefined/javawebapp/`
- JMeter HTML report: Build Artifacts -> `target/jmeter/reports/`
- Code quality + coverage: SonarQube -> project `maven-calculator-app`
- App: `http://<tomcat-ip>:8080/calculator-qa/api/calculator/ping` (QA) and `/calculator/...` (Production)

## 4. Run the stages by hand (same commands as Jenkins)
Useful to show each stage step by step, or to debug a red stage.
```console
mvn -B validate checkstyle:check
mvn -B clean compile
mvn -B test
mvn -B sonar:sonar -Dsonar.host.url=http://<sonar-ip>:9000 -Dsonar.token=<token>
mvn -B package -DskipTests
mvn -B verify -DskipUTs

export ARTIFACTORY_USERNAME=admin ARTIFACTORY_PASSWORD=<password>
mvn -B -s settings-artifactory.xml deploy -DskipTests -Dartifactory.url=http://<artifactory-ip>:8082/artifactory

export TOMCAT_USERNAME=deployer TOMCAT_PASSWORD=<password>
mvn -B cargo:redeploy -Dtomcat.url=http://<tomcat-ip>:8080/manager/text -Dtomcat.path=calculator-qa
mvn -B verify -Pperformance -DskipTests -Dperf.host=<tomcat-ip> -Dperf.port=8080 -Dperf.context=calculator-qa
mvn -B cargo:redeploy -Dtomcat.url=http://<tomcat-ip>:8080/manager/text -Dtomcat.path=calculator
```
Flags used above:
- `-DskipTests` skips unit **and** integration tests; `-DskipUTs` skips only unit tests.
- `-Pperformance` turns on the JMeter tests (they are off in normal builds because they need a running app).

## 5. Other useful commands

### 5.1 Run the app on your machine (no Tomcat needed)
```console
mvn jetty:run
```
Open http://localhost:9999/calculator/api/calculator/ping. Press Control-C to stop.

### 5.2 Project site with reports (Javadoc, Checkstyle, PMD, JaCoCo coverage, test results)
```console
mvn test site
```
Open `target/site/index.html`.

### 5.3 JMeter GUI (to view or edit the test plan)
Install JMeter, start the GUI (`jmeter`), open `src/test/jmeter/CalculatorTestPlan.jmx`.
Use the GUI only to create/debug tests; the load test itself runs from Maven (stage 11).

## 6. Containerize the app

### 6.1 Build and run a Docker image
`Dockerfile` copies `target/calculator.war` into the latest Tomcat (so run `mvn package` first);
`Dockerfile_multistage` builds the WAR inside Docker too.
```console
mvn -B package -DskipTests
docker build -t calculator .
# or, without Maven on your machine:
docker build -t calculator -f Dockerfile_multistage .

docker run --rm -p 8181:8080 calculator
```
The WAR is deployed as ROOT, so open http://localhost:8181/api/calculator/ping. Press Control-C to stop.

### 6.2 Push the image to Docker Hub
```console
docker login -u <Your-Docker-ID>
docker tag calculator <Your-Docker-ID>/calculator
docker push <Your-Docker-ID>/calculator
```

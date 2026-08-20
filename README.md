# DevOps CI/CD Kubernetes Demo Project

A complete, runnable, end-to-end DevOps pipeline you can run entirely on a **Windows 11 laptop** with **Docker Desktop** — no AWS account required.

```
GitHub → Jenkins CI → Maven Build/Test → SonarQube → Docker → Kubernetes → ArgoCD (GitOps) → Prometheus + Grafana
```

---

## Table of Contents

1. [Architecture](#1-architecture)
2. [Project Structure](#2-project-structure)
3. [Prerequisites](#3-prerequisites)
4. [Windows 11 Step-by-Step Setup](#4-windows-11-step-by-step-setup)
5. [The Application](#5-the-application)
6. [Jenkins CI/CD Pipeline](#6-jenkins-cicd-pipeline)
7. [SonarQube](#7-sonarqube)
8. [Docker](#8-docker)
9. [Jenkins + Docker on Windows](#9-jenkins--docker-on-windows)
10. [Kubernetes](#10-kubernetes)
11. [Monitoring Stack](#11-monitoring-stack)
12. [Grafana Dashboard](#12-grafana-dashboard)
13. [Alerting](#13-alerting)
14. [ArgoCD (GitOps)](#14-argocd-gitops)
15. [Security](#15-security)
16. [Testing](#16-testing)
17. [Smoke Testing](#17-smoke-testing)
18. [Optional: AWS/EKS Advanced Deployment](#18-optional-awseks-advanced-deployment)
19. [Windows Troubleshooting](#19-windows-troubleshooting)
20. [Useful Commands Reference](#20-useful-commands-reference)
21. [How to Demonstrate This Project in an Interview](#21-how-to-demonstrate-this-project-in-an-interview)
22. [Resume Description](#22-resume-description)
23. [Interview Questions](#23-interview-questions)

---

## 1. Architecture

```
 Developer
    |
    v
 GitHub (source + GitOps manifests)
    |
    v
 Jenkins (CI)  ---------------------------------------------+
    |                                                        |
    v                                                        |
 Maven build -> JUnit tests -> JaCoCo coverage -> SonarQube  |
    |                                                        |
    v                                                        |
 Docker build -> Trivy security scan -> Push to registry     |
    |                                                        |
    v                                                        |
 Update k8s/deployment.yaml image tag -> git commit + push --+
    |
    v
 ArgoCD (GitOps controller, watches the Git repo)
    |
    v
 Kubernetes (Deployment, Service, ConfigMap, Secret)
    |
    v
 Application (Spring Boot, exposes /actuator/prometheus)
    |
    v
 Prometheus (scrapes app + kube-state-metrics + node-exporter)
    |
    v
 Grafana (dashboards) + Alertmanager (alerts)
```

**Why two deployment paths exist in this repo:** Jenkins deploys directly during the pipeline (`kubectl apply` / `kubectl set image`) **and** also commits the new image tag back to Git for ArgoCD to reconcile. This mirrors a real GitOps setup: Jenkins owns *build, test, and image creation*; ArgoCD owns *what's actually running in the cluster*, continuously reconciling it against Git. See [section 14](#14-argocd-gitops) for why this separation matters.

### Component roles

| Component | Role |
|---|---|
| **GitHub** | Source of truth for application code and Kubernetes manifests |
| **Jenkins** | Orchestrates build, test, quality gate, image build/scan/push |
| **Maven** | Compiles the Java app and runs the build lifecycle |
| **JUnit 5** | Unit test framework |
| **JaCoCo** | Code coverage measurement, feeds SonarQube |
| **SonarQube** | Static analysis, code smells, bugs, vulnerabilities, quality gate |
| **Docker** | Packages the app into a portable, reproducible container image |
| **Trivy** | Scans the built image for known CVEs before it's pushed |
| **Kubernetes** | Runs and self-heals the application containers |
| **ArgoCD** | Continuously syncs the cluster state to match Git (GitOps) |
| **Prometheus** | Scrapes and stores time-series metrics |
| **Grafana** | Visualizes metrics from Prometheus |
| **Alertmanager** | Routes and displays firing alerts from Prometheus rules |
| **kube-state-metrics** | Exposes Kubernetes object state (pod status, restarts) as metrics |
| **node-exporter** | Exposes host/node-level metrics (CPU, memory, disk, network) |


---

## 2. Project Structure

```
devops-kubernetes-project/
├── app/                          # Spring Boot application
│   ├── src/main/java/...         # Controllers, models, repositories, config, exception handling
│   ├── src/test/java/...         # JUnit 5 tests
│   ├── src/main/resources/application.yml
│   ├── pom.xml
│   ├── Dockerfile                # Multi-stage, non-root, health-checked
│   └── .dockerignore
│
├── k8s/                          # Kubernetes manifests for the application
│   ├── namespace.yaml
│   ├── deployment.yaml
│   ├── service.yaml               # ClusterIP + NodePort
│   ├── configmap.yaml
│   ├── secret.yaml                 # Template only — see security notes
│   └── ingress.yaml                # Optional, requires an ingress controller
│
├── monitoring/
│   ├── prometheus/
│   │   ├── prometheus.yml
│   │   └── alert-rules.yml
│   ├── grafana/
│   │   ├── provisioning/datasources/datasource.yml
│   │   ├── provisioning/dashboards/dashboard-provider.yml
│   │   └── dashboards/devops-demo-dashboard.json
│   ├── alertmanager/
│   │   └── alertmanager.yml
│   └── k8s/                       # Deploys the whole monitoring stack INTO Kubernetes
│       ├── 00-namespace.yaml
│       ├── 01-prometheus-rbac.yaml
│       ├── 02-prometheus-deployment.yaml
│       ├── 03-alertmanager-deployment.yaml
│       ├── 04-kube-state-metrics.yaml
│       ├── 05-node-exporter.yaml
│       └── 06-grafana-deployment.yaml
│
├── argocd/
│   ├── application.yaml
│   └── project.yaml               # Optional dedicated AppProject
│
├── docker/
│   ├── docker-compose.yml         # Jenkins + SonarQube + Postgres (CI infra only)
│   ├── jenkins.Dockerfile         # Jenkins + Docker CLI + kubectl + Maven
│   └── plugins.txt
│
├── scripts/
│   ├── setup-windows.ps1          # Environment check
│   ├── build.ps1                  # Local Maven + Docker build
│   ├── deploy.ps1                 # Deploys app + full monitoring stack to Kubernetes
│   ├── install-argocd.ps1         # Installs ArgoCD
│   └── cleanup.ps1                # Tears everything down
│
├── Jenkinsfile
├── sonar-project.properties
├── .env.example
├── .gitignore
└── README.md
```

**Why monitoring runs inside Kubernetes rather than docker-compose:** Kubernetes-level metrics (pod status, container CPU/memory, restart counts) come from `kube-state-metrics` and `cAdvisor`/kubelet — both of which require RBAC access to the Kubernetes API and only make sense running *inside* the cluster they're monitoring. Running a second, disconnected Prometheus in docker-compose would not be able to see any of that, so this project deploys the whole monitoring stack (Prometheus, Grafana, Alertmanager, kube-state-metrics, node-exporter) as Kubernetes workloads via `scripts/deploy.ps1`. `docker-compose.yml` is reserved for Jenkins + SonarQube, which are CI tooling that sits *outside* the cluster and orchestrates deployments into it.

---

## 3. Prerequisites

| Tool | Required? | Notes |
|---|---|---|
| Windows 11 | Yes | Build 22000+ recommended |
| Docker Desktop | Yes | Enables WSL2 backend + optional built-in Kubernetes |
| WSL2 | Yes | Required by Docker Desktop |
| Git for Windows | Yes | |
| kubectl | Yes | Can also come bundled via Docker Desktop |
| PowerShell | Yes | Windows 11 ships with PowerShell 5.1; PowerShell 7 also works |
| Java 17 | Optional | Only needed if you want to build/test the app outside Docker |
| Maven | Optional | Same as above — the Docker build compiles it for you either way |
| Minikube | Optional | Fallback if Docker Desktop Kubernetes gives you trouble |

You do **not** need an AWS account for the base project. AWS/EKS is covered as an optional advanced section only.


---

## 4. Windows 11 Step-by-Step Setup

Commands are explicitly marked **[PowerShell]** or **[WSL/Linux terminal]**. Do not mix them — run PowerShell commands in a normal PowerShell/Windows Terminal window, and WSL commands only if you've opened a WSL distro shell (most of this project only needs PowerShell).

### Step 1 — Install Docker Desktop
Download and install from https://www.docker.com/products/docker-desktop/, then restart Windows if prompted.

### Step 2 — Enable WSL2
**[PowerShell — run as Administrator]**
```powershell
wsl --install
wsl --set-default-version 2
```
Restart Windows after this completes.

### Step 3 — Install Git
Download from https://git-scm.com/download/win and install with default options.
**[PowerShell]**
```powershell
git --version
```

### Step 4 — Install kubectl
**[PowerShell]**
```powershell
curl.exe -LO "https://dl.k8s.io/release/v1.31.0/bin/windows/amd64/kubectl.exe"
Move-Item .\kubectl.exe "C:\Windows\System32\kubectl.exe"
kubectl version --client
```
(Skip this if you enable Kubernetes through Docker Desktop, which installs its own kubectl integration — either works.)

### Step 5 — Install Minikube (only if you choose not to use Docker Desktop Kubernetes)
**[PowerShell]**
```powershell
winget install minikube
minikube start --cpus=4 --memory=6144 --driver=docker
```

### Step 6 — Clone the repository
**[PowerShell]**
```powershell
git clone https://github.com/<your-username>/devops-kubernetes-project.git
cd devops-kubernetes-project
```

### Step 7 — Run the environment check
**[PowerShell]**
```powershell
.\scripts\setup-windows.ps1
```
Fix anything it flags before continuing.

### Step 8 — Enable Kubernetes in Docker Desktop (recommended path)
Docker Desktop → Settings (gear icon) → **Kubernetes** → check **Enable Kubernetes** → **Apply & Restart**. Wait for the green "Kubernetes running" indicator in the bottom-left status bar.

**[PowerShell]**
```powershell
kubectl config use-context docker-desktop
kubectl get nodes
```

> If Docker Desktop Kubernetes is unstable on your machine (some Windows/WSL2 combinations have trouble), use Minikube from Step 5 instead and run `kubectl config use-context minikube`. Everything else in this README works identically against either cluster.

### Step 9 — Copy the environment file
**[PowerShell]**
```powershell
Copy-Item .env.example .env
notepad .env
```
Fill in a Docker Hub username/token if you plan to actually push images; for a fully local run without pushing, you can leave the Docker Hub values as placeholders and skip the "Push Docker Image" pipeline stage (or point `DOCKER_IMAGE_NAME` at a local-only tag).

### Step 10 — Start Jenkins + SonarQube
**[PowerShell]**
```powershell
cd docker
docker compose up -d --build
docker compose ps
cd ..
```
First boot of SonarQube can take 1-2 minutes; `docker compose ps` should show it `healthy` before continuing.

### Step 11 — Configure Jenkins
Open http://localhost:8081. On first run, the container starts unlocked (see `docker/jenkins.Dockerfile`), so go straight to **Manage Jenkins → Plugins** and confirm the plugins from `docker/plugins.txt` show as installed. Then **Manage Jenkins → Create a new job → Pipeline**, point it at your Git repo, script path `Jenkinsfile`.

### Step 12 — Configure GitHub credentials in Jenkins
**Manage Jenkins → Credentials → System → Global credentials → Add Credentials**
- Kind: Username with password
- Username: your GitHub username
- Password: a GitHub Personal Access Token (repo scope) — generate at https://github.com/settings/tokens
- ID: `github-credentials`

### Step 13 — Configure Docker Hub credentials in Jenkins
Same screen, add another credential:
- Kind: Username with password
- Username: your Docker Hub username
- Password: a Docker Hub access token (Docker Hub → Account Settings → Security → New Access Token)
- ID: `dockerhub-credentials`

### Step 14 — Configure SonarQube
1. Open http://localhost:9000 (default login `admin` / `admin`, you'll be asked to change it).
2. **My Account → Security → Generate Token**, name it `jenkins`, copy the token.
3. In Jenkins: **Manage Jenkins → Credentials**, add a **Secret text** credential with ID `sonarqube-token` and the token as the value.
4. **Manage Jenkins → System → SonarQube servers** → Add: Name `LocalSonarQube`, Server URL `http://sonarqube:9000` (container-to-container name, since Jenkins and SonarQube share the `ci-network` Docker network), Server authentication token = the `sonarqube-token` credential.
5. In SonarQube, go to **Quality Gates** and confirm "Sonar way" (the default) is active — this is the gate `waitForQualityGate` in the Jenkinsfile checks against.

### Step 15 — Deploy the application + monitoring stack to Kubernetes
**[PowerShell]**
```powershell
.\scripts\build.ps1
.\scripts\deploy.ps1
```

### Step 16 — Install ArgoCD
**[PowerShell]**
```powershell
.\scripts\install-argocd.ps1
```
This prints the ArgoCD URL and admin password.

### Step 17 — Point ArgoCD at your fork
Edit `argocd/application.yaml`, replace `<your-username>` in `repoURL` with your actual GitHub username, commit and push, then:
**[PowerShell]**
```powershell
kubectl apply -f argocd/application.yaml
```

### Step 18 — Prometheus is already deployed
Covered by Step 15 (`scripts/deploy.ps1` deploys the entire monitoring stack, including Prometheus).

### Step 19 — Grafana is already deployed
Also covered by Step 15, with the Prometheus datasource and dashboard already provisioned automatically.

### Step 20 — Alertmanager is already deployed
Also covered by Step 15.

### Step 21 — Confirm the Grafana dashboard loaded
Open http://localhost:30030 (`admin` / `admin123`) → **Dashboards → DevOps Demo folder → "DevOps Demo - Application, JVM, Kubernetes & Infrastructure"**. It should already be there — no manual import needed.

### Step 22 — Run the Jenkins pipeline
In Jenkins, open the pipeline job you created in Step 11 and click **Build Now**.

### Step 23 — Verify the Kubernetes deployment
**[PowerShell]**
```powershell
kubectl -n devops-demo get pods
kubectl -n devops-demo rollout status deployment/devops-demo
```

### Step 24 — Open the application
**[PowerShell]**
```powershell
curl.exe http://localhost:30080/api/health
```
Or visit http://localhost:30080/api/users in a browser.

### Step 25 — Open Grafana
http://localhost:30030

### Step 26 — Open Prometheus
http://localhost:30090 → **Status → Targets** — all targets should show `UP`.

### Step 27 — Test monitoring
Generate a little traffic and watch the "Requests per Second" panel move:
**[PowerShell]**
```powershell
1..50 | ForEach-Object { curl.exe -s http://localhost:30080/api/users | Out-Null }
```

### Step 28 — Test alerting
Scale the deployment to 0 to trigger `ApplicationDown`:
**[PowerShell]**
```powershell
kubectl -n devops-demo scale deployment/devops-demo --replicas=0
```
Watch it fire at http://localhost:30093, then restore it:
```powershell
kubectl -n devops-demo scale deployment/devops-demo --replicas=2
```

### Step 29 — Make a code change, push, and verify automatic CI/CD
Edit something small (e.g. a message string in `HealthController.java`), then:
**[PowerShell]**
```powershell
git add .
git commit -m "test: trigger pipeline"
git push
```
Jenkins picks it up (poll or webhook, depending on your job configuration), runs the full pipeline, and pushes an updated `k8s/deployment.yaml` image tag back to Git.

### Step 30 — Verify ArgoCD sync and Grafana metrics update
**[PowerShell]**
```powershell
kubectl -n argocd get application devops-demo
```
Status should move to `Synced` / `Healthy` within the auto-sync interval (default ~3 minutes, or trigger manually with `argocd app sync devops-demo`). Back in Grafana, the "Pod Restart Count" and request-rate panels will reflect the rollout.


---

## 5. The Application

A Spring Boot 3 / Java 17 REST API (`app/`).

**Endpoints:**
| Method | Path | Description |
|---|---|---|
| GET | `/api/health` | Simple custom health payload |
| GET | `/api/users` | List all users |
| GET | `/api/users/{id}` | Get one user (404 if missing) |
| POST | `/api/users` | Create a user (validated: `name`, `email`) |
| DELETE | `/api/users/{id}` | Delete a user |
| GET | `/api/products` | List all products |
| GET | `/api/products/{id}` | Get one product (404 if missing) |
| GET | `/actuator/health` | Liveness/readiness aggregate health |
| GET | `/actuator/info` | Build/app info |
| GET | `/actuator/metrics` | Micrometer metric names |
| GET | `/actuator/prometheus` | Prometheus-formatted scrape endpoint |

Data is stored in-memory (thread-safe `ConcurrentHashMap`-backed repositories) so the project runs with zero external database dependency. Swapping in a real database later only means changing the two repository classes.

Run it standalone without Docker or Kubernetes:
**[PowerShell]**
```powershell
cd app
mvn spring-boot:run
```

---

## 6. Jenkins CI/CD Pipeline

The `Jenkinsfile` defines 12 stages:

1. **Checkout** — pulls source, computes an image tag from the build number + short Git SHA
2. **Build** — `mvn clean compile`
3. **Unit Tests** — `mvn test`, publishes JUnit results; pipeline stops here if tests fail
4. **Code Coverage** — JaCoCo report, published as an HTML artifact
5. **SonarQube Analysis** — `mvn sonar:sonar` against the configured SonarQube server
6. **Quality Gate** — blocks the pipeline if SonarQube's quality gate isn't passed
7. **Docker Build** — multi-stage build, tagged with both the build-specific tag and `latest`
8. **Docker Image Security Scan** — Trivy scans for HIGH/CRITICAL CVEs with an available fix
9. **Push Docker Image** — pushes to Docker Hub using the `dockerhub-credentials` Jenkins credential
10. **Deploy to Kubernetes** — applies manifests, updates the running image, waits for rollout
11. **Smoke Test** — runs a throwaway pod that curls `/api/health` inside the cluster
12. **Update GitOps Deployment** — commits the new image tag to `k8s/deployment.yaml` and pushes, so ArgoCD picks it up
13. **Verify Deployment** — final rollout status + pod listing

The pipeline **fails the build** (stops immediately) if: the Maven build fails, unit tests fail, the SonarQube quality gate fails, the Docker build fails, the security scan finds a fixable HIGH/CRITICAL CVE, the Kubernetes rollout fails, or the smoke test doesn't get an HTTP 200.

No secrets are hardcoded anywhere in the `Jenkinsfile` — everything sensitive is pulled via `withCredentials(...)` from Jenkins' credential store.

---

## 7. SonarQube

- **Start it:** `docker compose up -d` from `docker/` (bundled in the same compose file as Jenkins).
- **Access it:** http://localhost:9000, default login `admin`/`admin` (you'll be forced to change the password on first login).
- **Generate a token:** My Account → Security → Generate Token.
- **Add the token to Jenkins:** as a Secret text credential with ID `sonarqube-token` (see Step 14 above).
- **How Jenkins connects:** the `Jenkinsfile`'s `withSonarQubeEnv("LocalSonarQube")` block wraps the `mvn sonar:sonar` call, which reads the server URL and injects the auth token from the `LocalSonarQube` server definition configured under Manage Jenkins → System.
- **Quality gate:** the default "Sonar way" gate is used; `waitForQualityGate abortPipeline: true` in the Jenkinsfile fails the build if it's not green. Customize thresholds under **Quality Gates** in the SonarQube UI if you want stricter/looser rules.
- **Versions used:** SonarQube 10.6 Community Edition (current LTS-track release compatible with Java 17 projects) and PostgreSQL 16 as its backing store — deliberately newer than the older SonarQube versions often seen in older reference tutorials, which are no longer compatible with current Java tooling.

---

## 8. Docker

`app/Dockerfile` is a two-stage build:
1. **Build stage** (`maven:3.9.9-eclipse-temurin-17`) compiles the jar.
2. **Runtime stage** (`eclipse-temurin:17-jre-jammy`) — a JRE-only (not JDK) image, much smaller than the build image — copies in just the jar.

Design choices:
- Runs as a **non-root** user (`spring`), created explicitly in the Dockerfile.
- Exposes port `8080`.
- Has a container `HEALTHCHECK` hitting `/actuator/health` (in addition to the Kubernetes-level probes, useful for plain `docker run`/compose usage).
- Dependency layer is copied and resolved (`mvn dependency:go-offline`) before source code, so source-only changes don't invalidate the dependency cache layer.

`docker/docker-compose.yml` provides the **local CI infrastructure** (Jenkins + SonarQube + its Postgres database) — not the application itself, which is deployed to Kubernetes instead (see [section 2](#2-project-structure) for why).

---

## 9. Jenkins + Docker on Windows

Jenkins needs to run `docker build`/`docker push` during the pipeline. On Windows with Docker Desktop, the cleanest way to give a containerized Jenkins access to Docker **without** running Jenkins itself in `--privileged` Docker-in-Docker mode is to **mount the host's Docker socket** into the Jenkins container:

```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock
```

This is what `docker/docker-compose.yml` does. On Windows/WSL2, Docker Desktop exposes this same Unix socket path inside the WSL2 integration, so the bind mount works the same way it would on native Linux.

**The tradeoff, explained honestly:** any container that can reach the Docker socket can effectively control the *entire* Docker Desktop engine — including starting privileged containers — because it's talking directly to the same daemon your host uses. That's a meaningfully bigger blast radius than `--privileged` Docker-in-Docker, which at least sandboxes the nested daemon. For a personal local learning project this tradeoff is reasonable and it's the standard approach used by most local Jenkins-in-Docker tutorials; for a real shared environment, you'd instead use rootless Docker-in-Docker, a Kubernetes-native Jenkins agent pattern (`docker-workflow` + `kubernetes` plugin spinning up ephemeral build pods), or a remote build service.

`docker/jenkins.Dockerfile` also installs the Docker CLI, `kubectl`, and Maven directly into the Jenkins image, and mounts your Windows kubeconfig (`~/.kube`) read-only so Jenkins can run `kubectl apply` against the same cluster Docker Desktop manages.


---

## 10. Kubernetes

Manifests live in `k8s/`. Highlights of `deployment.yaml`:

- **2 replicas**, `RollingUpdate` strategy (`maxSurge: 1`, `maxUnavailable: 0` — zero-downtime rollouts)
- **Resource requests/limits**: `150m`/`500m` CPU, `256Mi`/`512Mi` memory
- **Startup probe**: gives the JVM up to 60 seconds to boot before liveness checks start counting failures
- **Liveness probe**: `/actuator/health/liveness` — restarts the container if it deadlocks
- **Readiness probe**: `/actuator/health/readiness` — pulls the pod out of Service load-balancing if it's not ready, without restarting it
- `securityContext.runAsNonRoot: true` — enforced at the pod level too, matching the Dockerfile
- Prometheus scrape annotations on the pod template, so the dynamic `kubernetes-pods` Prometheus job picks it up automatically

`service.yaml` defines both a `ClusterIP` Service (for in-cluster traffic and Ingress) and a `NodePort` Service on `30080` (for easy `localhost` access from Windows without extra networking setup).

`ingress.yaml` is provided but genuinely optional — Docker Desktop Kubernetes doesn't ship an ingress controller by default, so unless you install `ingress-nginx` yourself, use the NodePort Service or `kubectl port-forward` instead.

---

## 11. Monitoring Stack

The full stack — Prometheus, Grafana, Alertmanager, kube-state-metrics, and node-exporter — is deployed **inside** the Kubernetes cluster (`monitoring/k8s/`), in its own `monitoring` namespace, by `scripts/deploy.ps1`.

Prometheus (`monitoring/prometheus/prometheus.yml`) scrapes:
1. **The Spring Boot app** — both a static target (`devops-demo.devops-demo.svc.cluster.local:8080`) and dynamic pod discovery via `prometheus.io/scrape` annotations, covering: uptime (`up`), HTTP request count/rate, HTTP error rate, response time/latency (via `http_server_requests_seconds_*` histograms), JVM memory/CPU/threads (via Micrometer's JVM binder metrics).
2. **kube-state-metrics** — pod status, deployment replica counts, pod restart counts.
3. **node-exporter** — node/host CPU, memory, disk, network.
4. **cAdvisor** (via the kubelet's `/metrics/cadvisor` proxy, using the `prometheus` ServiceAccount's RBAC permissions) — per-container CPU and memory usage.

This project uses **plain Prometheus** (not the Prometheus Operator / CRD-based `ServiceMonitor`) to keep the local setup simple and dependency-free, per the "beginner-friendly" requirement — the static `prometheus.yml` config is fully equivalent for a single-app demo, and does not require installing the Operator's CRDs first. If you later adopt the Prometheus Operator (common in production clusters), you'd replace `02-prometheus-deployment.yaml`'s config-file approach with a `ServiceMonitor` resource matching the app's Service labels.

---

## 12. Grafana Dashboard

`monitoring/grafana/dashboards/devops-demo-dashboard.json` is auto-provisioned (`monitoring/grafana/provisioning/dashboards/dashboard-provider.yml` tells Grafana to load anything in that folder on startup — no manual "Import Dashboard" click needed) with four rows:

- **Application:** UP/DOWN, requests/sec, total requests, HTTP 4xx rate, HTTP 5xx rate, average response time, p95 latency
- **JVM:** heap memory (used vs. max), non-heap memory, process CPU usage, thread count (live + daemon), GC pause rate
- **Kubernetes:** desired pod count, running pods, failed pods, restart count per pod, container CPU per pod, container memory per pod
- **Infrastructure:** node CPU %, node memory %, disk usage %, network RX/TX

The Prometheus datasource (`monitoring/grafana/provisioning/datasources/datasource.yml`) is also auto-provisioned and set as default, pointing at `http://prometheus:9090` (the in-cluster Prometheus Service DNS name).

---

## 13. Alerting

`monitoring/prometheus/alert-rules.yml` defines:

| Alert | Condition |
|---|---|
| `ApplicationDown` | `up{job="devops-demo-app"} == 0` for 1 minute |
| `HighErrorRate` | >5% of requests are HTTP 5xx over 5 minutes |
| `HighLatency` | p95 latency > 1s for 2 minutes |
| `PodRestarting` | More than 3 restarts in 15 minutes |
| `PodNotReady` | A pod not Ready for 5+ minutes |
| `HighCPU` | Container CPU usage > 90% of its 500m limit for 5 minutes |
| `HighMemory` | Container memory > 90% of its 512Mi limit for 5 minutes |

`monitoring/alertmanager/alertmanager.yml` intentionally ships with a receiver that has **no external integration configured** — firing and resolved alerts are still fully visible at http://localhost:30093 (or wherever you expose the Alertmanager Service) without needing an SMTP server or Slack webhook for the local demo.

**Adding real notifications later:** add a `slack_configs` or `email_configs` block to the `default-local` receiver — both are shown, commented out, directly in `alertmanager.yml` as a starting template. For Slack you'd need an [Incoming Webhook URL](https://api.slack.com/messaging/webhooks); for email, SMTP host/credentials (store the password in a Kubernetes Secret, not inline in the ConfigMap, for anything beyond a throwaway demo).

---

## 14. ArgoCD (GitOps)

`argocd/application.yaml` defines an ArgoCD `Application` pointed at this repo's `k8s/` folder, with:
```yaml
syncPolicy:
  automated:
    prune: true      # remove cluster resources deleted from Git
    selfHeal: true    # revert manual kubectl edits back to match Git
```

**Why ArgoCD instead of Jenkins deploying everything directly:**

- **Separation of concerns.** Jenkins' job is to *produce* a validated, tested, scanned artifact. ArgoCD's job is to *continuously reconcile* what's running against a Git-declared desired state. Mixing both into one imperative pipeline script means Jenkins has to also handle drift detection, rollback, and "what if someone kubectl-edited the cluster by hand" — none of which a linear CI pipeline is well-suited for.
- **Self-healing.** If someone manually changes something in the cluster (e.g. `kubectl scale` in a panic at 2am, or a bad `kubectl edit`), ArgoCD notices the drift from Git and reverts it automatically. A one-shot Jenkins deploy stage has no ongoing awareness of the cluster after the pipeline finishes.
- **Auditability.** Every deployed change has a corresponding Git commit (the "Update GitOps Deployment" Jenkinsfile stage), so "what's running in prod" is always answerable by "what's the latest commit in `k8s/`" — a core GitOps principle.
- **Credential blast radius.** Jenkins doesn't need long-lived, broad `kubectl` credentials for continuous cluster access; it only needs push access to Git. ArgoCD, running inside the cluster with its own scoped RBAC, is what actually talks to the Kubernetes API on an ongoing basis.
- **Decoupling deploy cadence from build cadence.** ArgoCD can reconcile independently of whether Jenkins is even running, and can manage multiple environments/clusters from the same Git source without Jenkins needing direct network access to each one.

This project's Jenkinsfile deliberately does *both* (a direct `kubectl` deploy stage AND a GitOps commit) so you can see and demo both mechanisms — in a real production setup you'd typically drop the direct `kubectl apply` deploy stage entirely and let ArgoCD be the only thing that touches the cluster.


---

## 15. Security

No secrets are hardcoded anywhere in this repo. Specifically:

- **Jenkins** reads GitHub, Docker Hub, and SonarQube credentials from the Jenkins Credentials store (`withCredentials`), never from plaintext in the `Jenkinsfile`.
- **Kubernetes** secrets live in `k8s/secret.yaml`, which ships as a clearly-marked **template** with a placeholder value — real values should be created imperatively (`kubectl create secret generic ... --from-literal=...`) and never committed. See the comment block at the top of that file.
- **`.env.example`** documents every environment variable this project uses, with no real values. Copy it to `.env` (git-ignored) and fill in real values locally.
- **`.gitignore`** excludes `.env`, build output, and other local-only files from being committed.
- **Grafana's admin password** ships as a Kubernetes Secret (`monitoring/k8s/06-grafana-deployment.yaml`) with an obvious placeholder (`admin123`) clearly commented as "change before treating this as anything other than a throwaway local demo."

---

## 16. Testing

`app/src/test/java/com/devops/demo/controller/` contains JUnit 5 + Spring `MockMvc` tests:

- `UserControllerTest` — health endpoint, list users, get by ID, create (201), validation failure (400), 404 on missing user
- `ProductControllerTest` — list products, get by ID, 404 on missing product
- `ActuatorEndpointTest` — `/actuator/health` and `/actuator/prometheus` respond successfully

Run locally: `mvn test` (from `app/`). The Jenkinsfile's **Unit Tests** stage runs this automatically on every pipeline execution and publishes JUnit XML results; the **Code Coverage** stage runs JaCoCo and publishes an HTML report as a build artifact.

---

## 17. Smoke Testing

After the Kubernetes deploy stage, the Jenkinsfile's **Smoke Test** stage:
1. Confirms the deployment rollout completed (`kubectl rollout status`, already awaited in the previous stage)
2. Lists pods and the Service
3. Spins up a throwaway `curlimages/curl` pod inside the cluster and sends a real HTTP request to `http://devops-demo.devops-demo.svc.cluster.local:8080/api/health`
4. Fails the build (non-zero exit from `curl -f`) if the response isn't HTTP 200

This catches problems a `rollout status` success alone can miss — e.g. the pod is "Running" and "Ready" per its probes, but the Service selector or networking is misconfigured so real traffic can't reach it.

---

## 18. Optional: AWS/EKS Advanced Deployment

Everything above runs entirely locally — AWS is not required. If you want to extend this to a real cloud cluster later:

1. Provision an EKS cluster (via `eksctl` or Terraform).
2. Push images to Amazon ECR instead of Docker Hub (swap the `dockerhub-credentials` step for an ECR login using an IAM role or access keys stored as Jenkins credentials — never hardcoded).
3. Point `kubectl config` at the EKS cluster (`aws eks update-kubeconfig`).
4. Everything else — the Jenkinsfile stages, Kubernetes manifests, ArgoCD Application, and monitoring stack — works unchanged, since none of it is Docker-Desktop-specific. You would typically switch the NodePort Services to a `LoadBalancer` type (backed by an AWS ELB) or a proper Ingress with an AWS Load Balancer Controller.
5. Consider the AWS-managed Prometheus/Grafana (Amazon Managed Service for Prometheus / Grafana) as an alternative to self-hosting the monitoring stack, though the self-hosted version in this repo works fine on EKS too.

This is intentionally left as a pointer rather than a fully built-out Terraform module — building and testing real AWS infrastructure is outside the scope of what can be verified in a local, zero-cost demo project.


---

## 19. Windows Troubleshooting

Each entry: **Cause → Command to diagnose → Solution**

**Docker Desktop not running**
- Cause: Docker Desktop isn't started, or crashed.
- Diagnose: `docker info` (fails with a connection error if not running).
- Solution: Start Docker Desktop from the Start menu, wait for the whale icon in the system tray to stop animating, then retry.

**WSL2 errors**
- Cause: WSL2 not installed, outdated, or the default distro is broken.
- Diagnose: `wsl --status` **[PowerShell]**
- Solution: `wsl --update` then `wsl --shutdown`, restart Docker Desktop. If it's still broken, `wsl --install` again (as Administrator).

**kubectl not found**
- Cause: kubectl isn't on your `PATH`.
- Diagnose: `kubectl version --client` returns "not recognized".
- Solution: Re-run Step 4 in [section 4](#4-windows-11-step-by-step-setup), or enable Docker Desktop's Kubernetes integration, which adds its own `kubectl`.

**minikube not starting**
- Cause: Insufficient resources allocated, or Hyper-V/WSL2 driver conflict.
- Diagnose: `minikube start --alsologtostderr -v=3`
- Solution: Increase Docker Desktop's resource limits (Settings → Resources), or explicitly pass `--driver=docker`: `minikube start --driver=docker --cpus=4 --memory=6144`.

**Kubernetes not enabled**
- Cause: The Docker Desktop Kubernetes toggle was never switched on, or is still starting.
- Diagnose: `kubectl cluster-info`
- Solution: Docker Desktop → Settings → Kubernetes → Enable Kubernetes → Apply & Restart. This can take several minutes on first enable.

**Jenkins cannot access Docker**
- Cause: The Docker socket isn't mounted, or the `jenkins` user isn't in the `docker` group inside the container.
- Diagnose: `docker compose exec jenkins docker ps`
- Solution: Confirm `docker/docker-compose.yml` still has the `/var/run/docker.sock:/var/run/docker.sock` volume mount, then `docker compose up -d --build` to rebuild with the group membership fix from `jenkins.Dockerfile`.

**Jenkins cannot connect to GitHub**
- Cause: Missing/incorrect PAT, or the token's scopes don't include `repo`.
- Diagnose: Run the pipeline and inspect the "Checkout" or "Update GitOps Deployment" stage log for a 401/403.
- Solution: Regenerate a GitHub PAT with `repo` scope, update the `github-credentials` entry in Jenkins.

**SonarQube not accessible**
- Cause: SonarQube is still booting (Elasticsearch startup can take a minute), or the container is unhealthy.
- Diagnose: `docker compose logs sonarqube --tail=50`
- Solution: Wait for `docker compose ps` to show `healthy`. On WSL2, SonarQube's embedded Elasticsearch may need `vm.max_map_count` raised: run `wsl -d docker-desktop sysctl -w vm.max_map_count=262144` **[PowerShell]**, or add it permanently via a `.wslconfig`.

**Docker image push failure**
- Cause: Not logged in, or invalid/expired Docker Hub token.
- Diagnose: `docker login` manually with the same credentials.
- Solution: Regenerate the Docker Hub access token, update the `dockerhub-credentials` entry in Jenkins.

**ImagePullBackOff**
- Cause: Kubernetes can't pull the image — wrong tag, private repo without imagePullSecrets, or you built the image locally but forgot `imagePullPolicy: IfNotPresent`/`Never`.
- Diagnose: `kubectl -n devops-demo describe pod <pod-name>` (look at the Events section)
- Solution: For a purely local image (never pushed), confirm `deployment.yaml`'s `imagePullPolicy` is `IfNotPresent` (it is, by default in this repo) and that the image was built with the exact same tag the Deployment references, in the same Docker daemon Kubernetes uses (Docker Desktop Kubernetes shares Docker Desktop's daemon, so this "just works" — Minikube needs `minikube image load <image>` or `eval $(minikube docker-env)` before building).

**CrashLoopBackOff**
- Cause: The app is failing to start — check for a port conflict, missing config, or an uncaught startup exception.
- Diagnose: `kubectl -n devops-demo logs <pod-name> --previous`
- Solution: Read the stack trace; common causes are a missing/misspelled ConfigMap key or the JVM being OOM-killed (raise the memory limit in `deployment.yaml`).

**Pending pods**
- Cause: Insufficient cluster CPU/memory to satisfy the pod's resource requests.
- Diagnose: `kubectl -n devops-demo describe pod <pod-name>` (Events will say "Insufficient cpu/memory")
- Solution: Increase Docker Desktop's allocated resources (Settings → Resources → Advanced), or lower the `requests` values in `deployment.yaml`.

**Kubernetes service not accessible**
- Cause: Wrong port, selector label mismatch, or NodePort not reachable from the Windows host.
- Diagnose: `kubectl -n devops-demo get endpoints devops-demo` (empty means the Service selector isn't matching any pod)
- Solution: Confirm the Deployment's pod template label (`app: devops-demo`) matches the Service's `selector`. If endpoints are populated but you still can't reach `localhost:30080`, try `kubectl port-forward svc/devops-demo -n devops-demo 8080:8080` as a fallback.

**ArgoCD not syncing**
- Cause: `repoURL` in `argocd/application.yaml` still has the `<your-username>` placeholder, or the repo/branch doesn't exist.
- Diagnose: `kubectl -n argocd get application devops-demo -o yaml` (look at `status.conditions`)
- Solution: Fix the `repoURL`/`targetRevision`, re-apply, and check `kubectl -n argocd logs deployment/argocd-repo-server`.

**Prometheus target DOWN**
- Cause: The target pod isn't running, or a network policy/RBAC issue.
- Diagnose: Prometheus UI → Status → Targets, check the error message next to the red target.
- Solution: For the app target, confirm `kubectl -n devops-demo get pods` shows Running pods. For `kubernetes-cadvisor`, confirm the `prometheus` ServiceAccount's ClusterRole (`monitoring/k8s/01-prometheus-rbac.yaml`) was applied.

**Grafana showing no data**
- Cause: Datasource misconfigured, or Prometheus itself has no data yet.
- Diagnose: Grafana → Connections → Data sources → Prometheus → "Test" button.
- Solution: Confirm the `grafana-datasources` ConfigMap was created (re-run `scripts/deploy.ps1`), and confirm Prometheus itself has data by querying `up` directly in the Prometheus UI first.

**Application metrics missing**
- Cause: `/actuator/prometheus` isn't reachable, or the Prometheus scrape job's target address is wrong.
- Diagnose: `kubectl -n devops-demo exec <pod> -- curl -s localhost:8080/actuator/prometheus | head`
- Solution: Confirm `management.endpoints.web.exposure.include` in `application.yml` includes `prometheus`, and that the pod annotations (`prometheus.io/scrape: "true"`) are present.

**Port conflicts**
- Cause: Something else on your machine is already using 8080, 9000, 9090, 3000, etc.
- Diagnose: **[PowerShell]** `Get-NetTCPConnection -LocalPort 8080 -ErrorAction SilentlyContinue`
- Solution: Stop the conflicting process, or change the `hostPort`/`nodePort` in the relevant compose/Kubernetes file (this repo already offsets Jenkins to `8081` specifically to avoid clashing with the app's `8080`).

**Windows firewall issues**
- Cause: Windows Defender Firewall blocking inbound connections to a NodePort or Docker-exposed port.
- Diagnose: Try `curl.exe` from the same machine (localhost) — if that also fails, it's not the firewall; if only remote-machine access fails, it likely is.
- Solution: Add an inbound rule for the specific port in Windows Defender Firewall, or temporarily allow it for the Private network profile only.


---

## 20. Useful Commands Reference

**Docker**
```powershell
docker ps
docker images
docker logs <container>
docker compose up -d
docker compose down
```

**Kubernetes**
```powershell
kubectl get nodes
kubectl get pods -n devops-demo
kubectl get svc -n devops-demo
kubectl get deployments -n devops-demo
kubectl describe pod <pod-name> -n devops-demo
kubectl logs <pod-name> -n devops-demo
kubectl rollout status deployment/devops-demo -n devops-demo
kubectl rollout restart deployment/devops-demo -n devops-demo
```

**ArgoCD** (CLI: `winget install argoproj.argocd-cli` or download from the ArgoCD GitHub releases)
```powershell
argocd login localhost:30443 --username admin
argocd app list
argocd app get devops-demo
argocd app sync devops-demo
argocd app history devops-demo
```

**Prometheus**
- Check targets: http://localhost:30090/targets
- Query metrics: http://localhost:30090/graph → enter a PromQL expression, e.g. `up{job="devops-demo-app"}`
- Check alerts: http://localhost:30090/alerts

**Grafana**
- Access dashboard: http://localhost:30030 → Dashboards → DevOps Demo folder
- Check datasource: Connections → Data sources → Prometheus → Test
- Import a dashboard manually (if you ever need to, beyond the auto-provisioned one): Dashboards → New → Import → paste a dashboard JSON or ID

---

## 21. How to Demonstrate This Project in an Interview

A tight 5-minute walkthrough:

1. Show the GitHub repository — architecture, folder structure.
2. Make a tiny code change (e.g. tweak a response message).
3. Push it to `main`.
4. Jenkins detects the change (poll/webhook) and starts a build.
5. Jenkins builds the application (Maven compile).
6. Unit tests execute and results are visible in the Jenkins UI.
7. SonarQube analyzes the code and reports the quality gate result.
8. Docker image is built (point out the multi-stage, non-root Dockerfile).
9. The image is pushed to Docker Hub.
10. ArgoCD detects the updated `k8s/deployment.yaml` commit.
11. Kubernetes rolls out the new version with zero downtime (show `kubectl rollout status` mid-flight).
12. Prometheus is already scraping the new pods (point out the scrape annotations).
13. Grafana displays live metrics for the new version.
14. Generate a burst of traffic against the app.
15. Show the request rate/latency panels react in real time.
16. Trigger a deliberate failure (`kubectl scale --replicas=0`).
17. Show the `ApplicationDown` alert fire in Alertmanager.
18. Restore the application (`kubectl scale --replicas=2`).
19. Show Kubernetes self-healing — new pods come up automatically, readiness probes gate traffic until they're actually ready, and the alert resolves.

---

## 22. Resume Description

### Project Title
**Cloud-Native CI/CD Pipeline with Kubernetes, GitOps, and Full-Stack Observability**

### Resume Bullet Points
- Designed and implemented an end-to-end CI/CD pipeline (Jenkins → Maven → SonarQube → Docker → Kubernetes → ArgoCD) with automated testing, static code analysis, container vulnerability scanning, and GitOps-driven deployment achieving zero-downtime rolling updates.
- Deployed a self-healing Kubernetes environment with liveness/readiness/startup probes, resource-based autoscaling limits, and RBAC-secured monitoring (Prometheus, Grafana, Alertmanager, kube-state-metrics) covering application, JVM, and infrastructure-level metrics with automated alerting.
- Built a production-style Spring Boot REST API instrumented with Micrometer/Prometheus metrics, backed by a fully automated Jenkins pipeline that enforces a SonarQube quality gate and runs live in-cluster smoke tests before promoting any build.

### Technologies Used
Java 17, Spring Boot 3, Maven, JUnit 5, JaCoCo, Jenkins, SonarQube, Docker, Trivy, Kubernetes, ArgoCD (GitOps), Prometheus, Grafana, Alertmanager, kube-state-metrics, node-exporter, PowerShell.

### Architecture Explanation
See [section 1](#1-architecture) above — a full diagram and per-component role breakdown.


---

## 23. Interview Questions

**1. What is the difference between CI and CD?**
CI (Continuous Integration) is about automatically building and testing every code change so integration problems surface early. CD extends that in one of two ways: Continuous Delivery (every change is automatically prepared into a releasable, deployable artifact, with a manual approval to actually release) or Continuous Deployment (every change that passes the pipeline is automatically deployed to production with no manual gate). This project implements Continuous Deployment — a passing pipeline run deploys automatically.

**2. What does Jenkins do in this pipeline?**
Orchestrates the build lifecycle: checkout, compile, test, static analysis via SonarQube, Docker image build/scan/push, Kubernetes deployment, smoke testing, and committing the new image reference back to the GitOps repo.

**3. Why use a declarative Jenkinsfile instead of configuring jobs through the UI?**
It's version-controlled alongside the code it builds, reviewable via pull requests, reproducible across Jenkins instances, and self-documenting — anyone can read exactly what the pipeline does without clicking through Jenkins UI screens.

**4. What is a Docker multi-stage build and why use one here?**
It uses multiple `FROM` stages in one Dockerfile so build-time tooling (the full Maven + JDK image) doesn't end up in the final image. Only the compiled jar is copied into a lightweight JRE-only runtime image, dramatically shrinking image size and reducing the attack surface.

**5. Why run the container as a non-root user?**
If the application process or a dependency is compromised, running as non-root limits what the attacker can do inside the container (can't modify most of the filesystem, can't bind privileged ports, etc.) — a core container-hardening practice.

**6. What is a Kubernetes Pod?**
The smallest deployable unit in Kubernetes — one or more tightly coupled containers that share network namespace and storage volumes, always scheduled together on the same node.

**7. What is a Kubernetes Deployment?**
A controller that manages a set of identical Pods (via a ReplicaSet), handling rolling updates, rollbacks, and self-healing (replacing Pods that die or fail health checks) to maintain the desired replica count.

**8. What is a Kubernetes Service?**
A stable network endpoint (virtual IP + DNS name) that load-balances traffic across a dynamic set of Pods matched by label selectors, so clients don't need to track individual Pod IPs that change as Pods are replaced.

**9. What's the difference between ClusterIP, NodePort, and LoadBalancer Services?**
ClusterIP is only reachable from inside the cluster; NodePort additionally opens a static port on every node so it's reachable from outside the cluster (used here for local Windows access); LoadBalancer provisions an external cloud load balancer (relevant on AWS/EKS, not typically available on a local Docker Desktop cluster).

**10. What is Ingress and why wasn't it required for this demo?**
Ingress is an HTTP(S) layer-7 routing resource (host/path-based rules, TLS termination) that needs an Ingress Controller installed to actually do anything. Docker Desktop Kubernetes doesn't ship one by default, so this project defaults to a NodePort Service and documents Ingress as an optional add-on.

**11. What is ArgoCD and what problem does it solve?**
A GitOps continuous-delivery controller for Kubernetes that continuously compares the live cluster state to a Git repository's declared state and reconciles any difference — either automatically (`selfHeal`) or via manual sync.

**12. What is GitOps?**
An operating model where Git is the single source of truth for infrastructure/deployment state, and an automated agent (here, ArgoCD) — not a human running `kubectl` by hand — is responsible for making the live environment match Git.

**13. Why use ArgoCD instead of having Jenkins run `kubectl apply` directly?**
See [section 14](#14-argocd-gitops) in full — in short: separation of concerns (build vs. reconcile), self-healing against manual drift, a full audit trail via Git history, and a smaller credential footprint for Jenkins.

**14. What does "self-healing" mean in this context?**
Two layers: Kubernetes itself restarts/reschedules failed Pods based on liveness probes, and ArgoCD additionally reverts any manual, out-of-band change to cluster resources back to what's declared in Git.

**15. What is SonarQube used for?**
Static code analysis: detecting bugs, code smells, security vulnerabilities, and duplicated code, plus tracking test coverage over time and enforcing a configurable Quality Gate that can block a pipeline from proceeding.

**16. What is a SonarQube Quality Gate?**
A set of pass/fail conditions (e.g. "no new bugs," "coverage on new code ≥ 80%," "no new blocker vulnerabilities") evaluated after each analysis; `waitForQualityGate abortPipeline: true` in this project's Jenkinsfile fails the build if the gate doesn't pass.

**17. What is Prometheus and how does it collect data?**
A pull-based time-series monitoring system: it scrapes metrics from HTTP endpoints (like this app's `/actuator/prometheus`) at a configured interval and stores them, rather than requiring applications to push metrics to it.

**18. What's the difference between monitoring and logging?**
Monitoring (Prometheus/Grafana here) answers "is the system healthy, and by how much" via aggregated numeric time-series (request rates, latencies, resource usage) — good for trends and alerting. Logging captures discrete, detailed event records (a specific request's stack trace, an error message) — good for root-causing a specific incident after an alert points you at *when* something went wrong. This project implements monitoring; a real production setup would pair it with a log aggregation stack (e.g. Loki, ELK) for the logging half.

**19. What is Grafana's role versus Prometheus's role?**
Prometheus collects and stores the metrics; Grafana is purely a visualization/dashboarding layer that queries Prometheus (or other datasources) with PromQL to render graphs, tables, and alerts panels.

**20. What is Alertmanager and how does it relate to Prometheus?**
Prometheus evaluates alerting rules (PromQL expressions crossing a threshold) and, when one fires, sends it to Alertmanager, which handles deduplication, grouping, silencing, inhibition, and routing to notification channels (Slack, email, PagerDuty, etc. — none configured in this local demo, by design).

**21. What is kube-state-metrics and why is it needed separately from Prometheus?**
Prometheus itself doesn't understand Kubernetes object state; kube-state-metrics is a separate service that watches the Kubernetes API and exposes object state (pod phase, restart counts, deployment replica status) as Prometheus-scrapeable metrics.

**22. What's the difference between a Docker registry and a Docker image?**
An image is the immutable, layered filesystem + metadata artifact produced by `docker build`. A registry (Docker Hub in this project) is a server that stores and serves versioned images by tag, so other machines (like a Kubernetes cluster) can pull them without needing the original build environment.

**23. What are Kubernetes liveness, readiness, and startup probes?**
Liveness: "is this container still working — restart it if not." Readiness: "is this container ready to receive traffic right now — remove it from the Service's endpoints if not, without restarting it." Startup: "give slow-starting apps extra time before liveness checks start counting failures," preventing a slow JVM boot from being mistaken for a hung process.

**24. What is a rolling deployment and how does this project configure it?**
An update strategy that replaces old Pods with new ones incrementally rather than all at once, avoiding downtime. This project's Deployment uses `maxSurge: 1, maxUnavailable: 0` — it always creates one extra new Pod before removing an old one, guaranteeing full capacity throughout the rollout.

**25. Why does the pipeline scan the Docker image with Trivy before pushing it?**
To catch known, fixable vulnerabilities (HIGH/CRITICAL CVEs) in OS packages or dependencies baked into the image *before* it's distributed and deployed, shifting security left rather than discovering issues in production.


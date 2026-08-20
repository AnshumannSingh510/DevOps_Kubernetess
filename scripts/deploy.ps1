<#
.SYNOPSIS
  Deploys the devops-demo application and the monitoring stack
  (Prometheus, Grafana, Alertmanager, kube-state-metrics, node-exporter)
  into the current kubectl context (Docker Desktop Kubernetes or Minikube).

.EXAMPLE
  .\scripts\deploy.ps1
#>

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

function Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

Step "Checking cluster connectivity"
kubectl cluster-info | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "kubectl cannot reach a cluster. Enable Kubernetes in Docker Desktop or start Minikube first."
}

Step "Deploying application (namespace: devops-demo)"
kubectl apply -f "$root\k8s\namespace.yaml"
kubectl apply -f "$root\k8s\configmap.yaml"
kubectl apply -f "$root\k8s\secret.yaml"
kubectl apply -f "$root\k8s\deployment.yaml"
kubectl apply -f "$root\k8s\service.yaml"

Step "Waiting for application rollout"
kubectl -n devops-demo rollout status deployment/devops-demo --timeout=180s

Step "Deploying monitoring stack (namespace: monitoring)"
kubectl apply -f "$root\monitoring\k8s\00-namespace.yaml"
kubectl apply -f "$root\monitoring\k8s\01-prometheus-rbac.yaml"

Write-Host "Creating/updating ConfigMaps from monitoring config files..."
kubectl -n monitoring create configmap prometheus-config `
    --from-file="$root\monitoring\prometheus\prometheus.yml" `
    --dry-run=client -o yaml | kubectl apply -f -

kubectl -n monitoring create configmap prometheus-rules `
    --from-file="$root\monitoring\prometheus\alert-rules.yml" `
    --dry-run=client -o yaml | kubectl apply -f -

kubectl -n monitoring create configmap alertmanager-config `
    --from-file="$root\monitoring\alertmanager\alertmanager.yml" `
    --dry-run=client -o yaml | kubectl apply -f -

kubectl -n monitoring create configmap grafana-datasources `
    --from-file="$root\monitoring\grafana\provisioning\datasources\datasource.yml" `
    --dry-run=client -o yaml | kubectl apply -f -

kubectl -n monitoring create configmap grafana-dashboard-provider `
    --from-file="$root\monitoring\grafana\provisioning\dashboards\dashboard-provider.yml" `
    --dry-run=client -o yaml | kubectl apply -f -

kubectl -n monitoring create configmap grafana-dashboards `
    --from-file="$root\monitoring\grafana\dashboards\devops-demo-dashboard.json" `
    --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f "$root\monitoring\k8s\02-prometheus-deployment.yaml"
kubectl apply -f "$root\monitoring\k8s\03-alertmanager-deployment.yaml"
kubectl apply -f "$root\monitoring\k8s\04-kube-state-metrics.yaml"
kubectl apply -f "$root\monitoring\k8s\05-node-exporter.yaml"
kubectl apply -f "$root\monitoring\k8s\06-grafana-deployment.yaml"

Step "Waiting for monitoring rollout"
kubectl -n monitoring rollout status deployment/prometheus --timeout=180s
kubectl -n monitoring rollout status deployment/alertmanager --timeout=120s
kubectl -n monitoring rollout status deployment/kube-state-metrics --timeout=120s
kubectl -n monitoring rollout status deployment/grafana --timeout=120s

Step "Deployment complete"
Write-Host "Application:  http://localhost:30080/api/health"
Write-Host "Prometheus:   http://localhost:30090"
Write-Host "Alertmanager: http://localhost:30093"
Write-Host "Grafana:      http://localhost:30030   (user: admin / password: admin123, see monitoring/k8s/06-grafana-deployment.yaml)"
Write-Host ""
Write-Host "If NodePorts are not reachable, use kubectl port-forward instead (see README section 'Useful Commands')."

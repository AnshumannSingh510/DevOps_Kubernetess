<#
.SYNOPSIS
  Installs ArgoCD into the current kubectl context and prints the
  initial admin password + how to reach the UI.

.EXAMPLE
  .\scripts\install-argocd.ps1
#>

$ErrorActionPreference = "Stop"

Write-Host "=== Installing ArgoCD ===" -ForegroundColor Cyan

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.13.2/manifests/install.yaml

Write-Host "`nWaiting for ArgoCD server to be ready (this can take a few minutes on first install)..."
kubectl -n argocd rollout status deployment/argocd-server --timeout=300s

Write-Host "`nExposing ArgoCD UI on NodePort 30443..."
kubectl -n argocd patch svc argocd-server -p '{\"spec\": {\"type\": \"NodePort\"}}' | Out-Null
kubectl -n argocd patch svc argocd-server --type='json' -p='[{"op":"replace","path":"/spec/ports/1/nodePort","value":30443}]'

Write-Host "`nFetching initial admin password..."
$secretB64 = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}"
$password = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secretB64))

Write-Host ""
Write-Host "ArgoCD is ready:" -ForegroundColor Green
Write-Host "  URL:      https://localhost:30443  (self-signed certificate - accept the browser warning)"
Write-Host "  Username: admin"
Write-Host "  Password: $password"
Write-Host ""
Write-Host "Next: edit argocd/application.yaml to point repoURL at YOUR fork, then:" -ForegroundColor Yellow
Write-Host "  kubectl apply -f argocd/application.yaml"

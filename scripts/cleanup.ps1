<#
.SYNOPSIS
  Tears down everything this project created: Kubernetes resources,
  the docker-compose CI stack, and (optionally) built Docker images.

.PARAMETER RemoveImages
  Also remove the local devops-demo Docker images.

.EXAMPLE
  .\scripts\cleanup.ps1
  .\scripts\cleanup.ps1 -RemoveImages
#>

param(
    [switch]$RemoveImages
)

$root = Split-Path -Parent $PSScriptRoot
$ErrorActionPreference = "Continue"

Write-Host "=== Cleaning up devops-kubernetes-project ===" -ForegroundColor Cyan

Write-Host "`nRemoving Kubernetes resources..."
kubectl delete namespace devops-demo --ignore-not-found=true
kubectl delete namespace monitoring --ignore-not-found=true

Write-Host "`nStopping docker-compose CI stack (Jenkins, SonarQube, Postgres)..."
Push-Location "$root\docker"
docker compose down -v
Pop-Location

if ($RemoveImages) {
    Write-Host "`nRemoving local devops-demo Docker images..."
    docker images "devops-demo" -q | ForEach-Object { docker rmi -f $_ }
}

Write-Host "`nCleanup complete." -ForegroundColor Green
Write-Host "Note: ArgoCD itself (if you installed it via the README's optional section) is not removed by this script."
Write-Host "To remove it too: kubectl delete namespace argocd"

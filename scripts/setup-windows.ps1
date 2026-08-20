<#
.SYNOPSIS
  One-time environment check for the devops-kubernetes-project on Windows 11.
  Run this FIRST, from PowerShell, in the repository root.

.DESCRIPTION
  Verifies Docker Desktop, WSL2, kubectl, and Git are installed and working,
  checks that Kubernetes is enabled in Docker Desktop, and creates the
  namespaces the rest of the project expects. It does not install anything
  automatically (Windows package installs generally want an interactive
  elevated prompt) — instead it tells you exactly what to install and where.
#>

$ErrorActionPreference = "Continue"
$failures = @()

function Test-Command($name, $command, $installHint) {
    Write-Host "Checking $name..." -NoNewline
    try {
        $null = Invoke-Expression $command 2>$null
        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq $null) {
            Write-Host " OK" -ForegroundColor Green
            return $true
        } else {
            throw "non-zero exit"
        }
    } catch {
        Write-Host " MISSING" -ForegroundColor Red
        Write-Host "  -> $installHint" -ForegroundColor Yellow
        $script:failures += $name
        return $false
    }
}

Write-Host "=== devops-kubernetes-project: Windows 11 environment check ===" -ForegroundColor Cyan

Test-Command "Docker" "docker --version" `
    "Install Docker Desktop: https://www.docker.com/products/docker-desktop/"

Test-Command "Docker Compose" "docker compose version" `
    "Docker Compose ships with modern Docker Desktop - update Docker Desktop if missing."

Test-Command "Git" "git --version" `
    "Install Git for Windows: https://git-scm.com/download/win"

Test-Command "kubectl" "kubectl version --client" `
    "Install kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/ (or enable it via Docker Desktop Kubernetes)."

Write-Host ""
Write-Host "Checking WSL2..." -NoNewline
$wslStatus = wsl --status 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host " OK" -ForegroundColor Green
} else {
    Write-Host " MISSING" -ForegroundColor Red
    Write-Host "  -> Run in an elevated PowerShell: wsl --install" -ForegroundColor Yellow
    $failures += "WSL2"
}

Write-Host ""
Write-Host "Checking Kubernetes cluster reachability..." -NoNewline
kubectl cluster-info 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host " OK" -ForegroundColor Green
    $context = kubectl config current-context
    Write-Host "  Current context: $context"
    if ($context -notmatch "docker-desktop" -and $context -notmatch "minikube") {
        Write-Host "  WARNING: current context is not docker-desktop or minikube." -ForegroundColor Yellow
        Write-Host "  Run: kubectl config use-context docker-desktop" -ForegroundColor Yellow
    }
} else {
    Write-Host " NOT REACHABLE" -ForegroundColor Red
    Write-Host "  -> Open Docker Desktop -> Settings -> Kubernetes -> Enable Kubernetes -> Apply & Restart" -ForegroundColor Yellow
    Write-Host "     (If it stays stuck, use Minikube instead: minikube start --cpus=4 --memory=6144)" -ForegroundColor Yellow
    $failures += "Kubernetes cluster"
}

Write-Host ""
if ($failures.Count -eq 0) {
    Write-Host "All checks passed. Next steps:" -ForegroundColor Green
    Write-Host "  1. Copy .env.example to .env and fill in values"
    Write-Host "  2. .\scripts\build.ps1        # builds the app + Docker image"
    Write-Host "  3. .\scripts\deploy.ps1       # deploys Kubernetes + monitoring stack"
    Write-Host "  4. cd docker; docker compose up -d   # starts Jenkins + SonarQube"
} else {
    Write-Host "Please fix the items above before continuing:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

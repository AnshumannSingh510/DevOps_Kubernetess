<#
.SYNOPSIS
  Builds the Spring Boot application and the Docker image, without Jenkins.
  Useful for a quick local test before wiring up the full pipeline.

.PARAMETER Tag
  Docker image tag to build. Defaults to "latest".

.EXAMPLE
  .\scripts\build.ps1
  .\scripts\build.ps1 -Tag dev-1
#>

param(
    [string]$Tag = "latest"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

Write-Host "=== Building devops-demo:$Tag ===" -ForegroundColor Cyan

Push-Location "$root\app"
try {
    if (Get-Command mvn -ErrorAction SilentlyContinue) {
        Write-Host "Running Maven build + tests..." -ForegroundColor Cyan
        mvn -B clean verify
        if ($LASTEXITCODE -ne 0) { throw "Maven build failed" }
    } else {
        Write-Host "Maven not found locally - skipping local build/test; Docker multi-stage build will compile it instead." -ForegroundColor Yellow
    }
} finally {
    Pop-Location
}

Write-Host "Building Docker image devops-demo:$Tag ..." -ForegroundColor Cyan
docker build -t "devops-demo:$Tag" "$root\app"
if ($LASTEXITCODE -ne 0) { throw "Docker build failed" }

Write-Host ""
Write-Host "Done. Image built: devops-demo:$Tag" -ForegroundColor Green
Write-Host "Run it standalone with:"
Write-Host "  docker run --rm -p 8080:8080 devops-demo:$Tag"
Write-Host "Then visit: http://localhost:8080/api/health"

﻿$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "This script needs to run as admin"
}

if ((Test-Path (Join-Path $env:ProgramFiles "Docker Desktop")) -or (Test-Path (Join-Path $env:ProgramFiles "DockerDesktop"))) {
    throw "Docker Desktop is installed on this Computer, cannot run this script"
}

# Install Windows feature containers
$restartNeeded = $false
if (!(Get-WindowsOptionalFeature -FeatureName containers -Online).State -eq 'Enabled') {
    $restartNeeded = (Enable-WindowsOptionalFeature -FeatureName containers -Online).RestartNeeded
}

# Get Latest Stable version and URL
$latestZipFile = (Invoke-WebRequest -UseBasicParsing -uri "https://download.docker.com/win/static/stable/x86_64/").Content.split("`r`n") | 
                 Where-Object { $_ -like "<a href=""docker-*"">docker-*" } | 
                 ForEach-Object { $zipName = $_.Split('"')[1]; [Version]($zipName.SubString(7,$zipName.Length-11).Split('-')[0]) } | 
                 Sort-Object | Select-Object -Last 1 | ForEach-Object { "docker-$_.zip" }

if (-not $latestZipFile) {
    throw "Unable to locate latest stable docker download"
}
if ($latestZipFile -eq "docker-20.10.10.zip") {
    $latestZipFile = "docker-20.10.9.zip"
}
$latestZipFileUrl = "https://download.docker.com/win/static/stable/x86_64/$latestZipFile"
$latestVersion = [Version]($latestZipFile.SubString(7,$latestZipFile.Length-11))
Write-Host "Latest stable available Docker Engine version is $latestVersion"

# Check existing docker version
$dockerService = get-service docker -ErrorAction SilentlyContinue
if ($dockerService) {
    if ($dockerService.Status -eq "Running") {
        $dockerVersion = [Version](docker version -f "{{.Server.Version}}")
        Write-Host "Current installed Docker Engine version $dockerVersion"
        if ($latestVersion -le $dockerVersion) {
            Write-Host "No new Docker Engine available"
            Return
        }
        Write-Host "New Docker Engine available"
    }
    else {
        Write-Host "Docker Service not running"
    }
}
else {
    Write-Host "Docker Engine not found"
}

Read-Host "Press Enter to Install new Docker Engine version (or Ctrl+C to break) ?"

if ($dockerService) {
    Stop-Service docker
}

# Download new version
$tempFile = "$([System.IO.Path]::GetTempFileName()).zip"
Invoke-WebRequest -UseBasicParsing -Uri $latestZipFileUrl -OutFile $tempFile
Expand-Archive $tempFile -DestinationPath $env:ProgramFiles -Force
Remove-Item $tempFile -Force

if ("$($env:Path);" -notlike "*;$($env:ProgramFiles)\docker;*") {
    [Environment]::SetEnvironmentVariable("Path", "$($env:path);$env:ProgramFiles\docker", [System.EnvironmentVariableTarget]::User)
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","User")
}

# Register service if necessary
if (-not $dockerService) {
    dockerd --register-service
}

Start-Service docker

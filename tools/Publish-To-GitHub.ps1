# Maintainer-only publishing helper for a NEW public Morfildor/Blitz-Ad-Shield repository.
# Requires Git and GitHub CLI (gh) installed and access to the Morfildor GitHub account.
# Does not use hard-coded credentials or change the visibility of any existing repository.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$fullName = 'Morfildor/Blitz-Ad-Shield'
$root = Split-Path -Parent $PSScriptRoot

function Assert-ExitCode([string]$Activity) {
    if ($LASTEXITCODE -ne 0) { throw "$Activity failed (exit code $LASTEXITCODE)." }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git is not installed. Install Git for Windows first.' }
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'GitHub CLI (gh) is not installed. Install it from https://cli.github.com/ first.' }

Push-Location $root
try {
    # Read-only existence probes should not terminate this Windows PowerShell session.
    $ErrorActionPreference = 'Continue'
    & gh auth status 2>$null | Out-Null
    $isUnauthenticated = ($LASTEXITCODE -ne 0)
    $ErrorActionPreference = 'Stop'
    if ($isUnauthenticated) {
        Write-Host 'Sign in to GitHub in the browser...' -ForegroundColor Cyan
        & gh auth login --web --hostname github.com
        Assert-ExitCode 'GitHub login'
    }

    $login = (& gh api user --jq .login).Trim()
    Assert-ExitCode 'GitHub account check'
    if ($login -ne 'Morfildor') {
        throw "Authenticated as '$login'. Log in as Morfildor to publish this project."
    }

    Write-Host "Repository: https://github.com/$fullName" -ForegroundColor Cyan
    $confirm = Read-Host 'Create or update the PUBLIC repository using these files? Enter PUBLISH to continue'
    if ($confirm -cne 'PUBLISH') { Write-Host 'Cancelled'; return }

    if (-not (Test-Path -LiteralPath '.git' -PathType Container)) {
        & git init -b main
        Assert-ExitCode 'git init'
    }
    $branch = (& git branch --show-current).Trim()
    if (-not $branch) {
        # Empty repositories may not show a current branch yet.
        & git symbolic-ref HEAD refs/heads/main
        Assert-ExitCode 'Set main branch'
    } elseif ($branch -ne 'main') {
        throw "Current branch is '$branch', expected 'main'. Publish from a fresh project folder."
    }

    & git add -A
    Assert-ExitCode 'Stage project files'
    & git diff --cached --quiet
    if ($LASTEXITCODE -eq 1) {
        & git -c 'user.name=Morfildor' -c 'user.email=23294363+Morfildor@users.noreply.github.com' commit -m 'Publish Blitz Ad Shield v0.2'
        Assert-ExitCode 'Create commit'
    } elseif ($LASTEXITCODE -ne 0) {
        throw 'Unable to check staged changes.'
    }

    $ErrorActionPreference = 'Continue'
    & gh repo view $fullName --json name --jq .name 2>$null | Out-Null
    $repoMissing = ($LASTEXITCODE -ne 0)
    $ErrorActionPreference = 'Stop'
    if ($repoMissing) {
        Write-Host 'Creating the public repository and pushing main...' -ForegroundColor Cyan
        & gh repo create $fullName --public --description 'Experimental free Windows system-tray ad blocker for the Blitz.gg desktop app' --source . --remote origin --push
        Assert-ExitCode 'Create and push repository'
    } else {
        $ErrorActionPreference = 'Continue'
        $remote = (& git remote get-url origin 2>$null)
        $remoteMissing = ($LASTEXITCODE -ne 0)
        $ErrorActionPreference = 'Stop'
        if ($remoteMissing -or $remote -notmatch '(^|[/:])Morfildor/Blitz-Ad-Shield(\.git)?$') {
            throw 'That GitHub repository already exists, but this folder has no matching origin remote. No files were pushed.'
        }
        & git push -u origin main
        Assert-ExitCode 'Push changes'
    }

    & gh repo edit $fullName --add-topic powershell --add-topic windows --add-topic league-of-legends --add-topic adblock --add-topic system-tray
    if ($LASTEXITCODE -ne 0) { Write-Warning 'Could not add repository topics.' }

    Write-Host 'Configuring GitHub Pages from main/docs...' -ForegroundColor Cyan
    $ErrorActionPreference = 'Continue'
    & gh api -X POST "repos/$fullName/pages" -f 'source[branch]=main' -f 'source[path]=/docs' --silent 2>$null
    $pagesFailed = ($LASTEXITCODE -ne 0)
    $ErrorActionPreference = 'Stop'
    if ($pagesFailed) {
        Write-Warning 'Pages was not enabled automatically. In GitHub: Settings > Pages > Deploy from a branch > main /docs > Save.'
    }

    Write-Host ''
    Write-Host "Repository: https://github.com/$fullName" -ForegroundColor Green
    Write-Host 'Pages URL (after GitHub finishes deploying): https://morfildor.github.io/Blitz-Ad-Shield/' -ForegroundColor Green
    Write-Host 'Verify the repo visibility, rendered README, and Pages status in GitHub.'
}
finally { Pop-Location }

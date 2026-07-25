# Apply facefusion-deck-kit on top of a clean FaceFusion / Pinokio install.
#
# Examples:
#   .\apply.ps1
#   .\apply.ps1 -Target "C:\pinokio\api\facefusion-pinokio.git"
#   .\apply.ps1 -Target "D:\apps\facefusion" -SkipPinokio
#   .\apply.ps1 -DryRun

param(
	[string]$Target = "",
	[switch]$SkipNsfw,
	[switch]$SkipProfiles,
	[switch]$SkipPinokio,
	[switch]$DryRun
)

$ErrorActionPreference = "Stop"
$KitRoot = $PSScriptRoot

function Write-Step([string]$Message) {
	Write-Host "==> $Message" -ForegroundColor Cyan
}

function Resolve-DefaultTarget {
	$candidates = @(
		"C:\pinokio\api\facefusion-pinokio.git",
		(Join-Path $env:USERPROFILE "pinokio\api\facefusion-pinokio.git"),
		(Join-Path $env:LOCALAPPDATA "pinokio\api\facefusion-pinokio.git")
	)
	foreach ($c in $candidates) {
		if (Test-Path -LiteralPath $c) {
			return (Resolve-Path -LiteralPath $c).Path
		}
	}
	return $null
}

function Get-Layout([string]$Root) {
	$hasRun = Test-Path -LiteralPath (Join-Path $Root "run.js")
	$hasNested = Test-Path -LiteralPath (Join-Path $Root "facefusion\facefusion.py")
	$hasStandalone = Test-Path -LiteralPath (Join-Path $Root "facefusion.py")

	if ($hasRun -and $hasNested) { return "pinokio" }
	if ($hasStandalone) { return "standalone" }
	if ($hasNested) { return "nested" }
	return "unknown"
}

function Backup-File([string]$FilePath, [string]$BackupDir) {
	if (-not (Test-Path -LiteralPath $FilePath)) { return }
	$leaf = Split-Path -Leaf $FilePath
	$parent = Split-Path -Leaf (Split-Path -Parent $FilePath)
	$destName = "${parent}__${leaf}"
	Copy-Item -LiteralPath $FilePath -Destination (Join-Path $BackupDir $destName) -Force
}

function Copy-Overlay([string]$Source, [string]$Destination) {
	if ($DryRun) {
		Write-Host "  [dry-run] copy $(Split-Path -Leaf $Source) -> $Destination"
		return
	}
	Backup-File $Destination $script:backupDir
	Copy-Item -LiteralPath $Source -Destination $Destination -Force
	Write-Host "  copied $(Split-Path -Leaf $Source)"
}

if (-not $Target) {
	$Target = Resolve-DefaultTarget
	if (-not $Target) {
		throw "Target not found. Pass -Target path to Pinokio FaceFusion app or FaceFusion clone."
	}
	Write-Host "Auto-detected target: $Target"
}

if (-not (Test-Path -LiteralPath $Target)) {
	throw "Target path does not exist: $Target"
}

$Target = (Resolve-Path -LiteralPath $Target).Path
$layout = Get-Layout $Target
if ($layout -eq "unknown") {
	throw "Unrecognized layout at $Target. Expected Pinokio app (run.js + facefusion/) or FaceFusion repo (facefusion.py)."
}

Write-Step "Target: $Target"
Write-Step "Layout: $layout"
if ($DryRun) { Write-Step "DRY RUN (no files will be modified by copy; NSFW uses --dry-run)" }

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$script:backupDir = Join-Path $Target "deck-kit-backup\$timestamp"
if (-not $DryRun) {
	New-Item -ItemType Directory -Force -Path $script:backupDir | Out-Null
}
Write-Step "Backup folder: $script:backupDir"

if (-not $SkipProfiles) {
	Write-Step "Installing profile configs"
	if ($layout -eq "standalone") {
		$faceRoot = $Target
	} else {
		$faceRoot = Join-Path $Target "facefusion"
	}
	if (-not (Test-Path -LiteralPath (Join-Path $faceRoot "facefusion.py"))) {
		throw "facefusion.py not found under $faceRoot"
	}
	Get-ChildItem -LiteralPath (Join-Path $KitRoot "overlay\facefusion") -Filter "*.ini" | ForEach-Object {
		$dest = Join-Path $faceRoot $_.Name
		Copy-Overlay $_.FullName $dest
	}
}

if (-not $SkipPinokio) {
	if ($layout -eq "pinokio") {
		Write-Step "Installing Pinokio launcher overlay"
		foreach ($name in @("run.js", "menu.js")) {
			$src = Join-Path $KitRoot "overlay\pinokio\$name"
			$dest = Join-Path $Target $name
			Copy-Overlay $src $dest
		}
	} else {
		Write-Host "  (not a Pinokio app root - skipping run.js/menu.js)"
	}
}

if (-not $SkipNsfw) {
	Write-Step "Patching NSFW filter"
	$python = $null
	$pyCandidates = @(
		(Join-Path $Target ".env\python.exe"),
		(Join-Path $Target "facefusion\.env\python.exe")
	)
	foreach ($p in $pyCandidates) {
		if (Test-Path -LiteralPath $p) {
			$python = $p
			break
		}
	}
	if (-not $python) {
		$cmd = Get-Command python -ErrorAction SilentlyContinue
		if ($cmd) { $python = $cmd.Source }
	}
	if (-not $python) {
		throw "Python not found. Install FaceFusion first, or put python on PATH."
	}

	$pkgCandidates = @(
		(Join-Path $Target "facefusion\facefusion"),
		(Join-Path $Target "facefusion")
	)
	foreach ($pkg in $pkgCandidates) {
		foreach ($f in @("content_analyser.py", "core.py")) {
			$fp = Join-Path $pkg $f
			if (Test-Path -LiteralPath $fp) {
				if (-not $DryRun) { Backup-File $fp $script:backupDir }
			}
		}
	}

	$patcher = Join-Path $KitRoot "scripts\patch_nsfw.py"
	$pyArgs = @($patcher, $Target)
	if ($DryRun) { $pyArgs += "--dry-run" }
	& $python @pyArgs
	if ($LASTEXITCODE -ne 0) {
		throw "NSFW patch failed (exit $LASTEXITCODE)"
	}
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Backups: $script:backupDir"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Stop FaceFusion if it is running"
Write-Host "  2. In Pinokio open FaceFusion and pick Fast / Balanced / Quality"
Write-Host "  3. After Pinokio Update/Reset, run this script again"
Write-Host ""
Write-Host "Standalone (no Pinokio):"
Write-Host "  python facefusion.py run --config-path facefusion.balanced.ini"

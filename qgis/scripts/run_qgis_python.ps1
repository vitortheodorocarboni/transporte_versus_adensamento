param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$Script,

  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$ScriptArguments
)

$ErrorActionPreference = "Stop"

# Resolving the repository root from this launcher's location.
$repositoryRoot = (
  Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")
).Path

# Resolving the requested script relative to the repository when necessary.
$scriptCandidate = if ([IO.Path]::IsPathRooted($Script)) {
  $Script
} else {
  Join-Path $repositoryRoot $Script
}
$scriptPath = (Resolve-Path -LiteralPath $scriptCandidate).Path

# Reading an optional explicit QGIS Python launcher.
$configuredLauncher = $env:QGIS_PYTHON_BAT
$launcherCandidates = @()

if ($configuredLauncher) {
  $launcherCandidates += Get-Item -LiteralPath $configuredLauncher
}

# Discovering installed QGIS launchers under the standard Windows directory.
$standardQgisRoot = Join-Path $env:ProgramFiles "QGIS *"
$launcherCandidates += Get-ChildItem `
  -Path (Join-Path $standardQgisRoot "bin\python-qgis.bat") `
  -File `
  -ErrorAction SilentlyContinue

if ($launcherCandidates.Count -eq 0) {
  throw (
    "QGIS Python was not found. Install QGIS or set QGIS_PYTHON_BAT to " +
    "the full path of python-qgis.bat."
  )
}

# Selecting the newest installed launcher by its parent QGIS version.
$qgisLauncher = $launcherCandidates |
  Sort-Object {
    $versionMatch = [regex]::Match(
      $_.Directory.Parent.Name,
      "QGIS\s+([0-9]+(?:\.[0-9]+)*)"
    )
    if ($versionMatch.Success) {
      [version]$versionMatch.Groups[1].Value
    } else {
      [version]"0.0"
    }
  } -Descending |
  Select-Object -First 1

# Keeping Windows text rendering and QGIS state deterministic.
$env:QT_QPA_PLATFORM = "windows"
$env:QGIS_CUSTOM_CONFIG_PATH = Join-Path $env:TEMP "qgis_dissertation"

# Running the selected script from the repository root.
Push-Location -LiteralPath $repositoryRoot
try {
  & $qgisLauncher.FullName `
    -X faulthandler `
    $scriptPath `
    @ScriptArguments
  exit $LASTEXITCODE
} finally {
  Pop-Location
}

param(
  [Parameter(Mandatory = $true)]
  [string]$InputFile
)

$projectRoot = "C:\Diss"
$quartoExe = "C:\Program Files\RStudio\resources\app\bin\quarto\bin\quarto.exe"
$tinytexCandidates = @(
  "C:\TinyTeX\bin\windows",
  (Join-Path $env:APPDATA "TinyTeX\bin\windows"),
  (Join-Path $env:USERPROFILE "TinyTeX\bin\windows"),
  (Join-Path $env:LOCALAPPDATA "TinyTeX\bin\windows")
)
$tinytexBin = $null
foreach ($candidate in $tinytexCandidates) {
  $candidatePdfEngine = Join-Path $candidate "xelatex.exe"
  $candidateKpsewhich = Join-Path $candidate "kpsewhich.exe"
  if ((Test-Path $candidatePdfEngine) -and (Test-Path $candidateKpsewhich)) {
    & $candidateKpsewhich -var-value=TEXMFVAR *> $null
    if ($LASTEXITCODE -eq 0) {
      $tinytexBin = $candidate
      break
    }
  }
}
$pdfEngine = if ($tinytexBin) { Join-Path $tinytexBin "xelatex.exe" } else { $null }

if (-not (Test-Path $projectRoot)) {
  throw "Project junction not found at C:\Diss. Recreate it with: cmd /c mklink /J C:\Diss `"<project-root>`""
}

if (-not $pdfEngine) {
  throw "Global TinyTeX with xelatex.exe was not found. Install it with tinytex::install_tinytex() in R."
}

$env:LOCALAPPDATA = Join-Path $projectRoot ".quarto-local\localappdata"
$env:APPDATA = Join-Path $projectRoot ".quarto-local\appdata"
$env:TEXMFCACHE = Join-Path $projectRoot ".quarto-local\texmf-cache"
$env:TEXMFVAR = Join-Path $projectRoot ".quarto-local\texmf-var"
$env:TEXMFCONFIG = Join-Path $projectRoot ".quarto-local\texmf-config"
$env:PATH = "$tinytexBin;$env:PATH"

New-Item -ItemType Directory -Force -Path $env:LOCALAPPDATA, $env:APPDATA, $env:TEXMFCACHE, $env:TEXMFVAR, $env:TEXMFCONFIG | Out-Null

if ([System.IO.Path]::IsPathRooted($InputFile)) {
  $resolvedInput = Resolve-Path $InputFile
} else {
  $resolvedInput = Resolve-Path (Join-Path $projectRoot $InputFile)
}

& $quartoExe render $resolvedInput --to pdf --pdf-engine $pdfEngine

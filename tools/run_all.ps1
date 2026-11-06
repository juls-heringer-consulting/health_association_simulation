<#
.SYNOPSIS
    Rebuilds the complete KVSim training database from scratch:
    generate sources -> create objects -> load staging -> core -> mart -> data quality.

.DESCRIPTION
    This is the automated version of what you can also do by hand in SSMS
    (see README.md, "Run it step by step"). It uses sqlcmd (Windows auth) and the
    project's Python virtual environment.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\run_all.ps1
    powershell -ExecutionPolicy Bypass -File tools\run_all.ps1 -SkipGenerate
#>
param(
    [string]$Server = "localhost",
    [switch]$SkipGenerate      # reuse the existing files in data/sources
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$python = Join-Path $root ".venv\Scripts\python.exe"
$env:PYTHONPATH = Join-Path $root "python"

function Invoke-SqlFile([string]$path) {
    Write-Host "  sql  $path"
    # -b: abort on error, -I: QUOTED_IDENTIFIER on, -C: trust the local self-signed certificate, -f 65001: UTF-8 files
    & sqlcmd -S $Server -E -C -b -I -f 65001 -i $path | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "sqlcmd failed for $path" }
}

function Invoke-Sql([string]$query) {
    Write-Host "  exec $query"
    & sqlcmd -S $Server -E -C -b -I -d KVSim -W -s "|" -Q $query
    if ($LASTEXITCODE -ne 0) { throw "sqlcmd failed: $query" }
}

if (-not $SkipGenerate) {
    Write-Host "1) Generate synthetic source files"
    & $python python\generate_sources.py
    if ($LASTEXITCODE -ne 0) { throw "generator failed" }
}

Write-Host "2) Create database objects (00 - 85)"
$folders = "00_setup", "10_meta", "20_stg", "30_core", "40_core_load", "50_mart", "60_mart_load", "70_quality", "80_security", "85_fulltext"
foreach ($folder in $folders) {
    Get-ChildItem (Join-Path "sql" $folder) -Filter *.sql | Sort-Object Name | ForEach-Object { Invoke-SqlFile $_.FullName }
}

Write-Host "3) Load staging (Python)"
& $python python\load_staging.py
if ($LASTEXITCODE -ne 0) { throw "staging load failed" }

Write-Host "4) stg -> core -> mart, then data quality"
Invoke-Sql "EXEC core.usp_load_all;"
Invoke-Sql "EXEC mart.usp_load_all;"
Invoke-Sql "EXEC meta.usp_run_dq_checks;"

Write-Host "5) Export the data dictionary to docs/data_dictionary.md"
& $python python\export_data_dictionary.py
if ($LASTEXITCODE -ne 0) { throw "data dictionary export failed" }

Write-Host "Done."

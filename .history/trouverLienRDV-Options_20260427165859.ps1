<#
.SYNOPSIS
    Lien entre les RDV Web (Novius) et les Options Winner (devis/commandes)
.DESCRIPTION
    Ce script utilise DuckDB (via CLI duckdb.exe) avec l'extension nanodbc pour :
      1. Charger en mémoire les Options Winner et les RDV Web depuis SQL Server
      2. Effectuer la jointure sur email / téléphone normalisé
      3. Exporter le résultat en CSV
.NOTES
    Script         : trouverLienRDV-Options.ps1
    Emplacement    : D:\MyReport\Sources\Reporting\DIGITAL\Sources\LienRDV-Options\SCRIPT\
    Prérequis      : duckdb.exe (CLI), DuckDB.ps1, D:\ScriptsPS\Sentry.ps1
    Auteur         : steven.azar@gp-aviva.com
    Historique     :
        2026-04-27 : SAK :  - Création du script
#>

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sqlFolder  = $scriptRoot

$sqlChargerDonnees = Join-Path $sqlFolder "charger_donnees.sql"
$sqlLienRdvOptions = Join-Path $sqlFolder "lien_rdv_options.sql"
$csvOutputPath     = "D:\MyReport\Sources\Reporting\DIGITAL\Sources\LienRDV-Options\LIEN_RDV_WEB_OPTION.csv"
$DuckDBExe         = "C:\duckdb.exe"

. "D:\ScriptsPS\DuckDB.ps1"

$ini = Import-PowerShellDataFile -Path "D:\MyReport\Sources\Reporting\DIGITAL\Sources\configSentry.psd1"
. "D:\ScriptsPS\Sentry.ps1" -dsn $ini.sentry.dsn

$logFolder = Join-Path $scriptRoot "LOG"
if (-Not (Test-Path $logFolder)) {
    New-Item -ItemType Directory -Path $logFolder -Force | Out-Null
}
$logFile = Join-Path $logFolder "output-trouverLienRDV-Options-$(Get-Date -Format 'yyyy-MM-dd').txt"
Start-Transcript -Path $logFile -Append

Write-Host "  LIEN RDV WEB (Novius) <-> OPTIONS (Winner)" -ForegroundColor Cyan
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan

try {

    if (-Not (Test-Path $DuckDBExe))         { Write-Error "DuckDB introuvable : $DuckDBExe"; exit 1 }
    if (-Not (Test-Path $sqlChargerDonnees)) { Write-Error "SQL introuvable : $sqlChargerDonnees"; exit 2 }
    if (-Not (Test-Path $sqlLienRdvOptions)) { Write-Error "SQL introuvable : $sqlLienRdvOptions"; exit 3 }

    $csvOutputFolder = Split-Path -Parent $csvOutputPath
    if (-Not (Test-Path $csvOutputFolder)) {
        New-Item -ItemType Directory -Path $csvOutputFolder -Force | Out-Null
    }

    Stop-DuckProcess

    Write-Host "[1/3] Chargement des données sources (SQL Server -> DuckDB mémoire)..." -ForegroundColor Yellow
    $sqlChargement = Get-Content -Path $sqlChargerDonnees -Raw

    $chrono = [System.Diagnostics.Stopwatch]::StartNew()

    Write-Host "[2/3] Exécution de la requête de lien + export CSV..." -ForegroundColor Yellow
    $sqlLien             = Get-Content -Path $sqlLienRdvOptions -Raw
    $csvOutputPathDuckDB = $csvOutputPath -replace '\\', '/'
    $sqlLien             = $sqlLien -replace '\{\{CSV_OUTPUT_PATH\}\}', $csvOutputPathDuckDB

    $sqlComplet = @"
$sqlChargement

$sqlLien
"@

    $tempSqlFull = [System.IO.Path]::GetTempFileName() + ".sql"
    Set-Content -Path $tempSqlFull -Value $sqlComplet -Encoding UTF8

    $duckOutput = & $DuckDBExe ":memory:" -init $tempSqlFull ".quit" 2>&1

    $chrono.Stop()

    if (Test-Path $csvOutputPath) {
        $csvInfo  = Get-Item $csvOutputPath
        $nbLignes = (Import-Csv -Path $csvOutputPath | Measure-Object).Count
        Write-Host "  CSV créé : $csvOutputPath ($nbLignes lignes, $([math]::Round($csvInfo.Length / 1KB, 1)) Ko) en $($chrono.Elapsed.TotalSeconds.ToString('F1'))s" -ForegroundColor Green
    }
    else {
        Write-Error "Le fichier CSV n'a pas été créé."
        $duckOutput | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        exit 10
    }

    Write-Host "[3/3] Nettoyage..." -ForegroundColor Yellow
    Remove-Item $tempSqlFull -Force -ErrorAction SilentlyContinue

    Write-Host "  Traitement terminé avec succès" -ForegroundColor Green

}
catch {
    Edit-SentryScope {
        $_.Contexts['LienRDV'] = @{
            script    = $PSCommandPath
            csvOutput = $csvOutputPath
        };
    }
    $_ | Out-Sentry

    Write-Error "Erreur : $($_.Exception.Message)"
    Write-Error $_.ScriptStackTrace
    if ($duckOutput) {
        $duckOutput | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    }
    exit 99
}
finally {
    if ($tempSqlFull -and (Test-Path $tempSqlFull)) {
        Remove-Item $tempSqlFull -Force -ErrorAction SilentlyContinue
    }
    Stop-Transcript
}
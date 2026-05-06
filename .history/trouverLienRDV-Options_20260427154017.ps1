<#
.SYNOPSIS
    Lien entre les RDV Web (Novius) et les Options Winner (devis/commandes)
.DESCRIPTION
    Ce script utilise DuckDB (via CLI duckdb.exe) avec l'extension nanodbc pour :
      1. Charger en mémoire les Options Winner et les RDV Web depuis SQL Server
      2. Effectuer la jointure sur email / téléphone normalisé
      3. Exporter le résultat en CSV
    
    Le lien se fait sur email OU téléphone car il n'y a pas d'identifiant client
    unique entre le site internet et WinnerBizz.
    
    La requête SQL Server native bloquait la base ; DuckDB en mémoire est
    beaucoup plus performant pour ce type de jointure.
.NOTES
    Script         : trouverLienRDV-Options.ps1
    Emplacement    : D:\MyReport\Sources\Reporting\DIGITAL\Sources\LienRDV-Options\SCRIPT\
    Prérequis      : duckdb.exe (CLI), DuckDB.fonctions.ps1
    Auteur         : steven.azar@gp-aviva.com
    Historique     :
        2026 - Création initiale
.LINK
#>


# Chemins de base
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sqlFolder  = $scriptRoot   # Les fichiers SQL sont dans le même dossier SCRIPT

# Fichiers SQL externes
$sqlChargerDonnees    = Join-Path $sqlFolder "01_charger_donnees.sql"
$sqlLienRdvOptions    = Join-Path $sqlFolder "02_lien_rdv_options.sql"

# Fichier CSV de sortie
$csvOutputPath = "D:\MyReport\Sources\Reporting\DIGITAL\Sources\LienRDV-Options\LIEN_RDV_WEB_OPTION.csv"

# Exécutable DuckDB
$DuckDBExe = "C:\duckdb.exe"

# Chargement des fonctions utilitaires DuckDB
. "D:\ScriptsPS\DuckDB.ps1"


$logFolder = Join-Path $scriptRoot "LOG"
if (-Not (Test-Path $logFolder)) {
    New-Item -ItemType Directory -Path $logFolder -Force | Out-Null
}
$logFile = Join-Path $logFolder "output-trouverLienRDV-Options-$(Get-Date -Format 'yyyy-MM-dd').txt"
Start-Transcript -Path $logFile -Append


Write-Host "  LIEN RDV WEB (Novius) <-> OPTIONS (Winner)" -ForegroundColor Cyan
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan


try {
    
    # Étape 0 : Vérifications préalables
    
    Write-Host "[0/3] Vérifications préalables..." -ForegroundColor Yellow

    if (-Not (Test-Path $DuckDBExe)) {
        Write-Error "Exécutable DuckDB introuvable : $DuckDBExe"
        exit 1
    }
    Write-Host "      DuckDB CLI trouvé : $DuckDBExe" -ForegroundColor Green

    if (-Not (Test-Path $sqlChargerDonnees)) {
        Write-Error "Fichier SQL introuvable : $sqlChargerDonnees"
        exit 2
    }

    if (-Not (Test-Path $sqlLienRdvOptions)) {
        Write-Error "Fichier SQL introuvable : $sqlLienRdvOptions"
        exit 3
    }
    Write-Host "      Fichiers SQL trouvés" -ForegroundColor Green

    # Créer le dossier de sortie CSV si nécessaire
    $csvOutputFolder = Split-Path -Parent $csvOutputPath
    if (-Not (Test-Path $csvOutputFolder)) {
        New-Item -ItemType Directory -Path $csvOutputFolder -Force | Out-Null
        Write-Host "      Dossier de sortie créé : $csvOutputFolder" -ForegroundColor Green
    }

    # Stopper les éventuels processus DuckDB résiduels
    Stop-DuckProcess

   
    # Étape 1 : Charger les données sources dans la mémoire DuckDB
    
    Write-Host "`n[1/3] Chargement des données sources (SQL Server -> DuckDB mémoire)..." -ForegroundColor Yellow

    $sqlChargement = Get-Content -Path $sqlChargerDonnees -Raw

    # On utilise le fichier SQL temporaire + CLI DuckDB
    $tempSqlStep1 = [System.IO.Path]::GetTempFileName() + ".sql"
    Set-Content -Path $tempSqlStep1 -Value $sqlChargement -Encoding UTF8

    $chrono = [System.Diagnostics.Stopwatch]::StartNew()

    # Exécution via CLI DuckDB en mémoire
    # Note : on ne peut pas enchaîner 2 appels CLI séparés car la mémoire
    # est perdue entre chaque invocation. On concatène donc les 2 étapes
    # (chargement + requête) dans un seul appel.

  
    # Étape 2 : Exécuter la requête de lien et exporter en CSV
    
    Write-Host "`n[2/3] Exécution de la requête de lien + export CSV..." -ForegroundColor Yellow

    $sqlLien = Get-Content -Path $sqlLienRdvOptions -Raw

    # Remplacer le placeholder du chemin CSV
    # On échappe les backslashes pour DuckDB (utilise des forward slashes)
    $csvOutputPathDuckDB = $csvOutputPath -replace '\\', '/'
    $sqlLien = $sqlLien -replace '\{\{CSV_OUTPUT_PATH\}\}', $csvOutputPathDuckDB

    # Concaténer les 2 scripts SQL : chargement + jointure/export
    $sqlComplet = @"

-- ÉTAPE 1 : Chargement des données sources

$sqlChargement

-- ============================================
-- ÉTAPE 2 : Jointure et export CSV

$sqlLien
"@

    # Écrire le SQL complet dans un fichier temporaire
    $tempSqlFull = [System.IO.Path]::GetTempFileName() + ".sql"
    Set-Content -Path $tempSqlFull -Value $sqlComplet -Encoding UTF8

    Write-Host "      Exécution DuckDB CLI en mémoire (nanodbc -> ODBC -> SQL Server)..." -ForegroundColor Gray

    # Exécution via CLI DuckDB : base en mémoire (:memory:)
    $duckOutput = & $DuckDBExe ":memory:" -init $tempSqlFull ".quit" 2>&1

    $chrono.Stop()

    # Vérifier si le CSV a été créé
    if (Test-Path $csvOutputPath) {
        $csvInfo = Get-Item $csvOutputPath
        $nbLignes = (Import-Csv -Path $csvOutputPath | Measure-Object).Count
        Write-Host "      CSV créé avec succès !" -ForegroundColor Green
        Write-Host "      Chemin   : $csvOutputPath" -ForegroundColor Green
        Write-Host "      Taille   : $([math]::Round($csvInfo.Length / 1KB, 1)) Ko" -ForegroundColor Green
        Write-Host "      Lignes   : $nbLignes" -ForegroundColor Green
        Write-Host "      Durée    : $($chrono.Elapsed.TotalSeconds.ToString('F1')) secondes" -ForegroundColor Green
    }
    else {
        Write-Error "Le fichier CSV n'a pas été créé. Vérifier les logs DuckDB."
        Write-Host "Sortie DuckDB :" -ForegroundColor Red
        $duckOutput | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        exit 10
    }

    # Étape 3 : Nettoyage
  
    Write-Host "`n[3/3] Nettoyage..." -ForegroundColor Yellow

    # Supprimer les fichiers SQL temporaires
    Remove-Item $tempSqlStep1 -Force -ErrorAction SilentlyContinue
    Remove-Item $tempSqlFull  -Force -ErrorAction SilentlyContinue
    Write-Host "      Fichiers temporaires supprimés" -ForegroundColor Green


    Write-Host ""
    Write-Host "  ================================================================" -ForegroundColor Green
    Write-Host "  TRAITEMENT TERMINE AVEC SUCCES" -ForegroundColor Green
    Write-Host "  $csvOutputPath" -ForegroundColor Green
    Write-Host "  ================================================================" -ForegroundColor Green
    Write-Host ""

}
catch {
    Write-Error "ERREUR : $($_.Exception.Message)"
    Write-Error $_.ScriptStackTrace

    # Afficher la sortie DuckDB si disponible
    if ($duckOutput) {
        Write-Host "`nSortie DuckDB :" -ForegroundColor Red
        $duckOutput | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    }

    exit 99
}
finally {
    # Nettoyage des fichiers temporaires en cas d'erreur
    if ($tempSqlStep1 -and (Test-Path $tempSqlStep1)) {
        Remove-Item $tempSqlStep1 -Force -ErrorAction SilentlyContinue
    }
    if ($tempSqlFull -and (Test-Path $tempSqlFull)) {
        Remove-Item $tempSqlFull -Force -ErrorAction SilentlyContinue
    }

    Stop-Transcript
}
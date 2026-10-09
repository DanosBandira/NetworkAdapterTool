<#
.SYNOPSIS
    Zet een ADS-route op naar een Beckhoff PLC. Aanroepbaar vanaf de commandline of een externe applicatie.

.DESCRIPTION
    Alle instellingen komen uit de argumenten; het script leest of schrijft geen configuratiebestand.
    - Verwijdert bestaande lokale routes naar hetzelfde IP-adres (oude PLC met andere NetId).
    - Voegt een nieuwe route toe via Add-AdsRoute (TcXaeMgmt) en test de verbinding.
    - Nooit interactief, behalve de vraag om TcXaeMgmt te installeren als die ontbreekt.

    Exitcodes:
      0 = route toegevoegd (en test geslaagd)
      1 = ontbrekende of ongeldige argumenten
      2 = TcXaeMgmt module niet gevonden
      3 = route toevoegen mislukt
      4 = route toegevoegd, maar verbindingstest mislukt

.PARAMETER Address
    IP-adres of hostnaam van de PLC. Verplicht.
.PARAMETER UserName
    Gebruikersnaam op de PLC. Verplicht.
.PARAMETER Password
    Wachtwoord op de PLC (platte tekst). Verplicht.
    Let op: een argument is zichtbaar in de proceslijst.
.PARAMETER SelfSigned
    Secure ADS (SelfSigned) gebruiken.
.PARAMETER Temporary
    Route als tijdelijke route registreren.
.PARAMETER KeepExisting
    Bestaande routes naar hetzelfde IP niet verwijderen.
.PARAMETER NoTest
    Verbindingstest overslaan.
.PARAMETER Timeout
    Zoek-timeout in ms voor het vinden van de PLC (standaard 5000).
.PARAMETER Json
    Resultaat als één JSON-regel naar stdout schrijven (handig voor externe applicaties).
.PARAMETER Bool
    Alleen 'true' of 'false' naar stdout schrijven (gelukt of niet). Meldingen gaan naar stderr.
.PARAMETER ErrorWait
    Aantal seconden wachten bij een fout voordat het script afsluit (standaard 5, 0 = niet wachten).
.PARAMETER InstallModule
    TcXaeMgmt automatisch installeren als deze ontbreekt, zonder te vragen.
    Zonder deze optie wordt het alleen gevraagd bij interactief gebruik (niet met -Json/-Bool).
    Niet-interactief is ook -AcceptLicense nodig (Beckhoff vereist acceptatie van hun licentie).
.PARAMETER AcceptLicense
    Hiermee accepteer je de licentie van Beckhoff voor TcXaeMgmt bij automatische installatie.

.EXAMPLE
    .\beckhoff-auto-router.ps1 -Address 192.168.1.50 -UserName Administrator -Password 1 -Json
#>
[CmdletBinding()]
param(
    [string]$Address,
    [string]$UserName,
    [string]$Password,
    [switch]$SelfSigned,
    [switch]$Temporary,
    [switch]$KeepExisting,
    [switch]$NoTest,
    [int]$Timeout = 5000,
    [switch]$Json,
    [switch]$Bool,
    [int]$ErrorWait = 5,
    [switch]$InstallModule,
    [switch]$AcceptLicense
)

$ErrorActionPreference = 'Stop'

function Write-Log([string]$Message, [string]$Color = 'Gray') {
    # In JSON/Bool-modus naar stderr loggen zodat stdout alleen het resultaat bevat
    if ($Json -or $Bool) { [Console]::Error.WriteLine($Message) }
    else { Write-Host $Message -ForegroundColor $Color }
}

function Exit-Result([int]$Code, [string]$Message, $Route = $null, $Test = $null) {
    $result = [ordered]@{
        success   = ($Code -eq 0)
        exitCode  = $Code
        message   = $Message
        address   = $Address
        name      = if ($Route) { "$($Route.Name)" } else { $null }
        netId     = if ($Route) { "$($Route.NetId)" } else { $null }
        tcVersion = if ($Route) { "$($Route.TcVersion)" } else { $null }
        test      = if ($Test) { "$($Test.CommandResult)" } else { $null }
    }
    if ($Bool) {
        Write-Log $Message
        [Console]::Out.WriteLine($(if ($Code -eq 0) { 'true' } else { 'false' }))
    }
    elseif ($Json) {
        [Console]::Out.WriteLine(($result | ConvertTo-Json -Compress))
    }
    else {
        Write-Log $Message $(if ($Code -eq 0) { 'Green' } else { 'Red' })
    }
    if ($Code -ne 0 -and $ErrorWait -gt 0) {
        [Console]::Error.WriteLine("Fout (exitcode $Code). Venster sluit over $ErrorWait seconden...")
        Start-Sleep -Seconds $ErrorWait
    }
    exit $Code
}

# --- Main ---------------------------------------------------------------

if (-not $Address)  { Exit-Result 1 "Geen adres opgegeven (gebruik -Address)." }
if (-not $UserName) { Exit-Result 1 "Geen gebruikersnaam opgegeven (gebruik -UserName)." }
if (-not $Password) { Exit-Result 1 "Geen wachtwoord opgegeven (gebruik -Password)." }

$securePw = ConvertTo-SecureString $Password -AsPlainText -Force
$useSsc = $SelfSigned.IsPresent

$cred = New-Object System.Management.Automation.PSCredential($UserName, $securePw)

# Module laden
function Import-TcModule {
    # Alleen de officieel geinstalleerde module (PowerShell Gallery: Install-Module TcXaeMgmt)
    Import-Module TcXaeMgmt
}

function Install-TcModule {
    Write-Log "TcXaeMgmt installeren vanaf de PowerShell Gallery..." 'Cyan'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue | Where-Object { $_.Version -ge [version]'2.8.5.201' })) {
        Write-Log "NuGet provider installeren..."
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
    }
    # Windows PowerShell 5.1 heeft standaard PowerShellGet 1.0.0.1; TcXaeMgmt vereist PowerShellGet 2.x
    $psGet = Get-Module -ListAvailable PowerShellGet | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $psGet -or $psGet.Version -lt [version]'2.0') {
        Write-Log "PowerShellGet bijwerken (huidig: $($psGet.Version))..."
        Install-Module PowerShellGet -Scope CurrentUser -Force -AllowClobber
    }
    # In een nieuw proces installeren, zodat de nieuwe PowerShellGet wordt geladen
    Write-Log "TcXaeMgmt installeren..."
    $cmd = "try { Import-Module PowerShellGet -MinimumVersion 2.0; Install-Module TcXaeMgmt -Scope CurrentUser -Force -AllowClobber -AcceptLicense -ErrorAction Stop } catch { [Console]::Error.WriteLine(`$_.Exception.Message); exit 1 }"
    $ErrorActionPreference = 'Continue'   # anders breekt stderr van het child-proces het script af (PS 5.1)
    powershell -NoProfile -ExecutionPolicy Bypass -Command $cmd 2>&1 | ForEach-Object { Write-Log "  $_" }
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0) { throw "Install-Module TcXaeMgmt mislukt (exitcode $LASTEXITCODE)." }
    Import-Module TcXaeMgmt
    Write-Log "TcXaeMgmt $((Get-Module TcXaeMgmt).Version) geinstalleerd." 'Green'
}

try {
    Import-TcModule
}
catch {
    $licenseUrl = 'https://github.com/Beckhoff/ADS/blob/master/LICENSE'
    $installHelp = @"
TcXaeMgmt module niet gevonden of kan niet worden geladen ($($_.Exception.Message)).

Installeren vanaf de PowerShell Gallery (internet nodig):
  - Automatisch: start dit script opnieuw met -InstallModule -AcceptLicense
  - Handmatig, in PowerShell:
      [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
      Install-PackageProvider NuGet -Scope CurrentUser -Force
      Install-Module PowerShellGet -Scope CurrentUser -Force -AllowClobber
    Sluit PowerShell, open een nieuw venster en voer uit:
      Install-Module TcXaeMgmt -Scope CurrentUser
    Beckhoff vereist dat je hun licentie accepteert: $licenseUrl

Let op: er moet ook een TwinCAT ADS-router op deze pc geinstalleerd zijn.
"@

    # Alleen vragen als er iemand achter het scherm zit (niet bij -Json/-Bool of aanroep door een applicatie)
    $doInstall = $InstallModule.IsPresent
    $licenseOk = $AcceptLicense.IsPresent
    $canAsk = -not ($Json -or $Bool) -and -not [Console]::IsInputRedirected -and [Environment]::UserInteractive
    if (-not $doInstall -and $canAsk) {
        Write-Log "TcXaeMgmt module is niet gevonden." 'Yellow'
        $answer = Read-Host "Wil je deze nu installeren vanaf de PowerShell Gallery? (j/n)"
        $doInstall = $answer -match '^[jy]'
    }
    if ($doInstall -and -not $licenseOk -and $canAsk) {
        Write-Log "Beckhoff vereist dat je de licentie van TcXaeMgmt accepteert:" 'Yellow'
        Write-Log "  $licenseUrl" 'Yellow'
        $answer = Read-Host "Accepteer je deze licentie? (j/n)"
        $licenseOk = $answer -match '^[jy]'
    }

    if (-not $doInstall) { Exit-Result 2 $installHelp }
    if (-not $licenseOk) { Exit-Result 2 "Licentie van Beckhoff niet geaccepteerd; module niet geinstalleerd.`n(Voor automatische installatie: -InstallModule -AcceptLicense)`n`n$installHelp" }
    try { Install-TcModule }
    catch { Exit-Result 2 "Automatisch installeren mislukt: $($_.Exception.Message)`n`n$installHelp" }
}

Write-Log "Doel: $Address  (user: $UserName$(if ($useSsc) {', SelfSigned'}))" 'Cyan'

try {
    # Oude routes naar hetzelfde IP opruimen (vorige PLC met dezelfde instellingen maar andere NetId)
    if (-not $KeepExisting) {
        $old = @(Get-AdsRoute | Where-Object { $_.Address -eq $Address -or $_.IPAddresses -contains $Address })
        foreach ($r in $old) {
            Write-Log "Oude route verwijderen: $($r.Name) ($($r.NetId))" 'Yellow'
            Remove-AdsRoute -NetId $r.NetId -Quiet | Out-Null
        }
    }

    # Nieuwe route toevoegen
    $addParams = @{
        Address    = $Address
        Credential = $cred
        Quiet      = $true
    }
    # Parameters verschillen per moduleversie (v3: -Timeout in ms; v7: -BroadcastTimeout in s en -PassThru)
    $addCmd = (Get-Command Add-AdsRoute).Parameters
    if ($addCmd.ContainsKey('BroadcastTimeout')) { $addParams.BroadcastTimeout = [int][math]::Ceiling($Timeout / 1000) }
    elseif ($addCmd.ContainsKey('Timeout'))      { $addParams.Timeout = $Timeout }
    if ($addCmd.ContainsKey('PassThru'))         { $addParams.PassThru = $true }
    if ($useSsc)    { $addParams.SelfSigned = $true }
    if ($Temporary) { $addParams.Temporary  = $true }

    Write-Log "Route toevoegen..." 'Cyan'
    $route = Add-AdsRoute @addParams | Select-Object -First 1
}
catch {
    Exit-Result 3 "Route toevoegen mislukt: $($_.Exception.Message)"
}
if (-not $route) { Exit-Result 3 "Route toevoegen mislukt: PLC niet gevonden op $Address." }

Write-Log "Route toegevoegd: $($route.Name) ($($route.NetId)), TwinCAT $($route.TcVersion)"

if ($NoTest) { Exit-Result 0 "Route naar $($route.Name) ($($route.NetId)) toegevoegd (niet getest)." $route }

Write-Log "Verbinding testen..." 'Cyan'
$testParams = @{ ErrorAction = 'SilentlyContinue' }
if ((Get-Command Test-AdsRoute).Parameters.ContainsKey('Count')) { $testParams.Count = 1 }
$test = $route | Test-AdsRoute @testParams | Select-Object -First 1
if (-not $test -or "$($test.CommandResult)" -ne 'Ok') {
    $why = if ($test -and $test.Exception) { $test.Exception.Message } else { 'geen antwoord' }
    Exit-Result 4 "Route toegevoegd, maar verbindingstest mislukt: $why" $route $test
}

Exit-Result 0 "Route naar $($route.Name) ($($route.NetId)) staat en werkt." $route $test

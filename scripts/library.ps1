param(
    [ValidateSet('Install', 'Start', 'Stop', 'Backup', 'Status')]
    [string]$Action = 'Start',
    [string]$DataPath,
    [string]$Proxy,
    [switch]$OpenBrowser
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = Split-Path -Parent $PSScriptRoot
$localRoot = Join-Path $projectRoot '.local'
$executable = Join-Path $projectRoot '.runtime\bin\filebrowser.exe'
$configPath = Join-Path $localRoot 'config.yaml'
$instancePath = Join-Path $localRoot 'instance.json'
$credentialPath = Join-Path $localRoot 'credentials.json'
$processPath = Join-Path $localRoot 'process.json'
$release = Get-Content -LiteralPath (Join-Path $projectRoot 'deployment\release.json') -Raw -Encoding UTF8 | ConvertFrom-Json

function Write-JsonFile($Value, [string]$Path) {
    $json = $Value | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding($false)))
}

function Get-LibraryInstance {
    if (-not (Test-Path -LiteralPath $instancePath)) {
        throw 'Run scripts\library.ps1 -Action Install first.'
    }
    return Get-Content -LiteralPath $instancePath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-LibraryProcess {
    if (-not (Test-Path -LiteralPath $processPath)) { return $null }
    $record = Get-Content -LiteralPath $processPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $running = Get-Process -Id $record.id -ErrorAction SilentlyContinue
    if ($null -eq $running) { return $null }
    # A PID can be reused by Windows; never stop a different process.
    if ($running.Path -ne $executable -or
        $running.StartTime.ToUniversalTime().Ticks.ToString() -ne $record.startTicks) {
        throw 'The saved process ID belongs to another process. No action was taken.'
    }
    return $running
}

function Test-LibraryHealth([string]$Url) {
    $request = [Net.HttpWebRequest]::Create($Url + '/health')
    $request.Proxy = $null
    $request.Timeout = 3000
    $request.ReadWriteTimeout = 3000
    $response = $null
    try {
        $response = $request.GetResponse()
        return [int]$response.StatusCode -eq 200
    } catch { return $false }
    finally { if ($null -ne $response) { $response.Close() } }
}

function Install-Library {
    $null = New-Item -ItemType Directory -Path (Split-Path $executable) -Force
    if (-not (Test-Path -LiteralPath $executable)) {
        $downloadPath = $executable + '.download'
        $downloadOptions = @{
            Uri = $release.url
            OutFile = $downloadPath
            UseBasicParsing = $true
            TimeoutSec = 180
        }
        if ($Proxy) { $downloadOptions.Proxy = $Proxy }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest @downloadOptions
        if ((Get-FileHash -LiteralPath $downloadPath -Algorithm SHA256).Hash -ne $release.sha256) {
            throw 'Release checksum mismatch. The downloaded file was not executed.'
        }
        Move-Item -LiteralPath $downloadPath -Destination $executable
    }
    if ((Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash -ne $release.sha256) {
        throw 'Installed binary checksum mismatch. Existing files were not replaced.'
    }
    if (Test-Path -LiteralPath $instancePath) {
        Write-Host 'Already configured. Existing files and account were preserved.'
        return
    }
    if (-not $DataPath) {
        $DataPath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'BeigerLibrary'
    }
    $DataPath = [IO.Path]::GetFullPath($DataPath)
    if (Test-Path -LiteralPath $DataPath) {
        throw 'Choose a new, empty data directory to avoid importing unrelated files.'
    }
    $null = New-Item -ItemType Directory -Path $DataPath
    foreach ($folder in @($localRoot, (Join-Path $localRoot 'state'), (Join-Path $localRoot 'cache'), (Join-Path $localRoot 'logs'))) {
        $null = New-Item -ItemType Directory -Path $folder -Force
    }
    $categories = Get-Content -LiteralPath (Join-Path $projectRoot 'deployment\categories.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($category in $categories) {
        $null = New-Item -ItemType Directory -Path (Join-Path $DataPath $category)
    }

    $settings = Get-Content -LiteralPath (Join-Path $projectRoot 'deployment\config.template.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $settings.server.database = Join-Path $localRoot 'state\database.db'
    $settings.server.cacheDir = Join-Path $localRoot 'cache'
    $settings.server.sources[0].path = $DataPath
    # JSON is valid YAML, and preserves Windows paths and Unicode without templating.
    Write-JsonFile $settings $configPath
    $randomBytes = New-Object byte[] 18
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $random.GetBytes($randomBytes) } finally { $random.Dispose() }
    $password = [Convert]::ToBase64String($randomBytes).Replace('+', '-').Replace('/', '_')
    $instance = [ordered]@{
        url = 'http://127.0.0.1:' + $settings.server.port
        port = $settings.server.port
        dataPath = $DataPath
        backupRoot = $DataPath + '-Backups'
        version = $release.version
    }
    Write-JsonFile ([ordered]@{username = 'library'; password = $password; url = $instance.url}) $credentialPath
    Write-JsonFile $instance $instancePath
    Write-Host ('Installed ' + $release.version + '. Data directory: ' + $DataPath)
    Write-Host ('Local login details: ' + $credentialPath)
}

function Start-Library {
    $instance = Get-LibraryInstance
    $running = Get-LibraryProcess
    if ($null -ne $running) {
        if (-not (Test-LibraryHealth $instance.url)) { throw 'Library process is running but not responding. Check .local\logs.' }
        Write-Host ('Already running: ' + $instance.url)
        return
    }
    if (-not (Test-Path -LiteralPath $instance.dataPath)) {
        throw 'The data directory is missing. Restore it before starting the library.'
    }
    $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $instance.port -ErrorAction SilentlyContinue)
    if ($listeners.Count -gt 0) { throw ('Port ' + $instance.port + ' is already in use. No process was stopped.') }
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($config.server.listen -notin @('127.0.0.1', '0.0.0.0')) { throw 'config.yaml listen must be 127.0.0.1 or 0.0.0.0.' }
    if ($config.server.port -ne $instance.port) { throw 'config.yaml and instance.json ports must match.' }
    if ($config.server.sources.Count -ne 1 -or $config.server.sources[0].path -ne $instance.dataPath) {
        throw 'The configured source no longer matches the backed-up library directory.'
    }
    $oldAdminPassword = [Environment]::GetEnvironmentVariable('FILEBROWSER_ADMIN_PASSWORD', 'Process')
    try {
        if (-not (Test-Path -LiteralPath $config.server.database)) {
            $credentials = Get-Content -LiteralPath $credentialPath -Raw -Encoding UTF8 | ConvertFrom-Json
            [Environment]::SetEnvironmentVariable('FILEBROWSER_ADMIN_PASSWORD', $credentials.password, 'Process')
        }
        $running = Start-Process -FilePath $executable -ArgumentList @('-c', ('"' + $configPath + '"')) `
            -WorkingDirectory $localRoot -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput (Join-Path $localRoot 'logs\server.log') `
            -RedirectStandardError (Join-Path $localRoot 'logs\server-error.log')
    } finally {
        [Environment]::SetEnvironmentVariable('FILEBROWSER_ADMIN_PASSWORD', $oldAdminPassword, 'Process')
    }
    Write-JsonFile ([ordered]@{id = $running.Id; startTicks = $running.StartTime.ToUniversalTime().Ticks.ToString()}) $processPath
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        $running.Refresh()
        if ($running.HasExited) { throw 'Library startup failed. See .local\logs\server.log and server-error.log.' }
        if (Test-LibraryHealth $instance.url) {
            Write-Host ('Running: ' + $instance.url)
            return
        }
        Start-Sleep -Milliseconds 500
    }
    throw 'Library did not become ready. See .local\logs.'
}

function Stop-Library {
    $running = Get-LibraryProcess
    if ($null -eq $running) {
        Write-Host 'Library is already stopped.'
        return
    }
    Stop-Process -InputObject $running
    if (-not $running.WaitForExit(10000)) { throw 'Could not stop the library for backup.' }
    Write-Host 'Library stopped. Files are preserved.'
}

function Backup-Library {
    $instance = Get-LibraryInstance
    $wasRunning = $null -ne (Get-LibraryProcess)
    $snapshotName = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 6)
    $snapshot = Join-Path $instance.backupRoot $snapshotName
    try {
        if ($wasRunning) { Stop-Library }
        $null = New-Item -ItemType Directory -Path $snapshot
        Copy-Item -LiteralPath $instance.dataPath -Destination (Join-Path $snapshot 'materials') -Recurse -Force
        Copy-Item -LiteralPath (Join-Path $localRoot 'state') -Destination (Join-Path $snapshot 'state') -Recurse -Force
        foreach ($file in @($configPath, $instancePath, $credentialPath)) {
            Copy-Item -LiteralPath $file -Destination $snapshot
        }
        Copy-Item -LiteralPath (Join-Path $projectRoot 'deployment\release.json') -Destination $snapshot
        Write-JsonFile ([ordered]@{createdAt = (Get-Date).ToUniversalTime().ToString('o'); complete = $true; originalDataPath = $instance.dataPath}) (Join-Path $snapshot 'backup.json')
        Write-Host ('Backup complete: ' + $snapshot)
    } finally {
        if ($wasRunning) { Start-Library }
    }
}

switch ($Action) {
    'Install' { Install-Library }
    'Start' { Start-Library }
    'Stop' { Stop-Library }
    'Backup' { Backup-Library }
    'Status' {
        $instance = Get-LibraryInstance
        [pscustomobject]@{url = $instance.url; running = ($null -ne (Get-LibraryProcess)); healthy = (Test-LibraryHealth $instance.url); dataPath = $instance.dataPath}
    }
}
if ($OpenBrowser -and $Action -eq 'Start') {
    Start-Process (Get-LibraryInstance).url
}

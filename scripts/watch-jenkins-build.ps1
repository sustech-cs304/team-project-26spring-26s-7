param(
    [Parameter(Mandatory = $true)]
    [string]$BaseUrl,

    [Parameter(Mandatory = $true)]
    [string]$JobName,

    [Parameter(Mandatory = $true)]
    [string]$Username,

    [Parameter(Mandatory = $true)]
    [string]$ApiToken,

    [string]$LogDir = '.ci-logs',
    [string]$MetadataPath,
    [int]$PollIntervalSeconds = 2,
    [int]$TimeoutSeconds = 1800
)

$ErrorActionPreference = 'Stop'

function Write-Status {
    param([string]$Message)
    Write-Host "[jenkins] $Message"
}

function Get-BasicAuthHeader {
    param(
        [string]$User,
        [string]$Token
    )

    $bytes = [System.Text.Encoding]::ASCII.GetBytes("${User}:${Token}")
    return @{
        Authorization = 'Basic ' + [Convert]::ToBase64String($bytes)
    }
}

function Resolve-LogDirectory {
    param([string]$Directory)

    if ([System.IO.Path]::IsPathRooted($Directory)) {
        return $Directory
    }

    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
    return Join-Path $repoRoot $Directory
}

function Resolve-OptionalFilePath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
    return Join-Path $repoRoot $Path
}

function Normalize-ConsoleText {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) {
        return $Text
    }

    $escape = [char]27
    $textWithoutNotes = [regex]::Replace(
        $Text,
        [regex]::Escape("$escape[8mha:") + '.*?' + [regex]::Escape("$escape[0m"),
        '',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    return [regex]::Replace($textWithoutNotes, [regex]::Escape("$escape[") + '[0-9;]*[A-Za-z]', '')
}

function Start-JenkinsBuild {
    param(
        [string]$Url,
        [string]$User,
        [string]$Token
    )

    $headerOutput = & curl.exe -s -D - -o NUL -X POST $Url --user "${User}:${Token}"

    if ($LASTEXITCODE -ne 0) {
        throw "curl.exe failed to trigger Jenkins build at $Url."
    }

    $locationHeader = $headerOutput |
        Select-String -Pattern '^Location:\s*(.+)$' |
        Select-Object -First 1

    if (-not $locationHeader) {
        throw 'Jenkins did not return a queue item location header.'
    }

    return $locationHeader.Matches[0].Groups[1].Value.Trim()
}

$headers = Get-BasicAuthHeader -User $Username -Token $ApiToken
$jobPath = (($JobName -split '/') | ForEach-Object { "job/$_" }) -join '/'
$jobUrl = ($BaseUrl.TrimEnd('/') + '/' + $jobPath).TrimEnd('/')
$queueApiUrl = $null
$buildApiUrl = $null
$buildUrl = $null
$buildNumber = $null
$logOffset = 0
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$lastQueueMessage = $null
$lastBuildState = $null
$logRoot = Resolve-LogDirectory -Directory $LogDir
$resolvedMetadataPath = Resolve-OptionalFilePath -Path $MetadataPath
$sessionLogPath = Join-Path $logRoot 'session.log'

New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
[System.IO.File]::WriteAllText(
    $sessionLogPath,
    @(
        "Jenkins job: $JobName"
        "Base URL: $BaseUrl"
        "Session started at: $(Get-Date -Format o)"
        'Status: initializing'
        ''
    ) -join [Environment]::NewLine
)

Write-Status "Triggering Jenkins job '$JobName' at $jobUrl"
Add-Content -Path $sessionLogPath -Value "Status: triggering build request" -Encoding UTF8
$queueLocation = Start-JenkinsBuild -Url "$jobUrl/build" -User $Username -Token $ApiToken

if ($queueLocation.StartsWith('/')) {
    $queueLocation = $BaseUrl.TrimEnd('/') + $queueLocation
}

$queueApiUrl = $queueLocation.TrimEnd('/') + '/api/json'
Write-Status "Queued build: $queueLocation"
Add-Content -Path $sessionLogPath -Value "Queue location: $queueLocation" -Encoding UTF8

while (-not $buildNumber) {
    if ((Get-Date) -gt $deadline) {
        throw "Timed out waiting for Jenkins queue item to start after $TimeoutSeconds seconds."
    }

    $queueItem = Invoke-RestMethod -Uri $queueApiUrl -Headers $headers

    if ($queueItem.cancelled) {
        throw 'Jenkins queue item was cancelled before execution.'
    }

    if ($queueItem.executable -and $queueItem.executable.number) {
        $buildNumber = [int]$queueItem.executable.number
        $buildUrl = $queueItem.executable.url.TrimEnd('/')
        $buildApiUrl = "$buildUrl/api/json"
        break
    }

    if ($queueItem.why -and $queueItem.why -ne $lastQueueMessage) {
        Write-Status "Waiting in queue: $($queueItem.why)"
        $lastQueueMessage = $queueItem.why
    }

    Start-Sleep -Seconds $PollIntervalSeconds
}

$safeJobName = ($JobName -replace '[^A-Za-z0-9._-]', '_')
$logPath = Join-Path $logRoot ("jenkins-{0}-build-{1}.log" -f $safeJobName, $buildNumber)
$header = @(
    "Jenkins job: $JobName"
    "Build URL: $buildUrl"
    "Started at: $(Get-Date -Format o)"
    ''
) -join [Environment]::NewLine
[System.IO.File]::WriteAllText($logPath, $header)
Add-Content -Path $sessionLogPath -Value "Build number: $buildNumber" -Encoding UTF8
Add-Content -Path $sessionLogPath -Value "Build log: $logPath" -Encoding UTF8

if ($resolvedMetadataPath) {
    $metadataDir = Split-Path -Parent $resolvedMetadataPath
    if ($metadataDir) {
        New-Item -ItemType Directory -Force -Path $metadataDir | Out-Null
    }

    [pscustomobject]@{
        jobName = $JobName
        buildNumber = $buildNumber
        buildUrl = $buildUrl
        logPath = $logPath
        generatedAt = (Get-Date -Format o)
    } | ConvertTo-Json | Set-Content -Path $resolvedMetadataPath -Encoding UTF8
}

Write-Status "Streaming build #$buildNumber"
Write-Status "Log file: $logPath"
Add-Content -Path $sessionLogPath -Value "Status: streaming build output" -Encoding UTF8

while ($true) {
    if ((Get-Date) -gt $deadline) {
        throw "Timed out waiting for Jenkins build #$buildNumber to finish after $TimeoutSeconds seconds."
    }

    $progressUrl = "$buildUrl/logText/progressiveText?start=$logOffset"
    $progressResponse = Invoke-WebRequest -Uri $progressUrl -Headers $headers -UseBasicParsing
    $content = Normalize-ConsoleText -Text $progressResponse.Content

    if ($content) {
        [Console]::Out.Write($content)
        Add-Content -Path $logPath -Value $content -Encoding UTF8
    }

    $textSize = $progressResponse.Headers['X-Text-Size']
    if ($textSize) {
        $logOffset = [int]$textSize
    } else {
        $logOffset += $content.Length
    }

    $moreData = $progressResponse.Headers['X-More-Data']
    if ($moreData -eq 'true') {
        Start-Sleep -Seconds $PollIntervalSeconds
        continue
    }

    $buildInfo = Invoke-RestMethod -Uri $buildApiUrl -Headers $headers
    $stateLabel = if ($buildInfo.building) { 'building' } else { $buildInfo.result }

    if ($stateLabel -and $stateLabel -ne $lastBuildState) {
        Write-Status "Build state: $stateLabel"
        $lastBuildState = $stateLabel
    }

    if ($buildInfo.building) {
        Start-Sleep -Seconds $PollIntervalSeconds
        continue
    }

    Write-Status "Build #$buildNumber finished with status $($buildInfo.result)"
    Add-Content -Path $sessionLogPath -Value "Finished at: $(Get-Date -Format o)" -Encoding UTF8
    Add-Content -Path $sessionLogPath -Value "Result: $($buildInfo.result)" -Encoding UTF8

    if ($buildInfo.result -ne 'SUCCESS') {
        exit 1
    }

    exit 0
}

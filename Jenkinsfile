pipeline {
    agent any

    options {
        skipDefaultCheckout(true)
        skipStagesAfterUnstable()
        timeout(time: 30, unit: 'MINUTES')
    }

    environment {
        DEVECO_SDK_HOME = 'C:\\Apps\\DevEco Studio\\sdk'
        DEVECO_NODE = 'C:\\Apps\\DevEco Studio\\tools\\node\\node.exe'
        DEVECO_OHPM = 'C:\\Apps\\DevEco Studio\\tools\\ohpm\\bin\\ohpm.bat'
        LOCAL_ARTIFACT_ROOT_DEFAULT = 'D:\\Mydata\\1University\\3Junior\\Software_Engineering\\project\\frontendv1\\team-project-26spring-26s-7\\ci-artifacts'
        ANSI_RESET = '[0m'
        ANSI_GREEN = '[32m'
        ANSI_RED = '[31m'
        ANSI_YELLOW = '[33m'
        ANSI_CYAN = '[36m'
    }

    stages {
        stage('Checkout') {
            steps {
                script {
                    echo ''
                    echo '╔════════════════════════════════════════════════════════════════╗'
                    echo '║                   Stage: Checkout                            ║'
                    echo '╚════════════════════════════════════════════════════════════════╝'
                    echo ''
                    checkout scm
                }
            }
            post {
                success {
                    script {
                        echo ''
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo "${ANSI_GREEN}✓ CHECKOUT COMPLETED SUCCESSFULLY${ANSI_RESET}"
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo ''
                    }
                }
                failure {
                    script {
                        echo ''
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo "${ANSI_RED}✗ CHECKOUT FAILED${ANSI_RESET}"
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo ''
                    }
                }
            }
        }

        stage('Prepare Outputs') {
            steps {
                script {
                    echo ''
                    echo '╔════════════════════════════════════════════════════════════════╗'
                    echo '║               Stage: Prepare Outputs                         ║'
                    echo '╚════════════════════════════════════════════════════════════════╝'
                    echo ''
                    def artifactRoot = env.LOCAL_ARTIFACT_ROOT?.trim()
                    if (!artifactRoot) {
                        artifactRoot = env.LOCAL_ARTIFACT_ROOT_DEFAULT
                    }
                    env.CI_OUTPUT_DIR = "${artifactRoot}\\build-${env.BUILD_NUMBER}"
                    echo "Output directory: ${env.CI_OUTPUT_DIR}"
                    echo ''
                    powershell '''
                        $dirs = @(
                          $env:CI_OUTPUT_DIR,
                          (Join-Path $env:CI_OUTPUT_DIR 'logs'),
                          (Join-Path $env:CI_OUTPUT_DIR 'reports'),
                          (Join-Path $env:CI_OUTPUT_DIR 'packages'),
                          (Join-Path $env:CI_OUTPUT_DIR 'metrics'),
                          (Join-Path $env:CI_OUTPUT_DIR 'meta')
                        )
                        foreach ($dir in $dirs) {
                          New-Item -ItemType Directory -Path $dir -Force | Out-Null
                        }

                        @"
Job Name: $env:JOB_NAME
Build Number: $env:BUILD_NUMBER
Build URL: $env:BUILD_URL
Workspace: $env:WORKSPACE
Git Branch: $env:GIT_BRANCH
Started At: $(Get-Date -Format o)
"@ | Set-Content -Path (Join-Path $env:CI_OUTPUT_DIR 'meta\\build-info.txt') | Out-Null
                    '''
                }
            }
            post {
                success {
                    script {
                        echo ''
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo "${ANSI_GREEN}✓ OUTPUT DIRECTORIES PREPARED SUCCESSFULLY${ANSI_RESET}"
                        echo "${ANSI_GREEN}  Location: ${env.CI_OUTPUT_DIR}${ANSI_RESET}"
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo ''
                    }
                }
                failure {
                    script {
                        echo ''
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo "${ANSI_RED}✗ OUTPUT PREPARATION FAILED${ANSI_RESET}"
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo ''
                    }
                }
            }
        }

        stage('Clean') {
            steps {
                script {
                    echo ''
                    echo '╔════════════════════════════════════════════════════════════════╗'
                    echo '║                    Stage: Clean                               ║'
                    echo '╚════════════════════════════════════════════════════════════════╝'
                    echo ''
                    dir('frontend') {
                        bat '''
                            if exist entry\\build rmdir /s /q entry\\build
                            if exist .hvigor rmdir /s /q .hvigor
                            if exist oh_modules rmdir /s /q oh_modules
                            if exist entry\\oh_modules rmdir /s /q entry\\oh_modules
                        '''
                    }
                }
            }
            post {
                success {
                    script {
                        echo ''
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo "${ANSI_GREEN}✓ CLEAN COMPLETED SUCCESSFULLY${ANSI_RESET}"
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo ''
                    }
                }
                failure {
                    script {
                        echo ''
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo "${ANSI_RED}✗ CLEAN FAILED${ANSI_RESET}"
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo ''
                    }
                }
            }
        }

        stage('Install Dependencies') {
            steps {
                script {
                    echo ''
                    echo '╔════════════════════════════════════════════════════════════════╗'
                    echo '║            Stage: Install Dependencies                       ║'
                    echo '╚════════════════════════════════════════════════════════════════╝'
                    echo ''
                    dir('frontend') {
                        bat '''
                            @echo off
                            call "%DEVECO_OHPM%" install > "%CI_OUTPUT_DIR%\\logs\\install-dependencies.log" 2>&1
                            set "stage_exit=%ERRORLEVEL%"
                            findstr /V /I /C:"ArkTS:WARN" /C:"Warning:" /C:"Switching off type checks" /C:"Function may throw exceptions" /C:"has been deprecated" /C:"is not supported on all devices" "%CI_OUTPUT_DIR%\\logs\\install-dependencies.log"
                            exit /b %stage_exit%
                        '''
                    }
                }
            }
            post {
                success {
                    script {
                        echo ''
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo "${ANSI_GREEN}✓ DEPENDENCIES INSTALLED SUCCESSFULLY${ANSI_RESET}"
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo ''
                    }
                }
                failure {
                    script {
                        echo ''
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo "${ANSI_RED}✗ DEPENDENCY INSTALLATION FAILED${ANSI_RESET}"
                        echo "${ANSI_YELLOW}  Check log: ${env.CI_OUTPUT_DIR}\\logs\\install-dependencies.log${ANSI_RESET}"
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo ''
                    }
                }
            }
        }

        stage('Compile') {
            steps {
                script {
                    echo ''
                    echo '╔════════════════════════════════════════════════════════════════╗'
                    echo '║                    Stage: Compile                             ║'
                    echo '╚════════════════════════════════════════════════════════════════╝'
                    echo ''
                    dir('frontend') {
                        bat '''
                            @echo off
                            powershell -NoProfile -ExecutionPolicy Bypass -File build.ps1 --mode module -p module=entry@default assembleHap > "%CI_OUTPUT_DIR%\\logs\\compile.log" 2>&1
                            set "stage_exit=%ERRORLEVEL%"
                            findstr /V /I /C:"ArkTS:WARN" /C:"Warning:" /C:"Switching off type checks" /C:"Function may throw exceptions" /C:"has been deprecated" /C:"is not supported on all devices" /C:"@Entry decorator" "%CI_OUTPUT_DIR%\\logs\\compile.log"
                            exit /b %stage_exit%
                        '''
                    }
                }
            }
            post {
                success {
                    script {
                        echo ''
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo "${ANSI_GREEN}✓ COMPILATION COMPLETED SUCCESSFULLY${ANSI_RESET}"
                        echo "${ANSI_GREEN}  HAP package generated${ANSI_RESET}"
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo ''
                    }
                }
                failure {
                    script {
                        echo ''
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo "${ANSI_RED}✗ COMPILATION FAILED${ANSI_RESET}"
                        echo "${ANSI_YELLOW}  Check log: ${env.CI_OUTPUT_DIR}\\logs\\compile.log${ANSI_RESET}"
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo ''
                    }
                }
            }
        }

        stage('Test') {
            steps {
                script {
                    echo ''
                    echo '╔════════════════════════════════════════════════════════════════╗'
                    echo '║                     Stage: Test                               ║'
                    echo '╚════════════════════════════════════════════════════════════════╝'
                    echo ''
                    dir('frontend') {
                        bat '''
                            @echo off
                            powershell -NoProfile -ExecutionPolicy Bypass -File build.ps1 test > "%CI_OUTPUT_DIR%\\logs\\test.log" 2>&1
                            set "stage_exit=%ERRORLEVEL%"
                            findstr /V /I /C:"ArkTS:WARN" /C:"Warning:" /C:"Switching off type checks" /C:"Function may throw exceptions" /C:"has been deprecated" /C:"is not supported on all devices" /C:"@Entry decorator" "%CI_OUTPUT_DIR%\\logs\\test.log"
                            exit /b %stage_exit%
                        '''
                    }
                }
            }
            post {
                always {
                    script {
                        echo ''
                        echo '------------------------------------------------------------'
                        echo '  Collecting and Processing Test Reports'
                        echo '------------------------------------------------------------'
                        echo ''
                        dir('frontend/entry/.test/default/intermediates/test/coverage_data') {
                            powershell '''
                                $resultFile = "test_result.txt"
                                if (Test-Path $resultFile) {
                                    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
                                    Write-Host "║                      TEST RESULTS                             ║" -ForegroundColor Cyan
                                    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

                                    $lines = Get-Content $resultFile | Where-Object {
                                        $_ -notmatch "@Entry decorator" -and
                                        $_ -notmatch "recommended way to export struct" -and
                                        $_ -notmatch "ACE Engine error in component preview"
                                    }
                                    $currentClass = ""
                                    $totalTests = 0
                                    $passedTests = 0
                                    $failedTests = 0
                                    foreach ($line in $lines) {
                                        if ($line -match '^class=(.+)$') {
                                            if ($currentClass -ne "") { Write-Host "" }
                                            $currentClass = $matches[1]
                                            Write-Host "  [$currentClass]" -ForegroundColor Yellow
                                        } elseif ($line -match '^test=(.+)$') {
                                            $testName = $matches[1]
                                        } elseif ($line -match '^result=(.+)$') {
                                            $result = $matches[1]
                                            $totalTests++
                                            if ($result -eq "Success") { $passedTests++ } else { $failedTests++ }
                                            $color = if ($result -eq "Success") { "Green" } else { "Red" }
                                            Write-Host "    [$testName]: $result" -ForegroundColor $color
                                        } elseif ($line -match '^Tests run:') {
                                            Write-Host ""
                                            Write-Host "  $line" -ForegroundColor Cyan
                                        }
                                    }
                                    Write-Host ""
                                    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
                                    Write-Host "║                     END TEST RESULTS                          ║" -ForegroundColor Cyan
                                    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
                                } else {
                                    Write-Host "WARNING: test_result.txt not found - tests may not have run" -ForegroundColor Yellow
                                }
                            '''
                        }
                        dir('frontend/entry/.test/default/outputs/test') {
                            archiveArtifacts artifacts: 'reports/**', allowEmptyArchive: true
                            powershell '''
                                $sourceRoot = (Get-Location).Path
                                $reportRoot = Join-Path $env:CI_OUTPUT_DIR 'reports\\test'
                                New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null
                                Copy-Item -Path (Join-Path $sourceRoot 'reports\\*') -Destination $reportRoot -Recurse -Force -ErrorAction SilentlyContinue
                            '''
                        }
                        dir('frontend/entry/.test/default/intermediates/test') {
                            archiveArtifacts artifacts: '*.json, coverage_data/**', allowEmptyArchive: true
                            powershell '''
                                $sourceRoot = (Get-Location).Path
                                $coverageRoot = Join-Path $env:CI_OUTPUT_DIR 'reports\\coverage'
                                New-Item -ItemType Directory -Path $coverageRoot -Force | Out-Null
                                Get-ChildItem -Path $sourceRoot -File -Filter *.json -ErrorAction SilentlyContinue | ForEach-Object {
                                  Copy-Item $_.FullName (Join-Path $coverageRoot $_.Name) -Force -ErrorAction SilentlyContinue | Out-Null
                                }
                                if (Test-Path (Join-Path $sourceRoot 'coverage_data')) {
                                  Copy-Item -Path (Join-Path $sourceRoot 'coverage_data') -Destination $coverageRoot -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
                                }
                            '''
                        }
                    }
                }
                success {
                    script {
                        echo ''
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo "${ANSI_GREEN}✓ TESTS PASSED${ANSI_RESET}"
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo ''
                    }
                }
                failure {
                    script {
                        echo ''
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo "${ANSI_RED}✗ TESTS FAILED${ANSI_RESET}"
                        echo "${ANSI_YELLOW}  Check test results above for details${ANSI_RESET}"
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo ''
                    }
                }
            }
        }

        stage('Archive') {
            steps {
                script {
                    echo ''
                    echo '╔════════════════════════════════════════════════════════════════╗'
                    echo '║                    Stage: Archive                             ║'
                    echo '╚════════════════════════════════════════════════════════════════╝'
                    echo ''
                    dir('frontend/entry/build/default/outputs/default') {
                        archiveArtifacts artifacts: '*.hap', fingerprint: true
                        powershell '''
                            $packageRoot = Join-Path $env:CI_OUTPUT_DIR 'packages'
                            Get-ChildItem -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -eq '.hap' -or $_.Name -eq 'pack.info' } | ForEach-Object {
                              Copy-Item $_.FullName (Join-Path $packageRoot $_.Name) -Force -ErrorAction SilentlyContinue | Out-Null
                            }
                        '''
                    }
                }
            }
            post {
                success {
                    script {
                        echo ''
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo "${ANSI_GREEN}✓ ARTIFACTS ARCHIVED SUCCESSFULLY${ANSI_RESET}"
                        echo "${ANSI_GREEN}  Location: ${env.CI_OUTPUT_DIR}\\packages${ANSI_RESET}"
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo ''
                    }
                }
                failure {
                    script {
                        echo ''
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo "${ANSI_RED}✗ ARCHIVE FAILED${ANSI_RESET}"
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo ''
                    }
                }
            }
        }

        stage('Metrics') {
            steps {
                script {
                    echo ''
                    echo '╔════════════════════════════════════════════════════════════════╗'
                    echo '║               Stage: Collect Metrics                          ║'
                    echo '╚════════════════════════════════════════════════════════════════╝'
                    echo ''
                    dir('frontend/entry/src/main/ets') {
                        powershell '''
                            $ErrorActionPreference = 'Continue'
                            $metricsPath = Join-Path $env:CI_OUTPUT_DIR 'metrics\\summary.txt'
                            $sourceFiles = Get-ChildItem -Recurse -File -Filter *.ets
                            $fileCount = $sourceFiles.Count

                            # --- lizard for NLOC only ---
                            $lizardNloc = 0
                            $hasLizard = $false
                            try {
                                pip install lizard 2>&1 | Out-Null
                                $lizardRaw = python -m lizard $sourceFiles.FullName --language ts 2>&1 | Out-String
                                if ($lizardRaw -match 'Total nloc') { $hasLizard = $true }
                            } catch { $hasLizard = $false }
                            if ($hasLizard) {
                                foreach ($line in ($lizardRaw -split '\\r?\\n')) {
                                    if ($line -match '^\\s*(\\d+)\\s+\\S+\\s+\\S+\\s+\\S+\\s+\\d+\\s+.*\\.ets$' -and $line -notmatch '@') {
                                        $lizardNloc += [int]$Matches[1]
                                    }
                                }
                            }

                            # --- Helper: strip comments and string literals ---
                            function Strip-CommentsAndStrings {
                                param([string]$Text)
                                $t = [regex]::Replace($Text, '//.*', '')
                                $t = [regex]::Replace($t, '/\\*[\\s\\S]*?\\*/', '')
                                $t = [regex]::Replace($t, "\\'[^']*\\'", '')
                                $t = [regex]::Replace($t, '"(?:[^"\\\\]|\\\\.)*"', '')
                                $t = [regex]::Replace($t, '`(?:[^`\\\\]|\\\\.)*`', '')
                                return $t
                            }

                            # --- Helper: find matching } for a { at $OpenPos, skipping strings/comments ---
                            function Find-MatchingBrace {
                                param([string]$Text, [int]$OpenPos)
                                $depth = 0
                                $i = $OpenPos
                                $len = $Text.Length
                                while ($i -lt $len) {
                                    $c = $Text[$i]
                                    if ($c -eq '\\"' -or $c -eq "\\'") { $i += 2; continue }
                                    if ($c -eq '"' -or $c -eq "'") {
                                        $q = $c; $i++
                                        while ($i -lt $len -and $Text[$i] -ne $q) {
                                            if ($Text[$i] -eq '\\') { $i++ }
                                            $i++
                                        }
                                        $i++; continue
                                    }
                                    if ($c -eq '`') {
                                        $i++
                                        while ($i -lt $len -and $Text[$i] -ne '`') {
                                            if ($Text[$i] -eq '\\') { $i++ }
                                            $i++
                                        }
                                        $i++; continue
                                    }
                                    if ($c -eq '/' -and ($i+1) -lt $len -and $Text[$i+1] -eq '/') {
                                        while ($i -lt $len -and $Text[$i] -ne "`n") { $i++ }
                                        continue
                                    }
                                    if ($c -eq '/' -and ($i+1) -lt $len -and $Text[$i+1] -eq '*') {
                                        $i += 2
                                        while ($i -lt $len -and -not ($Text[$i] -eq '*' -and ($i+1) -lt $len -and $Text[$i+1] -eq '/')) { $i++ }
                                        $i += 2; continue
                                    }
                                    if ($c -eq '{') { $depth++ }
                                    elseif ($c -eq '}') {
                                        $depth--
                                        if ($depth -eq 0) { return $i }
                                    }
                                    $i++
                                }
                                return -1
                            }

                            # --- Helper: count decision points in stripped text ---
                            function Get-DecisionPoints {
                                param([string]$Text)
                                $dp = 0
                                $dp += ([regex]::Matches($Text, '\\bif\\b')).Count
                                $dp += ([regex]::Matches($Text, '\\bfor\\b')).Count
                                $dp += ([regex]::Matches($Text, '\\bwhile\\b')).Count
                                $dp += ([regex]::Matches($Text, '\\bcatch\\b')).Count
                                $dp += ([regex]::Matches($Text, '\\bcase\\b')).Count
                                $dp += ([regex]::Matches($Text, '(?<!\\?)\\?(?![.?])')).Count
                                $dp += ([regex]::Matches($Text, '&&|\\|\\|')).Count
                                return $dp
                            }

                            # --- Per-function and per-file analysis ---
                            $controlFlowKw = @('if','for','while','switch','catch','class','struct','interface','enum','constructor','return','throw','new','typeof','instanceof','delete','void','with')
                            $lifecycleMethods = @('build','aboutToAppear','aboutToDisappear','onPageShow','onPageHide','onBackPress','onActive','onInactive','onDestroy')
                            $declPattern = '(?m)^\\s*(?:@\\w+\\s*)?(?:(?:private|public|protected)\\s+)?(?:static\\s+)?(?:async\\s+)?(\\w+)\\s*\\('

                            $totalLoc = 0
                            $allFunctions = @()
                            $fileDetails = @()

                            foreach ($file in $sourceFiles) {
                                $raw = Get-Content -Path $file.FullName -Raw -Encoding UTF8
                                if (-not $raw) { continue }
                                $lineCount = ($raw -split '\\r?\\n').Count
                                $totalLoc += $lineCount
                                $relPath = $file.FullName.Replace("$PWD\\", '')

                                # File-level CCN
                                $stripped = Strip-CommentsAndStrings $raw
                                $fileDp = Get-DecisionPoints $stripped
                                $fileCc = 1 + $fileDp
                                $fileDetails += [pscustomobject]@{
                                    File = $relPath
                                    TotalLines = $lineCount
                                    Complexity = $fileCc
                                }

                                # Function-level CCN via brace matching
                                $funcMatches = [regex]::Matches($raw, $declPattern)
                                foreach ($fm in $funcMatches) {
                                    $fnName = $fm.Groups[1].Value
                                    if ($fnName -in $controlFlowKw) { continue }

                                    # Distinguish real methods from ArkUI component calls
                                    $matchText = $fm.Value
                                    $hasModifier = $matchText -match '(?:private|public|protected|static|async)\\s'
                                    $hasReturnType = $false
                                    $hasDecorator = $matchText -match '@\\w+\\s'
                                    $searchFrom = $fm.Index + $fm.Length
                                    $openBrace = $raw.IndexOf('{', $searchFrom)
                                    if ($openBrace -gt $fm.Index) {
                                        $sigText = $raw.Substring($fm.Index, $openBrace - $fm.Index + 1)
                                        $hasReturnType = $sigText -match '\\)\\s*:\\s*\\S'
                                    }
                                    if (-not $hasModifier -and -not $hasReturnType -and -not $hasDecorator -and $fnName -notin $lifecycleMethods) {
                                        continue
                                    }

                                    if ($openBrace -eq -1) { continue }
                                    $matchLineNum = ($raw.Substring(0, $fm.Index) -split '\\r?\\n').Count
                                    $braceLineNum = ($raw.Substring(0, $openBrace) -split '\\r?\\n').Count
                                    if ([math]::Abs($braceLineNum - $matchLineNum) -gt 2) { continue }
                                    $between = $raw.Substring($fm.Index, [math]::Min($openBrace - $fm.Index + 1, $raw.Length - $fm.Index))
                                    if ($between.Contains(';')) { continue }

                                    $closeBrace = Find-MatchingBrace $raw $openBrace
                                    if ($closeBrace -eq -1) { continue }

                                    $body = $raw.Substring($openBrace, $closeBrace - $openBrace + 1)
                                    $strippedBody = Strip-CommentsAndStrings $body
                                    $fnDp = Get-DecisionPoints $strippedBody
                                    $fnCc = 1 + $fnDp

                                    $startLine = ($raw.Substring(0, $openBrace) -split '\\r?\\n').Count
                                    $endLine = ($raw.Substring(0, $closeBrace + 1) -split '\\r?\\n').Count
                                    $fnNloc = ($strippedBody -split '\\r?\\n' | Where-Object { $_.Trim() -ne '' }).Count

                                    $allFunctions += [pscustomobject]@{
                                        Name = $fnName
                                        CCN = $fnCc
                                        NLOC = $fnNloc
                                        StartLine = $startLine
                                        EndLine = $endLine
                                        File = $relPath
                                    }
                                }
                            }

                            $totalFileCcn = ($fileDetails | Measure-Object -Property Complexity -Sum).Sum
                            $avgFileCcn = if ($fileCount -gt 0) { [math]::Round($totalFileCcn / $fileCount, 1) } else { 0 }
                            $hotFiles = $fileDetails | Sort-Object Complexity -Descending | Select-Object -First 10

                            $totalFnCcn = ($allFunctions | Measure-Object -Property CCN -Sum).Sum
                            $fnCount = $allFunctions.Count
                            $avgFnCcn = if ($fnCount -gt 0) { [math]::Round($totalFnCcn / $fnCount, 2) } else { 0 }
                            $hotFns = $allFunctions | Sort-Object CCN -Descending | Select-Object -First 10

                            # --- Collect dependencies ---
                            $feRuntime = [System.Collections.Generic.List[string]]::new()
                            $feDev = [System.Collections.Generic.List[string]]::new()

                            $ohFiles = @(
                                (Join-Path $PWD '..\\..\\..\\..\\oh-package.json5'),
                                (Join-Path $PWD '..\\..\\..\\oh-package.json5')
                            )
                            foreach ($ohFile in $ohFiles) {
                                if (Test-Path $ohFile) {
                                    $raw = Get-Content $ohFile -Raw -Encoding UTF8
                                    $json = $raw -replace '//.*', '' -replace ',(\\s*[}\\]])', '$1'
                                    $obj = $json | ConvertFrom-Json
                                    if ($obj.dependencies) { $feRuntime.AddRange([string[]]@($obj.dependencies.PSObject.Properties.Name)) }
                                    if ($obj.devDependencies) { $feDev.AddRange([string[]]@($obj.devDependencies.PSObject.Properties.Name)) }
                                }
                            }
                            $feRuntime = $feRuntime | Sort-Object -Unique
                            $feDev = $feDev | Sort-Object -Unique

                            $bePackages = [System.Collections.Generic.List[string]]::new()
                            $backendDir = Join-Path $PWD '..\\..\\..\\..\\..\\..\\backend'
                            if (Test-Path $backendDir) {
                                Get-ChildItem -Path $backendDir -Filter 'requirements.txt' -Recurse -Depth 1 | ForEach-Object {
                                    Get-Content $_.FullName -Encoding UTF8 | ForEach-Object {
                                        $line = $_.Trim()
                                        if ($line -and $line -notmatch '^\\s*#') {
                                            $name = ($line -split '[><=;@\\[]')[0].Trim()
                                            if ($name) { $bePackages.Add($name) }
                                        }
                                    }
                                }
                            }
                            $bePackages = $bePackages | Sort-Object -Unique
                            $totalDeps = $feRuntime.Count + $feDev.Count + $bePackages.Count

                            # --- Build report ---
                            $sb = [System.Text.StringBuilder]::new()
                            [void]$sb.AppendLine("=== Code Metrics Summary ===")
                            [void]$sb.AppendLine("")
                            [void]$sb.AppendLine("Source Files (.ets):       $fileCount")
                            [void]$sb.AppendLine("LOC  (total lines):        $totalLoc")
                            if ($hasLizard) {
                                [void]$sb.AppendLine("NLOC (lizard):             $lizardNloc")
                                $density = if ($totalLoc -gt 0) { [math]::Round(($totalLoc - $lizardNloc) / $totalLoc * 100, 1) } else { 0 }
                                [void]$sb.AppendLine("Comment/Blank density:     $density%")
                            } else {
                                [void]$sb.AppendLine("NLOC (lizard):             (lizard unavailable)")
                            }
                            [void]$sb.AppendLine("Functions detected:        $fnCount  (PowerShell brace-matched)")
                            [void]$sb.AppendLine("")
                            [void]$sb.AppendLine("File-level CCN (regex):")
                            [void]$sb.AppendLine("  Total CCN:               $totalFileCcn")
                            [void]$sb.AppendLine("  Avg CCN per file:        $avgFileCcn")
                            [void]$sb.AppendLine("")
                            [void]$sb.AppendLine("Function-level CCN (PowerShell, per-function):")
                            [void]$sb.AppendLine("  Total functions:         $fnCount")
                            [void]$sb.AppendLine("  Total CCN:               $totalFnCcn")
                            [void]$sb.AppendLine("  Avg CCN per function:    $avgFnCcn")
                            [void]$sb.AppendLine("")
                            [void]$sb.AppendLine("--- Top 10 Most Complex Files ---")
                            foreach ($f in $hotFiles) {
                                $bar = '#' * [math]::Min($f.Complexity, 50)
                                [void]$sb.AppendLine("  $($f.Complexity.ToString().PadLeft(4))  $bar  $($f.File) ($($f.TotalLines) LOC)")
                            }
                            [void]$sb.AppendLine("")
                            [void]$sb.AppendLine("--- Top 10 Most Complex Functions ---")
                            foreach ($fn in $hotFns) {
                                $bar = '#' * [math]::Min($fn.CCN, 50)
                                [void]$sb.AppendLine("  $($fn.CCN.ToString().PadLeft(4))  $bar  $($fn.Name)@L$($fn.StartLine)-$($fn.EndLine) $($fn.File) ($($fn.NLOC) NLOC)")
                            }
                            [void]$sb.AppendLine("")
                            [void]$sb.AppendLine("--- Dependencies ---")
                            [void]$sb.AppendLine("Frontend (oh-package.json5):")
                            [void]$sb.AppendLine("  Runtime dependencies: $($feRuntime.Count)")
                            if ($feRuntime.Count -gt 0) {
                                [void]$sb.AppendLine("    $($feRuntime -join ', ')")
                            }
                            [void]$sb.AppendLine("  Dev dependencies: $($feDev.Count)")
                            if ($feDev.Count -gt 0) {
                                [void]$sb.AppendLine("    $($feDev -join ', ')")
                            }
                            [void]$sb.AppendLine("")
                            [void]$sb.AppendLine("Backend (requirements.txt, unique across services):")
                            [void]$sb.AppendLine("  Python packages: $($bePackages.Count)")
                            if ($bePackages.Count -gt 0) {
                                [void]$sb.AppendLine("    $($bePackages -join ', ')")
                            }
                            [void]$sb.AppendLine("")
                            [void]$sb.AppendLine("Total unique dependencies: $totalDeps")

                            $summary = $sb.ToString()
                            Write-Host $summary
                            $summary | Set-Content -Path $metricsPath -Encoding UTF8
                            exit 0
                        '''
                    }
                }
            }
            post {
                success {
                    script {
                        echo ''
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo "${ANSI_GREEN}✓ METRICS COLLECTED SUCCESSFULLY${ANSI_RESET}"
                        echo "${ANSI_GREEN}  Location: ${env.CI_OUTPUT_DIR}\\metrics${ANSI_RESET}"
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo ''
                    }
                }
                failure {
                    script {
                        echo ''
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo "${ANSI_RED}✗ METRICS COLLECTION FAILED${ANSI_RESET}"
                        echo "${ANSI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${ANSI_RESET}"
                        echo ''
                    }
                }
            }
        }
    }

    post {
        always {
            script {
                echo ''
                echo "${ANSI_CYAN}╔════════════════════════════════════════════════════════════════╗${ANSI_RESET}"
                echo "${ANSI_CYAN}║                    PIPELINE COMPLETED                          ║${ANSI_RESET}"
                echo "${ANSI_CYAN}╚════════════════════════════════════════════════════════════════╝${ANSI_RESET}"
                echo ''
                def statusColor = currentBuild.currentResult == 'SUCCESS' ? ANSI_GREEN : ANSI_RED
                echo "${statusColor}Build Status: ${currentBuild.currentResult}${ANSI_RESET}"
                echo ''
                env.CI_BUILD_RESULT = currentBuild.currentResult
                powershell '''
                    $metaRoot = Join-Path $env:CI_OUTPUT_DIR 'meta'
                    @"
Build Status: $env:CI_BUILD_RESULT
Finished At: $(Get-Date -Format o)
"@ | Set-Content -Path (Join-Path $metaRoot 'build-result.txt') | Out-Null

                    Get-ChildItem -Recurse -File $env:CI_OUTPUT_DIR -ErrorAction SilentlyContinue |
                      Select-Object FullName, Length, LastWriteTime |
                      Out-File -FilePath (Join-Path $metaRoot 'artifact-manifest.txt') | Out-Null
                '''
            }
        }
        success {
            script {
                echo ''
                echo "${ANSI_CYAN}╔════════════════════════════════════════════════════════════════╗${ANSI_RESET}"
                echo "${ANSI_GREEN}║  ✓ BUILD SUCCESS!                                            ║${ANSI_RESET}"
                echo "${ANSI_GREEN}║  Local outputs:                                              ║${ANSI_RESET}"
                echo "${ANSI_GREEN}║  ${env.CI_OUTPUT_DIR}                 ║${ANSI_RESET}"
                echo "${ANSI_CYAN}╚════════════════════════════════════════════════════════════════╝${ANSI_RESET}"
                echo ''
            }
        }
        failure {
            script {
                echo ''
                echo "${ANSI_CYAN}╔════════════════════════════════════════════════════════════════╗${ANSI_RESET}"
                echo "${ANSI_RED}║  ✗ BUILD FAILED!                                             ║${ANSI_RESET}"
                echo "${ANSI_RED}║  Local outputs:                                              ║${ANSI_RESET}"
                echo "${ANSI_RED}║  ${env.CI_OUTPUT_DIR}                 ║${ANSI_RESET}"
                echo "${ANSI_CYAN}╚════════════════════════════════════════════════════════════════╝${ANSI_RESET}"
                echo ''
            }
        }
    }
}

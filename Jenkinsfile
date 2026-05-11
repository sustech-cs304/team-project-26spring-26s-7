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
                            $metricsPath = Join-Path $env:CI_OUTPUT_DIR 'metrics\\summary.txt'
                            $sourceFiles = Get-ChildItem -Recurse -File -Filter *.ets
                            $lineCount = ($sourceFiles | Get-Content | Measure-Object -Line | Select-Object -ExpandProperty Lines)
                            $fileCount = $sourceFiles.Count
                            $complexity = 0

                            foreach ($file in $sourceFiles) {
                                $content = Get-Content -Path $file.FullName -Raw
                                $decisionPoints = 0
                                $decisionPoints += ([regex]::Matches($content, '\\bif\\b')).Count
                                $decisionPoints += ([regex]::Matches($content, '\\bfor\\b')).Count
                                $decisionPoints += ([regex]::Matches($content, '\\bwhile\\b')).Count
                                $decisionPoints += ([regex]::Matches($content, '\\bcatch\\b')).Count
                                $decisionPoints += ([regex]::Matches($content, '\\bcase\\b')).Count
                                $decisionPoints += ([regex]::Matches($content, '\\?')).Count
                                $decisionPoints += ([regex]::Matches($content, '&&|\\|\\|')).Count
                                $complexity += (1 + $decisionPoints)
                            }

                            $dependencyFile = Join-Path $PWD '..\\..\\..\\oh-package.json5'
                            $dependencies = Get-Content $dependencyFile -Raw

                            $summary = @"
Lines of Code:
$lineCount

Number of Source Files:
$fileCount

Cyclomatic Complexity (Approximate):
$complexity

Dependencies:
$dependencies
"@

                            $summary | Tee-Object -FilePath $metricsPath | Out-Null
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

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
    }

    stages {
        stage('Checkout') {
            steps {
                script {
                    echo '=== Stage: Checkout ==='
                    checkout scm
                }
            }
        }

        stage('Prepare Outputs') {
            steps {
                script {
                    echo '=== Stage: Prepare Outputs ==='
                    def artifactRoot = env.LOCAL_ARTIFACT_ROOT?.trim()
                    if (!artifactRoot) {
                        artifactRoot = env.LOCAL_ARTIFACT_ROOT_DEFAULT
                    }
                    env.CI_OUTPUT_DIR = "${artifactRoot}\\build-${env.BUILD_NUMBER}"
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
"@ | Set-Content -Path (Join-Path $env:CI_OUTPUT_DIR 'meta\\build-info.txt')
                    '''
                }
            }
        }

        stage('Clean') {
            steps {
                script {
                    echo '=== Stage: Clean ==='
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
        }

        stage('Install Dependencies') {
            steps {
                script {
                    echo '=== Stage: Install Dependencies ==='
                    dir('frontend') {
                        bat '''
                            @echo off
                            call "%DEVECO_OHPM%" install > "%CI_OUTPUT_DIR%\\logs\\install-dependencies.log" 2>&1
                            set "stage_exit=%ERRORLEVEL%"
                            findstr /V /I /C:"ArkTS:WARN" /C:"Warning:" "%CI_OUTPUT_DIR%\\logs\\install-dependencies.log"
                            exit /b %stage_exit%
                        '''
                    }
                }
            }
        }

        stage('Compile') {
            steps {
                script {
                    echo '=== Stage: Compile ==='
                    dir('frontend') {
                        bat '''
                            @echo off
                            powershell -NoProfile -ExecutionPolicy Bypass -File build.ps1 --mode module -p module=entry@default assembleHap > "%CI_OUTPUT_DIR%\\logs\\compile.log" 2>&1
                            set "stage_exit=%ERRORLEVEL%"
                            findstr /V /I /C:"ArkTS:WARN" /C:"Warning:" "%CI_OUTPUT_DIR%\\logs\\compile.log"
                            exit /b %stage_exit%
                        '''
                    }
                }
            }
        }

        stage('Test') {
            steps {
                script {
                    echo '=== Stage: Test ==='
                    dir('frontend') {
                        bat '''
                            @echo off
                            powershell -NoProfile -ExecutionPolicy Bypass -File build.ps1 test > "%CI_OUTPUT_DIR%\\logs\\test.log" 2>&1
                            set "stage_exit=%ERRORLEVEL%"
                            findstr /V /I /C:"ArkTS:WARN" /C:"Warning:" "%CI_OUTPUT_DIR%\\logs\\test.log"
                            exit /b %stage_exit%
                        '''
                    }
                }
            }
            post {
                always {
                    script {
                        echo 'Collecting test reports...'
                        dir('frontend/entry/.test/default/intermediates/test/coverage_data') {
                            bat '''
                                if exist test_result.txt (
                                    echo === Test Results ===
                                    type test_result.txt
                                    echo === End Test Results ===
                                ) else (
                                    echo WARNING: test_result.txt not found - tests may not have run
                                )
                            '''
                        }
                        dir('frontend/entry/.test/default/outputs/test') {
                            archiveArtifacts artifacts: 'reports/**', allowEmptyArchive: true
                            powershell '''
                                $sourceRoot = (Get-Location).Path
                                $reportRoot = Join-Path $env:CI_OUTPUT_DIR 'reports\\test'
                                New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null
                                Copy-Item -Path (Join-Path $sourceRoot 'reports\\*') -Destination $reportRoot -Recurse -Force
                            '''
                        }
                        dir('frontend/entry/.test/default/intermediates/test') {
                            archiveArtifacts artifacts: '*.json, coverage_data/**', allowEmptyArchive: true
                            powershell '''
                                $sourceRoot = (Get-Location).Path
                                $coverageRoot = Join-Path $env:CI_OUTPUT_DIR 'reports\\coverage'
                                New-Item -ItemType Directory -Path $coverageRoot -Force | Out-Null
                                Get-ChildItem -Path $sourceRoot -File -Filter *.json | ForEach-Object {
                                  Copy-Item $_.FullName (Join-Path $coverageRoot $_.Name) -Force
                                }
                                if (Test-Path (Join-Path $sourceRoot 'coverage_data')) {
                                  Copy-Item -Path (Join-Path $sourceRoot 'coverage_data') -Destination $coverageRoot -Recurse -Force
                                }
                            '''
                        }
                    }
                }
            }
        }

        stage('Archive') {
            steps {
                script {
                    echo '=== Stage: Archive ==='
                    dir('frontend/entry/build/default/outputs/default') {
                        archiveArtifacts artifacts: '*.hap', fingerprint: true
                        powershell '''
                            $packageRoot = Join-Path $env:CI_OUTPUT_DIR 'packages'
                            Get-ChildItem -File | Where-Object { $_.Extension -eq '.hap' -or $_.Name -eq 'pack.info' } | ForEach-Object {
                              Copy-Item $_.FullName (Join-Path $packageRoot $_.Name) -Force
                            }
                        '''
                    }
                }
            }
        }

        stage('Metrics') {
            steps {
                script {
                    echo '=== Stage: Collect Metrics ==='
                    dir('frontend/entry/src/main/ets') {
                        powershell '''
                            $metricsPath = Join-Path $env:CI_OUTPUT_DIR 'metrics\\summary.txt'
                            $sourceFiles = Get-ChildItem -Recurse -File -Filter *.ets
                            $lineCount = ($sourceFiles | Get-Content | Measure-Object -Line).Lines
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

                            $summary | Tee-Object -FilePath $metricsPath
                        '''
                    }
                }
            }
        }
    }

    post {
        always {
            script {
                echo '=== Pipeline Completed ==='
                echo "Build Status: ${currentBuild.currentResult}"
                env.CI_BUILD_RESULT = currentBuild.currentResult
                powershell '''
                    $metaRoot = Join-Path $env:CI_OUTPUT_DIR 'meta'
                    @"
Build Status: $env:CI_BUILD_RESULT
Finished At: $(Get-Date -Format o)
"@ | Set-Content -Path (Join-Path $metaRoot 'build-result.txt')

                    Get-ChildItem -Recurse -File $env:CI_OUTPUT_DIR |
                      Select-Object FullName, Length, LastWriteTime |
                      Out-File -FilePath (Join-Path $metaRoot 'artifact-manifest.txt')
                '''
            }
        }
        success {
            script {
                echo "Build SUCCESS! Local outputs: ${env.CI_OUTPUT_DIR}"
            }
        }
        failure {
            script {
                echo "Build FAILED! Local outputs: ${env.CI_OUTPUT_DIR}"
            }
        }
    }
}

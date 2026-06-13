param(
    [string]$Device,
    [string]$Apk,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$AppPackage = 'com.example.flutter_project'
$AppComponent = "$AppPackage/com.example.flutter_project.MainActivity"
$PackageKeywords = @(
    'cutter',
    'plotter',
    'skycut',
    'upus',
    'upprinting',
    'sunshine',
    'mechanic',
    'phonefilm',
    'vinyl'
)
$SkipPackages = @(
    $AppPackage,
    'android',
    'com.android.settings',
    'com.android.systemui'
)

function Write-Log {
    param([string]$Message)
    Write-Host "[launcher-install] $Message"
}

function Fail {
    param([string]$Message)
    throw "[launcher-install] ERROR: $Message"
}

function Run-Process {
    param(
        [string[]]$Arguments,
        [switch]$AllowFailure
    )

    $output = & adb @Arguments 2>&1
    $exitCode = $LASTEXITCODE

    if (-not $AllowFailure -and $exitCode -ne 0) {
        $joined = ($output | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($joined)) {
            $joined = "Command failed: adb $($Arguments -join ' ')"
        }
        Fail $joined
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output   = ($output | Out-String).Replace("`r", '').Trim()
    }
}

function Get-AdbArgs {
    param([string]$DeviceSerial, [string[]]$Extra)

    $args = @()
    if (-not [string]::IsNullOrWhiteSpace($DeviceSerial)) {
        $args += '-s'
        $args += $DeviceSerial
    }
    $args += $Extra
    return $args
}

function Invoke-AdbCapture {
    param([string]$DeviceSerial, [string[]]$Extra, [switch]$AllowFailure)

    $args = Get-AdbArgs -DeviceSerial $DeviceSerial -Extra $Extra
    $result = Run-Process -Arguments $args -AllowFailure:$AllowFailure
    return $result.Output
}

function Invoke-AdbShell {
    param(
        [string]$DeviceSerial,
        [string]$Command,
        [switch]$UseRoot,
        [switch]$AllowFailure
    )

    $extra = @('shell')
    if ($UseRoot) {
        $extra += 'su'
        $extra += '-c'
        $extra += $Command
    } else {
        $extra += $Command
    }

    return Invoke-AdbCapture -DeviceSerial $DeviceSerial -Extra $extra -AllowFailure:$AllowFailure
}

function Test-AdbShellSuccess {
    param(
        [string]$DeviceSerial,
        [string]$Command,
        [switch]$UseRoot
    )

    $extra = @('shell')
    if ($UseRoot) {
        $extra += 'su'
        $extra += '-c'
        $extra += $Command
    } else {
        $extra += $Command
    }

    $args = Get-AdbArgs -DeviceSerial $DeviceSerial -Extra $extra
    $result = Run-Process -Arguments $args -AllowFailure
    return $result.ExitCode -eq 0
}

function Detect-ProjectRoot {
    return Split-Path -Parent $PSScriptRoot
}

function Detect-DefaultApk {
    param([string]$ProjectRoot, [string]$ExplicitApk)

    if (-not [string]::IsNullOrWhiteSpace($ExplicitApk)) {
        $resolved = (Resolve-Path -Path $ExplicitApk).Path
        if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
            Fail "APK not found: $ExplicitApk"
        }
        return $resolved
    }

    $candidates = @(
        (Join-Path $ProjectRoot 'update.apk'),
        (Join-Path $ProjectRoot 'build\app\outputs\flutter-apk\app-release.apk')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    Fail 'No APK found. Put update.apk next to the project or pass -Apk C:\path\file.apk'
}

function Detect-Device {
    param([string]$ExplicitDevice)

    if (-not [string]::IsNullOrWhiteSpace($ExplicitDevice)) {
        return $ExplicitDevice
    }

    $output = Invoke-AdbCapture -DeviceSerial '' -Extra @('devices')
    $devices = @()
    foreach ($line in ($output -split "`n")) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^([^\s]+)\s+device$') {
            $devices += $Matches[1]
        }
    }

    if ($devices.Count -eq 0) {
        Fail 'No authorized adb device is connected.'
    }

    if ($devices.Count -gt 1) {
        Write-Log "Multiple devices detected. Using: $($devices[0])"
    }

    return $devices[0]
}

function Require-Adb {
    if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
        Fail 'adb is not installed or not in PATH.'
    }
}

function Require-Root {
    param([string]$DeviceSerial)

    if (-not (Test-AdbShellSuccess -DeviceSerial $DeviceSerial -Command 'id >/dev/null 2>&1' -UseRoot)) {
        Fail 'Root is required on the connected device.'
    }
}

function Get-ApkVersion {
    param([string]$ApkPath)

    $sdkRoot = $env:ANDROID_SDK_ROOT
    if ([string]::IsNullOrWhiteSpace($sdkRoot)) {
        $sdkRoot = $env:ANDROID_HOME
    }

    $aaptCandidates = @()
    if (-not [string]::IsNullOrWhiteSpace($sdkRoot) -and (Test-Path $sdkRoot)) {
        $buildTools = Join-Path $sdkRoot 'build-tools'
        if (Test-Path $buildTools) {
            $aaptCandidates += Get-ChildItem -Path $buildTools -Directory |
                Sort-Object Name -Descending |
                ForEach-Object { Join-Path $_.FullName 'aapt.exe' }
        }
    }

    foreach ($candidate in $aaptCandidates) {
        if (-not (Test-Path $candidate -PathType Leaf)) {
            continue
        }

        try {
            $badging = & $candidate dump badging $ApkPath 2>$null
            if ($LASTEXITCODE -ne 0) {
                continue
            }
            $joined = ($badging | Out-String)
            if ($joined -match "versionName='([^']+)'" -and $joined -match "versionCode='([^']+)'") {
                return "$($Matches[1]) ($($Matches[2]))"
            }
        } catch {
        }
    }

    return $null
}

function Install-App {
    param([string]$DeviceSerial, [string]$ApkPath, [switch]$DryRunMode)

    Write-Log "Installing APK: $ApkPath"
    if ($DryRunMode) {
        return
    }

    $result = Run-Process -Arguments (Get-AdbArgs -DeviceSerial $DeviceSerial -Extra @('install', '-r', '-d', $ApkPath)) -AllowFailure
    if ($result.ExitCode -ne 0) {
        $message = $result.Output
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = 'APK install failed.'
        }
        Fail $message
    }
}

function Add-Candidate {
    param([System.Collections.Generic.List[string]]$Candidates, [string]$PackageName)

    if ([string]::IsNullOrWhiteSpace($PackageName)) {
        return
    }
    if ($Candidates.Contains($PackageName)) {
        return
    }
    $Candidates.Add($PackageName) | Out-Null
}

function Get-HomePackages {
    param([string]$DeviceSerial)

    $output = Invoke-AdbShell -DeviceSerial $DeviceSerial -UseRoot -AllowFailure -Command "cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null || pm query-intent-activities -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null || true"
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in ($output -split "`n")) {
        if ($line -notmatch '/') {
            continue
        }
        $packageName = ($line.Split('/')[0]).Trim()
        Add-Candidate -Candidates $candidates -PackageName $packageName
    }
    return $candidates
}

function Get-KeywordPackages {
    param([string]$DeviceSerial)

    $output = Invoke-AdbShell -DeviceSerial $DeviceSerial -Command 'pm list packages' -AllowFailure
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in ($output -split "`n")) {
        $trimmed = $line.Trim()
        if (-not $trimmed.StartsWith('package:')) {
            continue
        }
        $packageName = $trimmed.Substring(8)
        $lowerName = $packageName.ToLowerInvariant()
        foreach ($keyword in $PackageKeywords) {
            if ($lowerName.Contains($keyword)) {
                Add-Candidate -Candidates $candidates -PackageName $packageName
                break
            }
        }
    }
    return $candidates
}

function Remove-OrDisablePackage {
    param([string]$DeviceSerial, [string]$PackageName, [switch]$DryRunMode)

    if ($SkipPackages -contains $PackageName) {
        return
    }

    Write-Log "Removing competing package: $PackageName"
    if ($DryRunMode) {
        return
    }

    [void](Test-AdbShellSuccess -DeviceSerial $DeviceSerial -UseRoot -Command "am force-stop '$PackageName' >/dev/null 2>&1 || true")

    if (Test-AdbShellSuccess -DeviceSerial $DeviceSerial -UseRoot -Command "pm uninstall --user 0 '$PackageName' >/dev/null 2>&1") {
        return
    }

    if (Test-AdbShellSuccess -DeviceSerial $DeviceSerial -UseRoot -Command "pm disable-user --user 0 '$PackageName' >/dev/null 2>&1 || pm disable '$PackageName' >/dev/null 2>&1") {
        return
    }

    Write-Log "Could not remove or disable: $PackageName"
}

function Force-LauncherDefault {
    param([string]$DeviceSerial, [switch]$DryRunMode)

    Write-Log "Making $AppPackage the HOME launcher"
    if ($DryRunMode) {
        return
    }

    $commands = @(
        "pm enable '$AppPackage' >/dev/null 2>&1 || true",
        "cmd package set-home-activity '$AppComponent' >/dev/null 2>&1 || pm set-home-activity '$AppComponent' >/dev/null 2>&1 || true",
        "am start -n '$AppComponent' >/dev/null 2>&1 || true",
        "input keyevent KEYCODE_HOME >/dev/null 2>&1 || true"
    )

    foreach ($command in $commands) {
        [void](Test-AdbShellSuccess -DeviceSerial $DeviceSerial -UseRoot -Command $command)
    }
}

function Show-Summary {
    param([string]$DeviceSerial)

    $resolvedHome = Invoke-AdbShell -DeviceSerial $DeviceSerial -UseRoot -AllowFailure -Command "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null || true"
    $resolvedHomeLine = ($resolvedHome -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 1).Trim()
    if ([string]::IsNullOrWhiteSpace($resolvedHomeLine)) {
        $resolvedHomeLine = 'unknown'
    }

    $focusOutput = Invoke-AdbShell -DeviceSerial $DeviceSerial -AllowFailure -Command "dumpsys window windows 2>/dev/null | grep -E 'mCurrentFocus|mFocusedApp' || true"
    $focusLines = $focusOutput -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 2

    Write-Log "Resolved HOME: $resolvedHomeLine"
    foreach ($line in $focusLines) {
        Write-Host $line.Trim()
    }
}

Require-Adb
$projectRoot = Detect-ProjectRoot
$apkPath = Detect-DefaultApk -ProjectRoot $projectRoot -ExplicitApk $Apk
$deviceSerial = Detect-Device -ExplicitDevice $Device
Require-Root -DeviceSerial $deviceSerial

Write-Log "Device: $deviceSerial"
$apkVersion = Get-ApkVersion -ApkPath $apkPath
if ($apkVersion) {
    Write-Log "APK version: $apkVersion"
}

Install-App -DeviceSerial $deviceSerial -ApkPath $apkPath -DryRunMode:$DryRun

$removalCandidates = New-Object 'System.Collections.Generic.List[string]'
foreach ($packageName in (Get-HomePackages -DeviceSerial $deviceSerial)) {
    Add-Candidate -Candidates $removalCandidates -PackageName $packageName
}
foreach ($packageName in (Get-KeywordPackages -DeviceSerial $deviceSerial)) {
    Add-Candidate -Candidates $removalCandidates -PackageName $packageName
}

if ($removalCandidates.Count -gt 0) {
    Write-Log "Candidate packages: $($removalCandidates -join ' ')"
}

foreach ($packageName in $removalCandidates) {
    Remove-OrDisablePackage -DeviceSerial $deviceSerial -PackageName $packageName -DryRunMode:$DryRun
}

Force-LauncherDefault -DeviceSerial $deviceSerial -DryRunMode:$DryRun
Show-Summary -DeviceSerial $deviceSerial
Write-Log 'Done.'

#Requires -Version 5.0
# DPI awareness - must be set before any UI code to prevent blurry text
try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class DpiHelper {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")]
    public static extern IntPtr SetProcessDpiAwarenessContext(IntPtr value);
}
"@
    # Try per-monitor DPI awareness first (Windows 10 1703+), fallback to system DPI awareness
    $DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = [IntPtr](-4)
    $result = [DpiHelper]::SetProcessDpiAwarenessContext($DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)
    if (-not $result) {
        [DpiHelper]::SetProcessDPIAware() | Out-Null
    }
} catch {
    try { [DpiHelper]::SetProcessDPIAware() | Out-Null } catch {}
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ============ Config Paths ============
$Script:TraeDataDir = "$env:APPDATA\TRAE SOLO CN"
$Script:SwitcherDir = "$env:APPDATA\TraeWorkSwitcher"
$Script:AccountsFile = "$Script:SwitcherDir\accounts.json"
$Script:ProfilesDir = "$Script:SwitcherDir\profiles"
$Script:LogFile = "$Script:SwitcherDir\switcher.log"

# ============ v5.3 3D Card Design System ============
$C_BG_PAGE = [System.Drawing.Color]::FromArgb(238, 240, 246)
$C_BG_HEADER = [System.Drawing.Color]::FromArgb(255, 255, 255)
$C_BG_CARD = [System.Drawing.Color]::FromArgb(255, 255, 255)
$C_BG_INPUT = [System.Drawing.Color]::FromArgb(248, 250, 252)
$C_BG_LOG = [System.Drawing.Color]::FromArgb(28, 30, 38)

$C_FROST_PRIMARY = [System.Drawing.Color]::FromArgb(79, 107, 255)
$C_FROST_SUCCESS = [System.Drawing.Color]::FromArgb(34, 197, 94)
$C_FROST_WARN = [System.Drawing.Color]::FromArgb(245, 158, 11)
$C_FROST_DANGER = [System.Drawing.Color]::FromArgb(239, 68, 68)
$C_FROST_NEUTRAL = [System.Drawing.Color]::FromArgb(107, 114, 128)
$C_FROST_DISABLED = [System.Drawing.Color]::FromArgb(209, 213, 219)
$C_FROST_ACCENT = [System.Drawing.Color]::FromArgb(88, 86, 214)
$C_BTN_REGISTER = [System.Drawing.Color]::FromArgb(255, 140, 50)

$C_TEXT_TITLE = [System.Drawing.Color]::FromArgb(31, 41, 55)
$C_TEXT_BODY = [System.Drawing.Color]::FromArgb(55, 65, 81)
$C_TEXT_MUTED = [System.Drawing.Color]::FromArgb(107, 114, 128)
$C_TEXT_LIGHT = [System.Drawing.Color]::FromArgb(220, 225, 235)
$C_TEXT_WHITE = [System.Drawing.Color]::White
$C_TEXT_DISABLED = [System.Drawing.Color]::FromArgb(156, 163, 175)

$C_SUCCESS = [System.Drawing.Color]::FromArgb(34, 197, 94)
$C_DANGER = [System.Drawing.Color]::FromArgb(239, 68, 68)
$C_BORDER = [System.Drawing.Color]::FromArgb(229, 231, 235)
$C_BORDER_FOCUS = [System.Drawing.Color]::FromArgb(79, 107, 255)

# ============ Utility Functions ============

function Write-Log {
    param([string]$Message)
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $log = "[$time] $Message"
    if (-not (Test-Path $Script:SwitcherDir)) { New-Item -ItemType Directory -Force -Path $Script:SwitcherDir | Out-Null }
    Add-Content -Path $Script:LogFile -Value $log -Encoding UTF8
}

function Add-LogLine {
    param([string]$Message)
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $log = "[$time] $Message"
    if (-not (Test-Path $Script:SwitcherDir)) { New-Item -ItemType Directory -Force -Path $Script:SwitcherDir | Out-Null }
    Add-Content -Path $Script:LogFile -Value $log -Encoding UTF8
    if ($Script:LogTextBox) {
        $Script:LogTextBox.AppendText("$log`r`n")
        $Script:LogTextBox.SelectionStart = $Script:LogTextBox.Text.Length
        $Script:LogTextBox.ScrollToCaret()
    }
}

function Get-TraeWorkPath {
    $proc = Get-Process -Name "TRAE SOLO CN" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc -and $proc.Path -and (Test-Path $proc.Path)) { return [string]$proc.Path }
    $drives = @("C:", "D:", "E:", "F:")
    try {
        $psDrives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue
        foreach ($psd in $psDrives) { $dname = $psd.Name + ":"; if ($drives -notcontains $dname) { $drives += $dname } }
    } catch {}
    $commonPaths = @()
    foreach ($d in $drives) {
        $commonPaths += "$d\TRAE SOLO CN\TRAE SOLO CN\TRAE SOLO CN.exe"
        $commonPaths += "$d\Program Files\TRAE SOLO CN\TRAE SOLO CN.exe"
    }
    $commonPaths += "$env:LOCALAPPDATA\Programs\TRAE SOLO CN\TRAE SOLO CN.exe"
    $desktopDirs = @("$env:USERPROFILE\Desktop", "$env:PUBLIC\Desktop")
    foreach ($deskDir in $desktopDirs) {
        $lnks = Get-ChildItem $deskDir -Filter "*.lnk" -ErrorAction SilentlyContinue
        foreach ($lnk in $lnks) {
            if ($lnk.Name -match "TRAE SOLO CN" -or $lnk.Name -match "TRAE Work") {
                try { $shell = New-Object -ComObject WScript.Shell; $shortcut = $shell.CreateShortcut($lnk.FullName); if ($shortcut.TargetPath -and (Test-Path $shortcut.TargetPath) -and $shortcut.TargetPath -match "TRAE SOLO CN\.exe$") { return [string]$shortcut.TargetPath } } catch {}
            }
        }
    }
    try {
        $regPaths = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall", "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall")
        foreach ($rp in $regPaths) { $regItems = Get-ChildItem $rp -ErrorAction SilentlyContinue; foreach ($regItem in $regItems) { $p = Get-ItemProperty $regItem.PSPath -ErrorAction SilentlyContinue; if ($p.DisplayName -match "TRAE SOLO CN" -and $p.InstallLocation) { $exe = Join-Path $p.InstallLocation "TRAE SOLO CN.exe"; if (Test-Path $exe) { return [string]$exe } } } }
    } catch {}
    foreach ($p in $commonPaths) { if (Test-Path $p) { return [string]$p } }
    return $null
}

function New-MachineId { return [Guid]::NewGuid().ToString().ToLower() }
function New-HexId { $bytes = New-Object 'byte[]' 32; $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create(); $rng.GetBytes($bytes); return [BitConverter]::ToString($bytes).Replace("-","").ToLower() }
function Get-TraeWorkProcess { return Get-Process -Name "TRAE SOLO CN" -ErrorAction SilentlyContinue }
function Initialize-Storage {
    if (-not (Test-Path $Script:SwitcherDir)) { New-Item -ItemType Directory -Force -Path $Script:SwitcherDir | Out-Null }
    if (-not (Test-Path $Script:ProfilesDir)) { New-Item -ItemType Directory -Force -Path $Script:ProfilesDir | Out-Null }
    if (-not (Test-Path $Script:AccountsFile)) { $initial = '{"accounts":{},"currentAccountId":null}'; [System.IO.File]::WriteAllText($Script:AccountsFile, $initial, [System.Text.Encoding]::UTF8) }
}

# ============ JSON Read/Write ============
function Read-AccountsJson {
    Initialize-Storage
    try {
        $raw = Get-Content $Script:AccountsFile -Encoding UTF8 -Raw
        $obj = $raw | ConvertFrom-Json
        $result = @{ accounts = @{}; currentAccountId = $obj.currentAccountId }
        if ($obj.accounts) {
            foreach ($prop in $obj.accounts.PSObject.Properties) {
                $mid = $prop.Value.machineId
                if ($mid -is [array]) { $mid = $mid[-1] }
                $result.accounts[$prop.Name] = @{ id = $prop.Value.id; name = $prop.Value.name; machineId = $mid; createdAt = $prop.Value.createdAt; lastUsedAt = $prop.Value.lastUsedAt; notes = $prop.Value.notes }
            }
        }
        return $result
    } catch { return @{ accounts = @{}; currentAccountId = $null } }
}

function Save-AccountsJson { param($Data); $json = $Data | ConvertTo-Json -Depth 10; [System.IO.File]::WriteAllText($Script:AccountsFile, $json, [System.Text.Encoding]::UTF8) }

function Stop-TraeWork {
    $proc = Get-TraeWorkProcess
    if ($proc) { Add-LogLine "正在关闭 Trae Work..."; $proc | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 3; Add-LogLine "Trae Work 已关闭" }
}

function Start-TraeWork {
    $exePath = Get-TraeWorkPath
    if (-not $exePath) { Add-LogLine "[错误] 未找到 Trae Work"; return $false }
    try { Add-LogLine "正在启动 Trae Work: $exePath"; Start-Process $exePath; Start-Sleep -Seconds 2; Add-LogLine "Trae Work 已启动"; return $true }
    catch { Add-LogLine "启动失败: $_"; return $false }
}

function Backup-CurrentProfile {
    param([string]$ProfileDir)
    Add-LogLine "正在备份当前配置..."
    New-Item -ItemType Directory -Force -Path $ProfileDir | Out-Null
    $storageJson = "$Script:TraeDataDir\User\globalStorage\storage.json"
    if (Test-Path $storageJson) { Copy-Item $storageJson "$ProfileDir\storage.json" -Force }
    $machineIdFile = "$Script:TraeDataDir\machineid"
    if (Test-Path $machineIdFile) { Copy-Item $machineIdFile "$ProfileDir\machineid" -Force }
    $ahaSourceDir = "$Script:TraeDataDir\aha"
    if (Test-Path $ahaSourceDir) { $ahaDest = "$ProfileDir\aha"; if (Test-Path $ahaDest) { Remove-Item $ahaDest -Recurse -Force }; Copy-Item $ahaSourceDir $ahaDest -Recurse -Force -ErrorAction SilentlyContinue }
    $prefsFile = "$Script:TraeDataDir\Preferences"
    if (Test-Path $prefsFile) { Copy-Item $prefsFile "$ProfileDir\Preferences" -Force }
    $localState = "$Script:TraeDataDir\Local State"
    if (Test-Path $localState) { Copy-Item $localState "$ProfileDir\Local State" -Force }
    $localStorage = "$Script:TraeDataDir\Local Storage\leveldb"
    if (Test-Path $localStorage) { $lsDest = "$ProfileDir\Local Storage\leveldb"; New-Item -ItemType Directory -Force -Path $lsDest | Out-Null; Copy-Item "$localStorage\*" $lsDest -Force -ErrorAction SilentlyContinue }
    $localConfigDb = "$Script:TraeDataDir\Local Storage\config.db"
    if (Test-Path $localConfigDb) { $lsParent = "$ProfileDir\Local Storage"; if (-not (Test-Path $lsParent)) { New-Item -ItemType Directory -Force -Path $lsParent | Out-Null }; Copy-Item $localConfigDb "$lsParent\config.db" -Force }
    $networkDir = "$Script:TraeDataDir\Network"
    if (Test-Path $networkDir) { $netDest = "$ProfileDir\Network"; if (Test-Path $netDest) { Remove-Item $netDest -Recurse -Force }; Copy-Item $networkDir $netDest -Recurse -Force -ErrorAction SilentlyContinue }
    $wvSource = "$Script:TraeDataDir\Partitions\trae-webview"
    if (Test-Path $wvSource) { $wvDest = "$ProfileDir\Partitions\trae-webview"; if (Test-Path $wvDest) { Remove-Item $wvDest -Recurse -Force }; Copy-Item $wvSource $wvDest -Recurse -Force -ErrorAction SilentlyContinue; Add-LogLine "  已备份 trae-webview" }
    $icubeSource = "$Script:TraeDataDir\Partitions\icube-web-crawler-shared-session-v1.0"
    if (Test-Path $icubeSource) { $icubeDest = "$ProfileDir\Partitions\icube-web-crawler-shared-session-v1.0"; if (Test-Path $icubeDest) { Remove-Item $icubeDest -Recurse -Force }; Copy-Item $icubeSource $icubeDest -Recurse -Force -ErrorAction SilentlyContinue; Add-LogLine "  已备份 icube-web-crawler" }
    $sessionStorage = "$Script:TraeDataDir\Session Storage"
    if (Test-Path $sessionStorage) { $ssDest = "$ProfileDir\Session Storage"; if (Test-Path $ssDest) { Remove-Item $ssDest -Recurse -Force }; Copy-Item $sessionStorage $ssDest -Recurse -Force -ErrorAction SilentlyContinue }
    $stateDb = "$Script:TraeDataDir\User\globalStorage\state.vscdb"
    $stateDbBak = "$Script:TraeDataDir\User\globalStorage\state.vscdb.backup"
    if (Test-Path $stateDb) { Copy-Item $stateDb "$ProfileDir\state.vscdb" -Force -ErrorAction SilentlyContinue }
    if (Test-Path $stateDbBak) { Copy-Item $stateDbBak "$ProfileDir\state.vscdb.backup" -Force -ErrorAction SilentlyContinue }
    Add-LogLine "备份完成"
}

function Restore-Profile {
    param([string]$ProfileDir, [string]$MachineId)
    Add-LogLine "正在恢复配置..."
    $codeLock = "$Script:TraeDataDir\code.lock"
    if (Test-Path $codeLock) { Remove-Item $codeLock -Force -ErrorAction SilentlyContinue }
    $machineIdFile = "$Script:TraeDataDir\machineid"
    Set-Content -Path $machineIdFile -Value $MachineId -Force -Encoding UTF8
    Add-LogLine "  机器码: $MachineId"
    $targetStorage = "$Script:TraeDataDir\User\globalStorage\storage.json"
    if (Test-Path "$ProfileDir\storage.json") { $dir = Split-Path $targetStorage -Parent; if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }; Copy-Item "$ProfileDir\storage.json" $targetStorage -Force }
    $targetAha = "$Script:TraeDataDir\aha"
    if (Test-Path "$ProfileDir\aha") { if (Test-Path $targetAha) { Remove-Item $targetAha -Recurse -Force -ErrorAction SilentlyContinue }; Copy-Item "$ProfileDir\aha" $targetAha -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path "$ProfileDir\Preferences") { Copy-Item "$ProfileDir\Preferences" "$Script:TraeDataDir\Preferences" -Force }
    if (Test-Path "$ProfileDir\Local State") { Copy-Item "$ProfileDir\Local State" "$Script:TraeDataDir\Local State" -Force }
    $targetLSdb = "$Script:TraeDataDir\Local Storage\leveldb"
    if (Test-Path "$ProfileDir\Local Storage\leveldb") { if (Test-Path $targetLSdb) { Remove-Item $targetLSdb\* -Force -ErrorAction SilentlyContinue } else { New-Item -ItemType Directory -Force -Path $targetLSdb | Out-Null }; Copy-Item "$ProfileDir\Local Storage\leveldb\*" $targetLSdb -Force -ErrorAction SilentlyContinue }
    if (Test-Path "$ProfileDir\Local Storage\config.db") { Copy-Item "$ProfileDir\Local Storage\config.db" "$Script:TraeDataDir\Local Storage\config.db" -Force }
    $targetNet = "$Script:TraeDataDir\Network"
    if (Test-Path "$ProfileDir\Network") { if (Test-Path $targetNet) { Remove-Item $targetNet\* -Recurse -Force -ErrorAction SilentlyContinue } else { New-Item -ItemType Directory -Force -Path $targetNet | Out-Null }; Copy-Item "$ProfileDir\Network\*" $targetNet -Recurse -Force -ErrorAction SilentlyContinue }
    $targetWVBase = "$Script:TraeDataDir\Partitions\trae-webview"
    if (Test-Path "$ProfileDir\Partitions\trae-webview") { if (Test-Path $targetWVBase) { Remove-Item $targetWVBase -Recurse -Force -ErrorAction SilentlyContinue }; $wvParent = Split-Path $targetWVBase -Parent; if (-not (Test-Path $wvParent)) { New-Item -ItemType Directory -Force -Path $wvParent | Out-Null }; Copy-Item "$ProfileDir\Partitions\trae-webview" $targetWVBase -Recurse -Force -ErrorAction SilentlyContinue; Add-LogLine "  已恢复 trae-webview" }
    $targetICubeBase = "$Script:TraeDataDir\Partitions\icube-web-crawler-shared-session-v1.0"
    if (Test-Path "$ProfileDir\Partitions\icube-web-crawler-shared-session-v1.0") { if (Test-Path $targetICubeBase) { Remove-Item $targetICubeBase -Recurse -Force -ErrorAction SilentlyContinue }; $iCubeParent = Split-Path $targetICubeBase -Parent; if (-not (Test-Path $iCubeParent)) { New-Item -ItemType Directory -Force -Path $iCubeParent | Out-Null }; Copy-Item "$ProfileDir\Partitions\icube-web-crawler-shared-session-v1.0" $targetICubeBase -Recurse -Force -ErrorAction SilentlyContinue; Add-LogLine "  已恢复 icube-web-crawler" }
    $targetSS = "$Script:TraeDataDir\Session Storage"
    if (Test-Path "$ProfileDir\Session Storage") { if (Test-Path $targetSS) { Remove-Item $targetSS -Recurse -Force -ErrorAction SilentlyContinue }; Copy-Item "$ProfileDir\Session Storage" $targetSS -Recurse -Force -ErrorAction SilentlyContinue }
    $targetStateDb = "$Script:TraeDataDir\User\globalStorage\state.vscdb"
    if (Test-Path "$ProfileDir\state.vscdb") { $stateDir = Split-Path $targetStateDb -Parent; if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Force -Path $stateDir | Out-Null }; Copy-Item "$ProfileDir\state.vscdb" $targetStateDb -Force -ErrorAction SilentlyContinue }
    if (Test-Path "$ProfileDir\state.vscdb.backup") { Copy-Item "$ProfileDir\state.vscdb.backup" "$Script:TraeDataDir\User\globalStorage\state.vscdb.backup" -Force -ErrorAction SilentlyContinue }
    Add-LogLine "恢复完成"
}

function Reset-DeviceIdsOnly {
    Add-LogLine "正在重置设备标识..."
    $machineIdFile = "$Script:TraeDataDir\machineid"
    $newMachineId = New-MachineId
    Set-Content -Path $machineIdFile -Value $newMachineId -Force -Encoding UTF8
    Add-LogLine "  machineid: $newMachineId"
    $storageFile = "$Script:TraeDataDir\User\globalStorage\storage.json"
    if (Test-Path $storageFile) {
        try {
            $storageObj = Get-Content $storageFile -Encoding UTF8 -Raw | ConvertFrom-Json
            if ($storageObj.'has_device_id_updated_to_aha') { $storageObj.PSObject.Properties.Remove('has_device_id_updated_to_aha'); Add-LogLine "  已移除 has_device_id_updated_to_aha" }
            if ($storageObj.'telemetry.machineId') { $storageObj.'telemetry.machineId' = $newMachineId }
            if ($storageObj.'telemetry.sqmId') { $storageObj.'telemetry.sqmId' = New-HexId }
            if ($storageObj.'aha.device.device_id') { $storageObj.'aha.device.device_id' = $newMachineId; Add-LogLine "  已重置 aha.device.device_id" }
            $storageJson = $storageObj | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($storageFile, $storageJson, [System.Text.Encoding]::UTF8)
        } catch { Add-LogLine "  [警告] 重置 storage.json 失败: $_" }
    }
    $tinyStorageFile = "$Script:TraeDataDir\aha\TinyStorage"
    if (Test-Path $tinyStorageFile) { try { $tinyObj = Get-Content $tinyStorageFile -Encoding UTF8 -Raw | ConvertFrom-Json; if ($tinyObj.PSObject.Properties.Name -contains 'device_id') { $tinyObj.PSObject.Properties.Remove('device_id'); $tinyJson = $tinyObj | ConvertTo-Json -Depth 10; [System.IO.File]::WriteAllText($tinyStorageFile, $tinyJson, [System.Text.Encoding]::UTF8) } } catch { Remove-Item $tinyStorageFile -Force -ErrorAction SilentlyContinue } }
    $wvPartition = "$Script:TraeDataDir\Partitions\trae-webview"
    if (Test-Path $wvPartition) { foreach ($f in @("$wvPartition\Cookies", "$wvPartition\Local Storage", "$wvPartition\Session Storage")) { if (Test-Path $f) { Remove-Item $f -Recurse -Force -ErrorAction SilentlyContinue } }; Add-LogLine "  已清除 trae-webview 追踪数据" }
    try { $machineGuid = [Guid]::NewGuid().ToString(); Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name "MachineGuid" -Value $machineGuid -ErrorAction SilentlyContinue; Add-LogLine "  MachineGuid: $machineGuid" } catch { Add-LogLine "  [警告] 重置 MachineGuid 需要管理员权限" }
    foreach ($td in @("$Script:TraeDataDir\aha\Remote_State", "$env:APPDATA\TRAE SOLO CN\logs\telemetry")) { if (Test-Path $td) { Remove-Item $td -Recurse -Force -ErrorAction SilentlyContinue } }
    $icubeServerData = "$Script:TraeDataDir\aha\icubeServerData"
    if (Test-Path $icubeServerData) { Remove-Item $icubeServerData -Recurse -Force -ErrorAction SilentlyContinue }
    return $newMachineId
}

# ============ Global Controls ============
$Script:MainForm = $null
$Script:AccountListBox = $null
$Script:StatusLabel = $null
$Script:StatusDot = $null
$Script:MachineIdLabel = $null
$Script:LogTextBox = $null
$Script:LastUsedLabel = $null
$Script:AccountCountLabel = $null
$Script:CurrentAccountLabel = $null
$Script:LogVisible = $false
$Script:LogToggleButton = $null

# ============ UI Helpers ============

function Enable-DoubleBuffer {
    param($Control)
    try {
        $prop = $Control.GetType().GetProperty("DoubleBuffered", [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic)
        if ($prop) { $prop.SetValue($Control, $true, $null) }
    } catch {}
}

function New-RoundedRectPath {
    param([int]$X, [int]$Y, [int]$W, [int]$H, [int]$R)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $R * 2
    if ($d -gt $W) { $d = $W }
    if ($d -gt $H) { $d = $H }
    $path.AddArc($X, $Y, $d, $d, 180, 90)
    $path.AddArc($X + $W - $d, $Y, $d, $d, 270, 90)
    $path.AddArc($X + $W - $d, $Y + $H - $d, $d, $d, 0, 90)
    $path.AddArc($X, $Y + $H - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

# 3D rounded button using standard Button + shadow Panel
function New-3DButton {
    param(
        [string]$Text,
        [int]$X, [int]$Y, [int]$W, [int]$H,
        $BackColor,
        [scriptblock]$ClickHandler,
        [switch]$Disabled,
        $TextColor = [System.Drawing.Color]::White,
        [int]$FontSize = 10,
        [int]$Radius = 10,
        $PanelBg = $C_BG_CARD
    )
    $shadowGap = 4
    $iW = [int]$W
    $iH = [int]$H
    $iR = [int]$Radius
    $iFs = [int]$FontSize

    $bgColor = if ($Disabled) { $C_FROST_DISABLED } else { $BackColor }
    $fgColor = if ($Disabled) { $C_TEXT_DISABLED } else { $TextColor }

    # Hover/press colors
    $hoverR = [Math]::Min(255, [int]$bgColor.R + 20)
    $hoverG = [Math]::Min(255, [int]$bgColor.G + 20)
    $hoverB = [Math]::Min(255, [int]$bgColor.B + 20)
    $hoverColor = [System.Drawing.Color]::FromArgb($hoverR, $hoverG, $hoverB)
    $downR = [Math]::Max(0, [int]$bgColor.R - 20)
    $downG = [Math]::Max(0, [int]$bgColor.G - 20)
    $downB = [Math]::Max(0, [int]$bgColor.B - 20)
    $downColor = [System.Drawing.Color]::FromArgb($downR, $downG, $downB)

    # Shadow container panel
    $container = New-Object System.Windows.Forms.Panel
    $container.Size = [System.Drawing.Size]::new($iW + $shadowGap, $iH + $shadowGap)
    $container.Location = [System.Drawing.Point]::new($X, $Y)
    $container.BackColor = $PanelBg
    Enable-DoubleBuffer $container

    $container.Tag = @{ BtnW = $iW; BtnH = $iH; Radius = $iR }
    $container.Add_Paint({
        param($sender, $e)
        try {
            $g = $e.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $w = [int]$sender.Tag.BtnW
            $h = [int]$sender.Tag.BtnH
            $r = [int]$sender.Tag.Radius
            for ($si = 1; $si -le 4; $si++) {
                $sa = [int](70 * (5 - $si) / 12)
                if ($sa -lt 3) { continue }
                $sp = New-RoundedRectPath $si $si $w $h $r
                $sb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($sa, 0, 0, 0))
                $g.FillPath($sb, $sp)
                $sb.Dispose()
                $sp.Dispose()
            }
        } catch {}
    })

    # Standard Button - native text rendering guaranteed
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Location = [System.Drawing.Point]::new(0, 0)
    $btn.Size = [System.Drawing.Size]::new($iW, $iH)
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize = 0
    $btn.FlatAppearance.MouseOverBackColor = $hoverColor
    $btn.FlatAppearance.MouseDownBackColor = $downColor
    $btn.BackColor = $bgColor
    $btn.ForeColor = $fgColor
    $btn.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", $iFs, [System.Drawing.FontStyle]::Bold)
    $btn.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btn.TabStop = $false
    Enable-DoubleBuffer $btn

    # Rounded corners via Region
    $rgnPath = New-RoundedRectPath 0 0 $iW $iH $iR
    $btn.Region = New-Object System.Drawing.Region($rgnPath)
    $rgnPath.Dispose()

    if ($Disabled) {
        $btn.Enabled = $false
    }

    if ($ClickHandler -and -not $Disabled) {
        $btn.Add_Click($ClickHandler)
    }

    $container.Controls.Add($btn)

    # Expose button for text updates
    $container | Add-Member -NotePropertyName TextLabel -NotePropertyValue $btn

    return $container
}

# Shadow card container (outer panel draws shadow, inner panel clips rounded corners)
function New-ShadowCard {
    param(
        [int]$X, [int]$Y, [int]$W, [int]$H,
        $BackColor = $C_BG_CARD,
        [int]$Radius = 12,
        [int]$ShadowSize = 6
    )
    $outer = New-Object System.Windows.Forms.Panel
    $outer.Size = [System.Drawing.Size]::new($W + $ShadowSize, $H + $ShadowSize)
    $outer.Location = [System.Drawing.Point]::new($X, $Y)
    $outer.BackColor = $C_BG_PAGE
    Enable-DoubleBuffer $outer

    $outer.Tag = @{ Radius = $Radius; ShadowSize = $ShadowSize; ContentW = $W; ContentH = $H }

    $outer.Add_Paint({
        param($sender, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

        $tag = $sender.Tag
        $w = $tag.ContentW
        $h = $tag.ContentH
        $r = $tag.Radius
        $ss = $tag.ShadowSize

        for ($i = 1; $i -le $ss; $i++) {
            $alpha = [int](80 * ($ss - $i + 1) / ($ss * $ss))
            if ($alpha -lt 2) { continue }
            $sp = New-RoundedRectPath 0 ($i - 1) $w $h $r
            $sb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($alpha, 0, 0, 0))
            $g.FillPath($sb, $sp)
            $sb.Dispose()
            $sp.Dispose()
        }
    })

    $inner = New-Object System.Windows.Forms.Panel
    $inner.Size = [System.Drawing.Size]::new($W, $H)
    $inner.Location = [System.Drawing.Point]::new(0, 0)
    $inner.BackColor = $BackColor
    Enable-DoubleBuffer $inner

    $regionPath = New-RoundedRectPath 0 0 $W $H $Radius
    $inner.Region = New-Object System.Drawing.Region($regionPath)
    $regionPath.Dispose()

    $inner.Tag = @{ Radius = $Radius }
    $inner.Add_Paint({
        param($sender, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $r = $sender.Tag.Radius
        $cardPath = New-RoundedRectPath 0 0 $sender.Width $sender.Height $r
        $borderPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(25, 0, 0, 0), 1)
        $g.DrawPath($borderPen, $cardPath)
        $borderPen.Dispose()
        $cardPath.Dispose()
    })

    $outer.Controls.Add($inner)
    $outer | Add-Member -NotePropertyName InnerPanel -NotePropertyValue $inner

    return $outer
}

function Update-UI {
    if ($Script:AccountListBox -eq $null) { return }
    $Script:AccountListBox.Items.Clear()
    $data = Read-AccountsJson
    $accounts = $data.accounts
    $currentId = $data.currentAccountId
    $count = 0
    if ($accounts.Count -eq 0) {
        $Script:AccountListBox.Items.Add("  （暂无账号 - 点击右侧「新建账号」按钮添加）") | Out-Null
        $Script:AccountCountLabel.Text = "共 0 个账号"
        $Script:CurrentAccountLabel.Text = "当前：未登录"
    } else {
        foreach ($key in $accounts.Keys) {
            $acc = $accounts[$key]
            $isCurrent = ($acc.id -eq $currentId)
            $prefix = if ($isCurrent) { "[当前] " } else { "          " }
            $Script:AccountListBox.Items.Add("$prefix$($acc.name)") | Out-Null
            $count++
            if ($isCurrent) { $Script:CurrentAccountLabel.Text = "当前：$($acc.name)" }
        }
        $Script:AccountCountLabel.Text = "共 $count 个账号"
        if (-not $currentId) { $Script:CurrentAccountLabel.Text = "当前：未设置" }
    }
    $proc = Get-TraeWorkProcess
    if ($proc) { $Script:StatusDot.BackColor = $C_SUCCESS; $Script:StatusLabel.Text = "运行中  PID: $($proc.Id)"; $Script:StatusLabel.ForeColor = $C_SUCCESS }
    else { $Script:StatusDot.BackColor = $C_DANGER; $Script:StatusLabel.Text = "未运行"; $Script:StatusLabel.ForeColor = $C_TEXT_MUTED }
}

function Update-AccountDetail {
    if ($Script:AccountListBox.SelectedItem -eq $null) { $Script:MachineIdLabel.Text = "机器码：-"; $Script:LastUsedLabel.Text = "上次使用：-"; return }
    $selectedText = $Script:AccountListBox.SelectedItem.ToString()
    $data = Read-AccountsJson
    foreach ($key in $data.accounts.Keys) {
        $acc = $data.accounts[$key]
        if ($selectedText -match [regex]::Escape($acc.name)) {
            $midShort = $acc.machineId
            if ($midShort -and $midShort.Length -gt 20) { $midShort = $midShort.Substring(0,8) + "..." + $midShort.Substring($midShort.Length-8) }
            $Script:MachineIdLabel.Text = "机器码：$midShort"
            $Script:LastUsedLabel.Text = "上次使用：$(if ($acc.lastUsedAt) { $acc.lastUsedAt } else { '从未' })"
            break
        }
    }
}

# ============ Core Operations ============
function Do-NewAccount {
    Add-LogLine "=== 开始新建账号流程 ==="
    $name = [Microsoft.VisualBasic.Interaction]::InputBox("请输入新账号名称", "新建账号", "账号$([math]::Floor((Get-Random -Maximum 999)))")
    if ([string]::IsNullOrWhiteSpace($name)) { Add-LogLine "已取消"; return }
    $data = Read-AccountsJson
    if ($data.accounts.ContainsKey($name)) { [System.Windows.Forms.MessageBox]::Show("账号 '$name' 已存在！", "提示", 0, 48); return }
    $accountId = [Guid]::NewGuid().ToString()
    $profileDir = "$Script:ProfilesDir\$accountId"
    Stop-TraeWork
    $newMachineId = Reset-DeviceIdsOnly
    Backup-CurrentProfile $profileDir
    $data.accounts[$name] = @{ id = $accountId; name = $name; machineId = $newMachineId; createdAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss"); lastUsedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss"); notes = "v5" }
    $data.currentAccountId = $accountId
    Save-AccountsJson $data
    Add-LogLine "新账号 '$name' 已创建"
    Start-TraeWork
    Update-UI
    [System.Windows.Forms.MessageBox]::Show("账号 '$name' 已创建！`n`n请使用新账号登录后点击「保存当前登录」。", "已创建", 0, 64)
}

function Do-SaveCurrentLogin {
    Add-LogLine "=== 保存当前登录 ==="
    $data = Read-AccountsJson
    if (-not $data.currentAccountId) { [System.Windows.Forms.MessageBox]::Show("没有当前账号", "提示", 0, 48); return }
    $currentId = $data.currentAccountId
    $accountName = $null
    foreach ($key in $data.accounts.Keys) { if ($data.accounts[$key].id -eq $currentId) { $accountName = $key; break } }
    if (-not $accountName) { [System.Windows.Forms.MessageBox]::Show("未找到当前账号", "提示", 0, 48); return }
    if (Get-TraeWorkProcess) { Add-LogLine "正在关闭 Trae Work 以释放文件锁..."; Stop-TraeWork }
    $profileDir = "$Script:ProfilesDir\$currentId"
    Backup-CurrentProfile $profileDir
    $data.accounts[$accountName].lastUsedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    $data.accounts[$accountName].notes = "v5"
    Save-AccountsJson $data
    Add-LogLine "账号 '$accountName' 登录状态已保存"
    Update-UI
    [System.Windows.Forms.MessageBox]::Show("当前登录状态已保存到账号 '$accountName'", "已保存", 0, 64)
}

function Do-SwitchAccount {
    Add-LogLine "=== 切换账号 ==="
    if ($Script:AccountListBox.SelectedItem -eq $null) { [System.Windows.Forms.MessageBox]::Show("请先选择一个账号", "提示", 0, 48); return }
    $selectedText = $Script:AccountListBox.SelectedItem.ToString()
    $data = Read-AccountsJson
    $targetAccount = $null; $targetKey = $null
    foreach ($key in $data.accounts.Keys) { if ($selectedText -match [regex]::Escape($data.accounts[$key].name)) { $targetAccount = $data.accounts[$key]; $targetKey = $key; break } }
    if (-not $targetAccount) { [System.Windows.Forms.MessageBox]::Show("未找到账号", "提示", 0, 48); return }
    $profileDir = "$Script:ProfilesDir\$($targetAccount.id)"
    if (-not (Test-Path $profileDir)) { [System.Windows.Forms.MessageBox]::Show("配置数据未找到", "提示", 0, 48); return }
    Stop-TraeWork
    Restore-Profile $profileDir $targetAccount.machineId
    $data.currentAccountId = $targetAccount.id
    $data.accounts[$targetKey].lastUsedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    Save-AccountsJson $data
    Add-LogLine "已切换到: $($targetAccount.name)"
    Start-TraeWork
    Update-UI
    [System.Windows.Forms.MessageBox]::Show("已切换到账号 '$($targetAccount.name)'", "已切换", 0, 64)
}

function Do-DeleteAccount {
    if ($Script:AccountListBox.SelectedItem -eq $null) { [System.Windows.Forms.MessageBox]::Show("请先选择一个账号", "提示", 0, 48); return }
    $selectedText = $Script:AccountListBox.SelectedItem.ToString()
    $data = Read-AccountsJson
    $targetKey = $null
    foreach ($key in $data.accounts.Keys) { if ($selectedText -match [regex]::Escape($data.accounts[$key].name)) { $targetKey = $key; break } }
    if (-not $targetKey) { return }
    $confirm = [System.Windows.Forms.MessageBox]::Show("确认删除账号 '$targetKey'？此操作不可撤销。", "确认", 4, 48)
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    $accountId = $data.accounts[$targetKey].id
    $profileDir = "$Script:ProfilesDir\$accountId"
    if (Test-Path $profileDir) { Remove-Item $profileDir -Recurse -Force -ErrorAction SilentlyContinue }
    $data.accounts.Remove($targetKey)
    if ($data.currentAccountId -eq $accountId) { $data.currentAccountId = $null }
    Save-AccountsJson $data
    Add-LogLine "账号 '$targetKey' 已删除"
    Update-UI
}

function Do-SwitchWithNewDevice {
    Add-LogLine "=== 切换并刷新设备 ==="
    if ($Script:AccountListBox.SelectedItem -eq $null) { [System.Windows.Forms.MessageBox]::Show("请先选择一个账号", "提示", 0, 48); return }
    $selectedText = $Script:AccountListBox.SelectedItem.ToString()
    $data = Read-AccountsJson
    $targetAccount = $null; $targetKey = $null
    foreach ($key in $data.accounts.Keys) { if ($selectedText -match [regex]::Escape($data.accounts[$key].name)) { $targetAccount = $data.accounts[$key]; $targetKey = $key; break } }
    if (-not $targetAccount) { return }
    $profileDir = "$Script:ProfilesDir\$($targetAccount.id)"
    if (-not (Test-Path $profileDir)) { [System.Windows.Forms.MessageBox]::Show("配置数据未找到", "提示", 0, 48); return }
    Stop-TraeWork
    Restore-Profile $profileDir $targetAccount.machineId
    $newMachineId = Reset-DeviceIdsOnly
    $data.accounts[$targetKey].machineId = $newMachineId
    $data.currentAccountId = $targetAccount.id
    $data.accounts[$targetKey].lastUsedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    Save-AccountsJson $data
    Backup-CurrentProfile $profileDir
    Add-LogLine "已切换并刷新: $($targetAccount.name), 新机器码: $newMachineId"
    Start-TraeWork
    Update-UI
}

function Create-MainForm {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "TARE多账号切换（免登陆）"
    $form.ClientSize = [System.Drawing.Size]::new(780, 560)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.BackColor = $C_BG_PAGE
    $form.Font = [System.Drawing.Font]::new("Microsoft YaHei UI", 9)
    $form.ShowIcon = $true
    $form.ShowInTaskbar = $true
    Enable-DoubleBuffer $form

    # Window icon - load from custom ICO file
    $icoPath = Join-Path $PSScriptRoot "tare-switcher.ico"
    if (Test-Path $icoPath) {
        try {
            $form.Icon = [System.Drawing.Icon]::new($icoPath)
            Add-LogLine "窗口图标已加载: $icoPath"
        } catch {
            Add-LogLine "[警告] 图标加载失败: $_"
        }
    } else {
        Add-LogLine "[警告] 图标文件不存在: $icoPath"
    }

    # ===== Header Card =====
    $headerCard = New-ShadowCard 16 10 748 60 $C_BG_HEADER 14 8
    $form.Controls.Add($headerCard)
    $hdr = $headerCard.InnerPanel

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = "TARE多账号切换（免登陆）"
    $titleLabel.Font = [System.Drawing.Font]::new("Microsoft YaHei UI", 14, [System.Drawing.FontStyle]::Bold)
    $titleLabel.ForeColor = $C_TEXT_TITLE
    $titleLabel.Location = [System.Drawing.Point]::new(16, 8)
    $titleLabel.Size = [System.Drawing.Size]::new(400, 26)
    $titleLabel.BackColor = $C_BG_HEADER
    $hdr.Controls.Add($titleLabel)

    $versionLabel = New-Object System.Windows.Forms.Label
    $versionLabel.Text = "v5.3  |  立体卡片设计  |  多账号免登录管理"
    $versionLabel.Font = [System.Drawing.Font]::new("Microsoft YaHei UI", 8)
    $versionLabel.ForeColor = $C_TEXT_MUTED
    $versionLabel.Location = [System.Drawing.Point]::new(16, 36)
    $versionLabel.Size = [System.Drawing.Size]::new(400, 16)
    $versionLabel.BackColor = $C_BG_HEADER
    $hdr.Controls.Add($versionLabel)

    # Status indicator
    $Script:StatusDot = New-Object System.Windows.Forms.Panel
    $Script:StatusDot.Size = [System.Drawing.Size]::new(8, 8)
    $Script:StatusDot.Location = [System.Drawing.Point]::new(620, 22)
    $Script:StatusDot.BackColor = $C_DANGER
    $hdr.Controls.Add($Script:StatusDot)

    $Script:StatusLabel = New-Object System.Windows.Forms.Label
    $Script:StatusLabel.Text = "未运行"
    $Script:StatusLabel.Font = [System.Drawing.Font]::new("Microsoft YaHei UI", 9)
    $Script:StatusLabel.ForeColor = $C_TEXT_MUTED
    $Script:StatusLabel.Location = [System.Drawing.Point]::new(634, 18)
    $Script:StatusLabel.Size = [System.Drawing.Size]::new(100, 18)
    $Script:StatusLabel.BackColor = $C_BG_HEADER
    $hdr.Controls.Add($Script:StatusLabel)

    # ===== Current Account Info Card (left) =====
    $infoCard = New-ShadowCard 16 82 480 58 $C_BG_CARD 12 6
    $form.Controls.Add($infoCard)
    $info = $infoCard.InnerPanel

    $Script:CurrentAccountLabel = New-Object System.Windows.Forms.Label
    $Script:CurrentAccountLabel.Text = "当前：未登录"
    $Script:CurrentAccountLabel.Font = [System.Drawing.Font]::new("Microsoft YaHei UI", 12, [System.Drawing.FontStyle]::Bold)
    $Script:CurrentAccountLabel.ForeColor = $C_TEXT_TITLE
    $Script:CurrentAccountLabel.Location = [System.Drawing.Point]::new(14, 6)
    $Script:CurrentAccountLabel.Size = [System.Drawing.Size]::new(340, 26)
    $Script:CurrentAccountLabel.BackColor = $C_BG_CARD
    $info.Controls.Add($Script:CurrentAccountLabel)

    $Script:AccountCountLabel = New-Object System.Windows.Forms.Label
    $Script:AccountCountLabel.Text = "共 0 个账号"
    $Script:AccountCountLabel.Font = [System.Drawing.Font]::new("Microsoft YaHei UI", 9)
    $Script:AccountCountLabel.ForeColor = $C_TEXT_MUTED
    $Script:AccountCountLabel.Location = [System.Drawing.Point]::new(14, 34)
    $Script:AccountCountLabel.Size = [System.Drawing.Size]::new(200, 18)
    $Script:AccountCountLabel.BackColor = $C_BG_CARD
    $info.Controls.Add($Script:AccountCountLabel)

    # Register button (right side of info card, 3D orange)
    $btnRegister = New-3DButton "注册TRAE账号" 520 86 244 50 $C_BTN_REGISTER {
        Start-Process "https://www.trae.cn/work-fission/NXPJLUUKLJVK"
        Add-LogLine "已打开 TRAE 注册页面"
    } -FontSize 11 -Radius 12 -PanelBg $C_BG_PAGE
    $form.Controls.Add($btnRegister)

    # ===== Left: Account List Card =====
    $listCard = New-ShadowCard 16 154 480 288 $C_BG_CARD 12 6
    $form.Controls.Add($listCard)
    $lst = $listCard.InnerPanel

    $listLabel = New-Object System.Windows.Forms.Label
    $listLabel.Text = "已保存的账号"
    $listLabel.Font = [System.Drawing.Font]::new("Microsoft YaHei UI", 10, [System.Drawing.FontStyle]::Bold)
    $listLabel.ForeColor = $C_TEXT_TITLE
    $listLabel.Location = [System.Drawing.Point]::new(14, 10)
    $listLabel.Size = [System.Drawing.Size]::new(200, 22)
    $listLabel.BackColor = $C_BG_CARD
    $lst.Controls.Add($listLabel)

    $Script:AccountListBox = New-Object System.Windows.Forms.ListBox
    $Script:AccountListBox.Location = [System.Drawing.Point]::new(14, 36)
    $Script:AccountListBox.Size = [System.Drawing.Size]::new(452, 168)
    $Script:AccountListBox.Font = [System.Drawing.Font]::new("Microsoft YaHei UI", 11)
    $Script:AccountListBox.BorderStyle = "FixedSingle"
    $Script:AccountListBox.BackColor = $C_BG_INPUT
    $Script:AccountListBox.Add_SelectedIndexChanged({ Update-AccountDetail })
    $lst.Controls.Add($Script:AccountListBox)

    # Account detail
    $Script:MachineIdLabel = New-Object System.Windows.Forms.Label
    $Script:MachineIdLabel.Text = "机器码：-"
    $Script:MachineIdLabel.Font = [System.Drawing.Font]::new("Microsoft YaHei UI", 9)
    $Script:MachineIdLabel.ForeColor = $C_TEXT_MUTED
    $Script:MachineIdLabel.Location = [System.Drawing.Point]::new(14, 212)
    $Script:MachineIdLabel.Size = [System.Drawing.Size]::new(452, 18)
    $Script:MachineIdLabel.BackColor = $C_BG_CARD
    $lst.Controls.Add($Script:MachineIdLabel)

    $Script:LastUsedLabel = New-Object System.Windows.Forms.Label
    $Script:LastUsedLabel.Text = "上次使用：-"
    $Script:LastUsedLabel.Font = [System.Drawing.Font]::new("Microsoft YaHei UI", 9)
    $Script:LastUsedLabel.ForeColor = $C_TEXT_MUTED
    $Script:LastUsedLabel.Location = [System.Drawing.Point]::new(14, 234)
    $Script:LastUsedLabel.Size = [System.Drawing.Size]::new(452, 18)
    $Script:LastUsedLabel.BackColor = $C_BG_CARD
    $lst.Controls.Add($Script:LastUsedLabel)

    # ===== Right: Action Buttons Card =====
    $btnCard = New-ShadowCard 520 154 244 288 $C_BG_CARD 12 6
    $form.Controls.Add($btnCard)
    $btns = $btnCard.InnerPanel

    $btnX = 16
    $btnW = 212
    $btnH = 38
    $btnGap = 8
    $btnStartY = 14

    $btnNew = New-3DButton "新建账号（重置设备）" $btnX $btnStartY $btnW $btnH $C_FROST_PRIMARY {
        Do-NewAccount
    } -FontSize 10
    $btns.Controls.Add($btnNew)

    $btnSave = New-3DButton "保存当前登录" $btnX ($btnStartY + $btnH + $btnGap) $btnW $btnH $C_FROST_SUCCESS {
        Do-SaveCurrentLogin
    } -FontSize 10
    $btns.Controls.Add($btnSave)

    $btnSwitch = New-3DButton "切换到选中账号" $btnX ($btnStartY + ($btnH + $btnGap) * 2) $btnW $btnH $C_FROST_WARN {
        Do-SwitchAccount
    } -FontSize 10
    $btns.Controls.Add($btnSwitch)

    $btnSwitchNew = New-3DButton "切换+刷新设备（开发中）" $btnX ($btnStartY + ($btnH + $btnGap) * 3) $btnW $btnH $C_FROST_ACCENT -Disabled -FontSize 9
    $btns.Controls.Add($btnSwitchNew)

    $btnDelete = New-3DButton "删除选中账号" $btnX ($btnStartY + ($btnH + $btnGap) * 4) $btnW $btnH $C_FROST_DANGER {
        Do-DeleteAccount
    } -FontSize 10
    $btns.Controls.Add($btnDelete)

    $btnRefresh = New-3DButton "刷新状态" $btnX ($btnStartY + ($btnH + $btnGap) * 5) $btnW 30 $C_FROST_NEUTRAL {
        Update-UI
        Add-LogLine "状态已刷新"
    } -FontSize 9 -Radius 8
    $btns.Controls.Add($btnRefresh)

    # ===== Log Toggle Button (collapsed by default) =====
    $Script:LogVisible = $false
    $Script:LogToggleButton = New-3DButton "[+] 查看操作日志" 16 452 220 28 $C_FROST_NEUTRAL {
        $Script:LogVisible = -not $Script:LogVisible
        if ($Script:LogVisible) {
            $Script:LogTextBox.Visible = $true
            $Script:LogToggleButton.TextLabel.Text = "[-] 隐藏操作日志"
            $Script:LogToggleButton.TextLabel.Invalidate()
            $Script:MainForm.ClientSize = [System.Drawing.Size]::new(780, 740)
        } else {
            $Script:LogTextBox.Visible = $false
            $Script:LogToggleButton.TextLabel.Text = "[+] 查看操作日志"
            $Script:LogToggleButton.TextLabel.Invalidate()
            $Script:MainForm.ClientSize = [System.Drawing.Size]::new(780, 560)
        }
        $Script:LogToggleButton.Invalidate()
    } -FontSize 9 -Radius 8 -PanelBg $C_BG_PAGE
    $form.Controls.Add($Script:LogToggleButton)

    # ===== Help text (right side of log button) =====
    $helpLabel = New-Object System.Windows.Forms.Label
    $helpLabel.Text = "使用说明：`n  1. 新建账号 -> 启动TW -> 登录 -> 保存当前登录`n  2. 切换账号 -> 恢复完整登录状态 -> 免验证码自动登录`n  3. 积分功能开发中"
    $helpLabel.Font = [System.Drawing.Font]::new("Microsoft YaHei UI", 8)
    $helpLabel.ForeColor = $C_TEXT_MUTED
    $helpLabel.Location = [System.Drawing.Point]::new(250, 448)
    $helpLabel.Size = [System.Drawing.Size]::new(514, 72)
    $helpLabel.BackColor = $C_BG_PAGE
    $form.Controls.Add($helpLabel)

    # ===== Log Area (hidden by default) =====
    $Script:LogTextBox = New-Object System.Windows.Forms.TextBox
    $Script:LogTextBox.Location = [System.Drawing.Point]::new(16, 530)
    $Script:LogTextBox.Size = [System.Drawing.Size]::new(748, 194)
    $Script:LogTextBox.Multiline = $true
    $Script:LogTextBox.ScrollBars = "Vertical"
    $Script:LogTextBox.ReadOnly = $true
    $Script:LogTextBox.Font = [System.Drawing.Font]::new("Consolas", 8)
    $Script:LogTextBox.BackColor = $C_BG_LOG
    $Script:LogTextBox.ForeColor = [System.Drawing.Color]::FromArgb(180, 230, 180)
    $Script:LogTextBox.Visible = $false
    $form.Controls.Add($Script:LogTextBox)

    $Script:MainForm = $form
    return $form
}

# ============ Start ============
Add-Type -AssemblyName Microsoft.VisualBasic
Initialize-Storage

$form = Create-MainForm
Update-UI
Add-LogLine "TARE多账号切换 v5.3 已启动"
Add-LogLine "v5.3: 立体卡片设计 | 圆角阴影按钮 | 日志折叠 | 自定义图标"

[void]$form.ShowDialog()

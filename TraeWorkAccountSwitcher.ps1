<#
.SYNOPSIS
    Trae Work 账号切换工具
.DESCRIPTION
    管理 Trae Work (TRAE SOLO CN) 多账号，每个账号绑定独立机器码，一键切换无需验证码。
    
    工作原理：
    1. 保存每个账号的完整配置快照（storage.json, machineid, aha/TinyStorage, Local Storage, 网络会话等）
    2. 切换时：关闭 Trae Work → 写入目标账号的配置 → 清理缓存 → 启动 Trae Work
    3. 每个账号自动分配独立机器码，无需手动设置

.NOTES
    作者: Trae Account Switcher
    版本: 1.0.0
    数据目录: %APPDATA%\TRAE SOLO CN\
    配置文件: %APPDATA%\TraeWorkSwitcher\accounts.json
#>

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('menu', 'add', 'list', 'switch', 'delete', 'export', 'import')]
    [string]$Command = 'menu',

    [Parameter(Mandatory = $false)]
    [string]$Name,

    [Parameter(Mandatory = $false)]
    [string]$Token,

    [Parameter(Mandatory = $false)]
    [string]$MachineId
)

# ============ 配置 ============
$Script:TraeDataDir = "$env:APPDATA\TRAE SOLO CN"
$Script:SwitcherDir = "$env:APPDATA\TraeWorkSwitcher"
$Script:AccountsFile = "$Script:SwitcherDir\accounts.json"
$Script:ProfilesDir = "$Script:SwitcherDir\profiles"
$Script:LogFile = "$Script:SwitcherDir\switcher.log"

# ============ 日志 ============
function Write-Log {
    param([string]$Message)
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $log = "[$time] $Message"
    Write-Host $log
    if (-not (Test-Path $Script:SwitcherDir)) { New-Item -ItemType Directory -Force -Path $Script:SwitcherDir | Out-Null }
    Add-Content -Path $Script:LogFile -Value $log -Encoding UTF8
}

# ============ 工具函数 ============
function Get-TraeWorkPath {
    <#
    .SYNOPSIS
        自动检测 Trae Work 可执行文件路径
    #>
    $commonPaths = @(
        "$env:LOCALAPPDATA\Programs\TRAE SOLO CN\TRAE SOLO CN.exe",
        "$env:LOCALAPPDATA\Programs\TRAE SOLO\TRAE SOLO.exe",
        "C:\Program Files\TRAE SOLO CN\TRAE SOLO CN.exe",
        "C:\Program Files\TRAE SOLO\TRAE SOLO.exe"
    )
    
    # 尝试从开始菜单查找
    $startMenuPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\TRAE SOLO CN"
    if (Test-Path $startMenuPath) {
        $lnk = Get-ChildItem $startMenuPath -Filter "*.lnk" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($lnk) {
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($lnk.FullName)
            if ($shortcut.TargetPath -and (Test-Path $shortcut.TargetPath)) {
                return $shortcut.TargetPath
            }
        }
    }

    foreach ($p in $commonPaths) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function New-MachineId {
    <#
    .SYNOPSIS
        生成新的 UUID 格式机器码
    #>
    return [Guid]::NewGuid().ToString().ToLower()
}

function Get-TraeWorkProcess {
    <#
    .SYNOPSIS
        检查 Trae Work 进程是否在运行
    #>
    return Get-Process -Name "TRAE SOLO CN" -ErrorAction SilentlyContinue
}

function Stop-TraeWork {
    <#
    .SYNOPSIS
        关闭 Trae Work 进程
    #>
    Write-Log "正在关闭 Trae Work..."
    
    $proc = Get-TraeWorkProcess
    if (-not $proc) {
        Write-Log "Trae Work 未运行"
        return
    }

    # 先尝试优雅关闭
    $proc.CloseMainWindow() | Out-Null
    Start-Sleep -Seconds 2

    # 如果还在运行，强制关闭
    $proc = Get-TraeWorkProcess
    if ($proc) {
        $proc | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    # 确保所有相关进程退出
    $remaining = Get-TraeWorkProcess
    if ($remaining) {
        Write-Log "警告: 部分进程仍存在，等待退出..."
        Start-Sleep -Seconds 3
        $remaining | Stop-Process -Force -ErrorAction SilentlyContinue
    }

    Write-Log "Trae Work 已关闭"
}

function Start-TraeWork {
    <#
    .SYNOPSIS
        启动 Trae Work
    #>
    $exePath = Get-TraeWorkPath
    if (-not $exePath) {
        Write-Log "错误: 未找到 Trae Work 可执行文件"
        return $false
    }
    Write-Log "正在启动 Trae Work: $exePath"
    try {
        Start-Process -FilePath $exePath
        Write-Log "Trae Work 已启动"
        return $true
    } catch {
        Write-Log "启动失败: $_"
        return $false
    }
}

# ============ 账号配置管理 ============

function Initialize-Storage {
    <#
    .SYNOPSIS
        初始化存储结构
    #>
    if (-not (Test-Path $Script:SwitcherDir)) {
        New-Item -ItemType Directory -Force -Path $Script:SwitcherDir | Out-Null
        Write-Log "已创建配置目录: $($Script:SwitcherDir)"
    }
    if (-not (Test-Path $Script:ProfilesDir)) {
        New-Item -ItemType Directory -Force -Path $Script:ProfilesDir | Out-Null
    }
    if (-not (Test-Path $Script:AccountsFile)) {
        $initial = @{ accounts = @{}; currentAccountId = $null }
        $initial | ConvertTo-Json -Depth 10 | Set-Content -Path $Script:AccountsFile -Encoding UTF8
        Write-Log "已创建账号文件: $($Script:AccountsFile)"
    }
}

function Get-Accounts {
    <#
    .SYNOPSIS
        获取所有账号列表
    #>
    Initialize-Storage
    $data = Get-Content $Script:AccountsFile -Encoding UTF8 | ConvertFrom-Json
    return $data.accounts
}

function Save-Accounts {
    param($Accounts, $CurrentId)
    $data = @{ accounts = $Accounts; currentAccountId = $CurrentId }
    $data | ConvertTo-Json -Depth 10 | Set-Content -Path $Script:AccountsFile -Encoding UTF8
}

function Backup-CurrentProfile {
    <#
    .SYNOPSIS
        备份当前 Trae Work 账号配置到 profile 目录
    #>
    param([string]$ProfileDir)

    Write-Log "备份当前账号配置到: $ProfileDir"
    New-Item -ItemType Directory -Force -Path $ProfileDir | Out-Null

    # 1. 备份 storage.json
    $storageJson = "$Script:TraeDataDir\User\globalStorage\storage.json"
    if (Test-Path $storageJson) {
        Copy-Item $storageJson "$ProfileDir\storage.json" -Force
        Write-Log "已备份 storage.json"
    }

    # 2. 备份 machineid
    $machineIdFile = "$Script:TraeDataDir\machineid"
    if (Test-Path $machineIdFile) {
        Copy-Item $machineIdFile "$ProfileDir\machineid" -Force
        Write-Log "已备份 machineid"
    }

    # 3. 备份 aha/TinyStorage
    $tinyStorage = "$Script:TraeDataDir\aha\TinyStorage"
    if (Test-Path $tinyStorage) {
        $ahaDir = "$ProfileDir\aha"
        New-Item -ItemType Directory -Force -Path $ahaDir | Out-Null
        Copy-Item $tinyStorage "$ahaDir\TinyStorage" -Force
        Write-Log "已备份 aha/TinyStorage"
    }

    # 4. 备份 Local Storage (leveldb) - 包含 cookies/session
    $localStorage = "$Script:TraeDataDir\Local Storage\leveldb"
    if (Test-Path $localStorage) {
        $lsDir = "$ProfileDir\LocalStorage\leveldb"
        New-Item -ItemType Directory -Force -Path $lsDir | Out-Null
        Copy-Item "$localStorage\*" $lsDir -Force -ErrorAction SilentlyContinue
        Write-Log "已备份 Local Storage"
    }

    # 5. 备份 Network 目录 (cookies)
    $networkDir = "$Script:TraeDataDir\Network"
    if (Test-Path $networkDir) {
        $netDir = "$ProfileDir\Network"
        New-Item -ItemType Directory -Force -Path $netDir | Out-Null
        Copy-Item "$networkDir\*" $netDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "已备份 Network 会话"
    }

    # 6. 备份 Partitions/trae-webview 的 Local Storage
    $webviewLS = "$Script:TraeDataDir\Partitions\trae-webview\Local Storage\leveldb"
    if (Test-Path $webviewLS) {
        $wvDir = "$ProfileDir\Partitions\trae-webview\LocalStorage\leveldb"
        New-Item -ItemType Directory -Force -Path $wvDir | Out-Null
        Copy-Item "$webviewLS\*" $wvDir -Force -ErrorAction SilentlyContinue
        Write-Log "已备份 Webview Local Storage"
    }
}

function Restore-Profile {
    <#
    .SYNOPSIS
        将指定 profile 恢复到 Trae Work 数据目录
    #>
    param([string]$ProfileDir, [string]$MachineId)

    Write-Log "恢复账号配置..."

    # 1. 写入 machineid（每个账号独立）
    $machineIdFile = "$Script:TraeDataDir\machineid"
    $machineIdDir = Split-Path $machineIdFile -Parent
    if (-not (Test-Path $machineIdDir)) { New-Item -ItemType Directory -Force -Path $machineIdDir | Out-Null }
    Set-Content -Path $machineIdFile -Value $MachineId -Force -Encoding UTF8
    Write-Log "已写入机器码: $MachineId"

    # 2. 恢复 storage.json
    $profileStorage = "$ProfileDir\storage.json"
    $targetStorage = "$Script:TraeDataDir\User\globalStorage\storage.json"
    $targetDir = Split-Path $targetStorage -Parent
    if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Force -Path $targetDir | Out-Null }
    
    if (Test-Path $profileStorage) {
        Copy-Item $profileStorage $targetStorage -Force
        Write-Log "已恢复 storage.json"
    }

    # 3. 恢复 aha/TinyStorage
    $profileTiny = "$ProfileDir\aha\TinyStorage"
    $targetTiny = "$Script:TraeDataDir\aha\TinyStorage"
    $targetAhaDir = Split-Path $targetTiny -Parent
    if (Test-Path $profileTiny) {
        if (-not (Test-Path $targetAhaDir)) { New-Item -ItemType Directory -Force -Path $targetAhaDir | Out-Null }
        Copy-Item $profileTiny $targetTiny -Force
        Write-Log "已恢复 aha/TinyStorage"
    }

    # 4. 恢复 Local Storage - 先清空再写入
    $profileLS = "$ProfileDir\LocalStorage\leveldb"
    $targetLS = "$Script:TraeDataDir\Local Storage\leveldb"
    if (Test-Path $profileLS) {
        if (Test-Path $targetLS) { Remove-Item "$targetLS\*" -Force -ErrorAction SilentlyContinue }
        else { New-Item -ItemType Directory -Force -Path $targetLS | Out-Null }
        Copy-Item "$profileLS\*" $targetLS -Force -ErrorAction SilentlyContinue
        Write-Log "已恢复 Local Storage"
    }

    # 5. 恢复 Network 目录
    $profileNet = "$ProfileDir\Network"
    $targetNet = "$Script:TraeDataDir\Network"
    if (Test-Path $profileNet) {
        if (Test-Path $targetNet) { Remove-Item "$targetNet\*" -Recurse -Force -ErrorAction SilentlyContinue }
        else { New-Item -ItemType Directory -Force -Path $targetNet | Out-Null }
        Copy-Item "$profileNet\*" $targetNet -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "已恢复 Network 会话"
    }

    # 6. 恢复 Partitions/trae-webview
    $profileWV = "$ProfileDir\Partitions\trae-webview\LocalStorage\leveldb"
    $targetWV = "$Script:TraeDataDir\Partitions\trae-webview\Local Storage\leveldb"
    if (Test-Path $profileWV) {
        if (Test-Path $targetWV) { Remove-Item "$targetWV\*" -Force -ErrorAction SilentlyContinue }
        else { New-Item -ItemType Directory -Force -Path $targetWV | Out-Null }
        Copy-Item "$profileWV\*" $targetWV -Force -ErrorAction SilentlyContinue
        Write-Log "已恢复 Webview Local Storage"
    }
}

function Clear-TraeCache {
    <#
    .SYNOPSIS
        清理 Trae Work 缓存，强制重新加载登录状态
    #>
    Write-Log "清理缓存..."

    # 删除 state.vscdb 和 state.vscdb.backup（VS Code 状态的 SQLite 数据库）
    $filesToDelete = @(
        "$Script:TraeDataDir\User\globalStorage\state.vscdb",
        "$Script:TraeDataDir\User\globalStorage\state.vscdb.backup",
        "$Script:TraeDataDir\Local State",
        "$Script:TraeDataDir\Cookies",
        "$Script:TraeDataDir\Cookies-journal"
    )

    $dirsToDelete = @(
        "$Script:TraeDataDir\Session Storage",
        "$Script:TraeDataDir\IndexedDB",
        "$Script:TraeDataDir\Service Worker",
        "$Script:TraeDataDir\Cache",
        "$Script:TraeDataDir\Code Cache",
        "$Script:TraeDataDir\GPUCache",
        "$Script:TraeDataDir\DawnGraphiteCache",
        "$Script:TraeDataDir\DawnWebGPUCache",
        "$Script:TraeDataDir\Shared Dictionary",
        "$Script:TraeDataDir\VideoDecodeStats",
        "$Script:TraeDataDir\blob_storage",
        "$Script:TraeDataDir\WebStorage"
    )

    foreach ($f in $filesToDelete) {
        if (Test-Path $f) {
            Remove-Item $f -Force -ErrorAction SilentlyContinue
            Write-Log "已删除: $(Split-Path $f -Leaf)"
        }
    }

    foreach ($d in $dirsToDelete) {
        if (Test-Path $d) {
            Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "已删除目录: $(Split-Path $d -Leaf)"
        }
    }
}

# ============ 账号操作 ============

function Add-Account {
    <#
    .SYNOPSIS
        添加新账号（从当前 Trae Work 登录状态捕获）
    #>
    param(
        [string]$AccountName,
        [string]$CustomMachineId
    )

    Initialize-Storage
    $accounts = Get-Accounts

    # 检查是否已存在同名账号
    if ($accounts.PSObject.Properties.Name -contains $AccountName) {
        Write-Log "错误: 账号 '$AccountName' 已存在"
        return $false
    }

    # 生成机器码
    $machineId = if ($CustomMachineId) { $CustomMachineId } else { New-MachineId }

    $accountId = [Guid]::NewGuid().ToString()
    $profileDir = "$Script:ProfilesDir\$accountId"

    # 备份当前配置
    Backup-CurrentProfile -ProfileDir $profileDir

    # 保存账号信息
    $account = @{
        id = $accountId
        name = $AccountName
        machineId = $machineId
        createdAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        lastUsedAt = $null
        notes = "通过 Trae Work 登录状态捕获"
    }

    $accounts.PSObject.Properties.Add([PSCustomObject]@{
        Name = $AccountName
        Value = $account
    })

    Save-Accounts -Accounts $accounts -CurrentId $null
    Write-Log "账号 '$AccountName' 添加成功！机器码: $machineId"
    Write-Log "提示: 如需切换到此账号，请执行切换命令"
    return $true
}

function Add-AccountManual {
    <#
    .SYNOPSIS
        手动添加账号（需要提供 storage.json 和 machineid）
    #>
    param(
        [string]$AccountName,
        [string]$StorageJsonPath,
        [string]$MachineIdFile
    )

    Initialize-Storage
    $accounts = Get-Accounts

    if ($accounts.PSObject.Properties.Name -contains $AccountName) {
        Write-Log "错误: 账号 '$AccountName' 已存在"
        return $false
    }

    $machineId = if (Test-Path $MachineIdFile) {
        Get-Content $MachineIdFile -Encoding UTF8 -Raw | ForEach-Object { $_.Trim() }
    } else {
        New-MachineId
    }

    $accountId = [Guid]::NewGuid().ToString()
    $profileDir = "$Script:ProfilesDir\$accountId"
    New-Item -ItemType Directory -Force -Path $profileDir | Out-Null

    # 复制提供的文件
    if (Test-Path $StorageJsonPath) {
        Copy-Item $StorageJsonPath "$profileDir\storage.json" -Force
    }

    $account = @{
        id = $accountId
        name = $AccountName
        machineId = $machineId
        createdAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        lastUsedAt = $null
        notes = "手动添加"
    }

    $accounts.PSObject.Properties.Add([PSCustomObject]@{
        Name = $AccountName
        Value = $account
    })

    Save-Accounts -Accounts $accounts -CurrentId $null
    Write-Log "账号 '$AccountName' 手动添加成功！"
    return $true
}

function Switch-Account {
    <#
    .SYNOPSIS
        切换到指定账号
    #>
    param([string]$AccountName)

    Initialize-Storage
    $data = Get-Content $Script:AccountsFile -Encoding UTF8 | ConvertFrom-Json
    $accounts = $data.accounts

    if (-not ($accounts.PSObject.Properties.Name -contains $AccountName)) {
        Write-Log "错误: 账号 '$AccountName' 不存在"
        return $false
    }

    $account = $accounts.$AccountName
    $profileDir = "$Script:ProfilesDir\$($account.id)"

    if (-not (Test-Path $profileDir)) {
        Write-Log "错误: 账号 '$AccountName' 的配置数据不存在，请重新添加"
        return $false
    }

    Write-Log "=========================================="
    Write-Log "开始切换账号: $AccountName"
    Write-Log "机器码: $($account.machineId)"

    # 1. 关闭 Trae Work
    Stop-TraeWork

    # 2. 恢复配置
    Restore-Profile -ProfileDir $profileDir -MachineId $account.machineId

    # 3. 清理缓存
    Clear-TraeCache

    # 4. 更新最后使用时间
    $account.lastUsedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    $data.currentAccountId = $account.id
    $data | ConvertTo-Json -Depth 10 | Set-Content -Path $Script:AccountsFile -Encoding UTF8

    # 5. 启动 Trae Work
    Start-TraeWork

    Write-Log "账号切换完成: $AccountName"
    Write-Log "=========================================="
    return $true
}

function Delete-Account {
    <#
    .SYNOPSIS
        删除指定账号
    #>
    param([string]$AccountName)

    Initialize-Storage
    $data = Get-Content $Script:AccountsFile -Encoding UTF8 | ConvertFrom-Json
    $accounts = $data.accounts

    if (-not ($accounts.PSObject.Properties.Name -contains $AccountName)) {
        Write-Log "错误: 账号 '$AccountName' 不存在"
        return $false
    }

    $account = $accounts.$AccountName
    $profileDir = "$Script:ProfilesDir\$($account.id)"

    # 删除配置
    if (Test-Path $profileDir) {
        Remove-Item $profileDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 从列表中移除
    $accounts.PSObject.Properties.Remove($AccountName)

    # 如果删除的是当前账号，重置
    $currentId = if ($data.currentAccountId -eq $account.id) { $null } else { $data.currentAccountId }
    Save-Accounts -Accounts $accounts -CurrentId $currentId

    Write-Log "账号 '$AccountName' 已删除"
    return $true
}

function Export-Accounts {
    <#
    .SYNOPSIS
        导出账号数据
    #>
    $exportPath = "$Script:SwitcherDir\accounts_export.json"
    Copy-Item $Script:AccountsFile $exportPath -Force
    Write-Log "账号数据已导出到: $exportPath"
    return $exportPath
}

function Import-Accounts {
    <#
    .SYNOPSIS
        导入账号数据
    #>
    param([string]$ImportPath)

    if (-not (Test-Path $ImportPath)) {
        Write-Log "错误: 导入文件不存在: $ImportPath"
        return $false
    }

    Copy-Item $ImportPath $Script:AccountsFile -Force
    Write-Log "账号数据已导入"
    return $true
}

# ============ 交互菜单 ============

function Show-Menu {
    Clear-Host
    Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║     🔑 Trae Work 账号切换工具 v1.0       ║" -ForegroundColor Cyan
    Write-Host "║      每个账号绑定独立机器码              ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # 显示当前状态
    $proc = Get-TraeWorkProcess
    $status = if ($proc) { "🟢 运行中 (PID: $($proc.Id))" } else { "🔴 未运行" }
    Write-Host "Trae Work 状态: $status" -ForegroundColor $(if ($proc) { "Green" } else { "Red" })
    
    $exePath = Get-TraeWorkPath
    if ($exePath) {
        Write-Host "安装路径: $exePath" -ForegroundColor Gray
    } else {
        Write-Host "安装路径: 未检测到" -ForegroundColor Yellow
    }
    Write-Host "数据目录: $Script:TraeDataDir" -ForegroundColor Gray
    Write-Host ""

    # 显示账号列表
    Initialize-Storage
    $data = Get-Content $Script:AccountsFile -Encoding UTF8 | ConvertFrom-Json
    $accounts = $data.accounts
    $currentId = $data.currentAccountId

    if ($accounts.PSObject.Properties.Count -eq 0) {
        Write-Host "📭 暂无账号" -ForegroundColor Yellow
        Write-Host "  提示: 先登录 Trae Work，然后选择 [1] 添加当前账号" -ForegroundColor DarkGray
    } else {
        Write-Host "📋 账号列表:" -ForegroundColor White
        Write-Host ("─" * 50) -ForegroundColor DarkGray
        $i = 1
        foreach ($prop in $accounts.PSObject.Properties) {
            $acc = $prop.Value
            $isCurrent = ($acc.id -eq $currentId)
            $prefix = if ($isCurrent) { "👉" } else { "  " }
            $marker = if ($isCurrent) { " [当前使用]" } else { "" }
            $machineShort = $acc.machineId.Substring(0, [Math]::Min(8, $acc.machineId.Length)) + "..."
            
            Write-Host "$prefix $i. $($acc.name)$marker" -ForegroundColor $(if ($isCurrent) { "Green" } else { "White" })
            Write-Host "     机器码: $machineShort" -ForegroundColor Gray
            if ($acc.lastUsedAt) { Write-Host "     上次使用: $($acc.lastUsedAt)" -ForegroundColor Gray }
            $i++
        }
        Write-Host ("─" * 50) -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "══════════════ 操作菜单 ══════════════" -ForegroundColor Cyan
    Write-Host "  [1] 添加当前账号" -ForegroundColor White
    Write-Host "  [2] 切换账号" -ForegroundColor White
    Write-Host "  [3] 删除账号" -ForegroundColor White
    Write-Host "  [4] 刷新列表" -ForegroundColor White
    Write-Host "  [5] 查看日志" -ForegroundColor White
    Write-Host "  [6] 导出/导入" -ForegroundColor White
    Write-Host "  [7] 打开配置目录" -ForegroundColor White
    Write-Host "  [Q] 退出" -ForegroundColor White
    Write-Host "══════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    $choice = Read-Host "请输入选项"
    
    switch ($choice.ToUpper()) {
        '1' { Show-AddAccountMenu }
        '2' { Show-SwitchMenu }
        '3' { Show-DeleteMenu }
        '4' { Show-Menu }
        '5' { Show-Logs }
        '6' { Show-ImportExportMenu }
        '7' { 
            explorer $Script:SwitcherDir
            Start-Sleep 1
            Show-Menu 
        }
        'Q' { 
            Write-Host "再见！" -ForegroundColor Cyan
            exit 
        }
        default {
            Write-Host "无效选项，请重新选择" -ForegroundColor Red
            Start-Sleep 1
            Show-Menu
        }
    }
}

function Show-AddAccountMenu {
    Clear-Host
    Write-Host "📥 添加当前账号" -ForegroundColor Cyan
    Write-Host "提示: 请确保 Trae Work 已登录目标账号" -ForegroundColor Yellow
    Write-Host ""

    $name = Read-Host "请输入账号名称（如: 账号1）"
    if (-not $name) { Write-Host "已取消"; Start-Sleep 1; Show-Menu; return }

    $customMachine = Read-Host "是否自定义机器码？留空自动生成 (Enter 跳过)"
    
    Add-Account -AccountName $name -CustomMachineId $customMachine
    
    Write-Host ""
    Write-Host "按任意键返回菜单..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Show-Menu
}

function Show-SwitchMenu {
    Clear-Host
    Write-Host "🔄 切换账号" -ForegroundColor Cyan
    Write-Host ""
    
    Initialize-Storage
    $data = Get-Content $Script:AccountsFile -Encoding UTF8 | ConvertFrom-Json
    $accounts = $data.accounts

    if ($accounts.PSObject.Properties.Count -eq 0) {
        Write-Host "暂无账号，请先添加账号" -ForegroundColor Yellow
        Write-Host "按任意键返回..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        Show-Menu
        return
    }

    $i = 1
    $nameList = @()
    foreach ($prop in $accounts.PSObject.Properties) {
        $acc = $prop.Value
        $isCurrent = ($acc.id -eq $data.currentAccountId)
        $marker = if ($isCurrent) { " [当前]" } else { "" }
        Write-Host "  [$i] $($acc.name)$marker" -ForegroundColor $(if ($isCurrent) { "Green" } else { "White" })
        $nameList += $prop.Name
        $i++
    }
    Write-Host "  [0] 返回" -ForegroundColor Gray
    Write-Host ""

    $choice = Read-Host "请选择要切换的账号编号"
    if ($choice -eq '0') { Show-Menu; return }

    $index = [int]$choice - 1
    if ($index -lt 0 -or $index -ge $nameList.Count) {
        Write-Host "无效选项" -ForegroundColor Red
        Start-Sleep 1
        Show-SwitchMenu
        return
    }

    $selectedName = $nameList[$index]
    $selectedAcc = $accounts.$selectedName

    if ($selectedAcc.id -eq $data.currentAccountId) {
        Write-Host "该账号已经是当前账号！" -ForegroundColor Yellow
        Start-Sleep 1
        Show-SwitchMenu
        return
    }

    Write-Host ""
    Write-Host "⚠️  即将切换到账号: $selectedName" -ForegroundColor Yellow
    Write-Host "⚠️  切换前请保存工作内容" -ForegroundColor Yellow
    $confirm = Read-Host "确认切换？(Y/N)"
    
    if ($confirm.ToUpper() -ne 'Y') {
        Write-Host "已取消" -ForegroundColor Gray
        Start-Sleep 1
        Show-SwitchMenu
        return
    }

    Switch-Account -AccountName $selectedName

    Write-Host ""
    Write-Host "按任意键返回菜单..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Show-Menu
}

function Show-DeleteMenu {
    Clear-Host
    Write-Host "🗑️ 删除账号" -ForegroundColor Cyan
    Write-Host ""

    Initialize-Storage
    $data = Get-Content $Script:AccountsFile -Encoding UTF8 | ConvertFrom-Json
    $accounts = $data.accounts

    if ($accounts.PSObject.Properties.Count -eq 0) {
        Write-Host "暂无账号" -ForegroundColor Yellow
        Write-Host "按任意键返回..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        Show-Menu
        return
    }

    $i = 1
    $nameList = @()
    foreach ($prop in $accounts.PSObject.Properties) {
        $acc = $prop.Value
        $isCurrent = ($acc.id -eq $data.currentAccountId)
        $marker = if ($isCurrent) { " [当前]" } else { "" }
        Write-Host "  [$i] $($acc.name)$marker"
        $nameList += $prop.Name
        $i++
    }
    Write-Host "  [0] 返回" -ForegroundColor Gray
    Write-Host ""

    $choice = Read-Host "请选择要删除的账号编号"
    if ($choice -eq '0') { Show-Menu; return }

    $index = [int]$choice - 1
    if ($index -lt 0 -or $index -ge $nameList.Count) {
        Write-Host "无效选项" -ForegroundColor Red
        Start-Sleep 1
        Show-DeleteMenu
        return
    }

    $selectedName = $nameList[$index]
    $confirm = Read-Host "确认删除账号 '$selectedName'？此操作不可恢复！(Y/N)"
    
    if ($confirm.ToUpper() -ne 'Y') {
        Write-Host "已取消" -ForegroundColor Gray
        Start-Sleep 1
        Show-DeleteMenu
        return
    }

    Delete-Account -AccountName $selectedName

    Write-Host ""
    Write-Host "按任意键返回菜单..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Show-Menu
}

function Show-Logs {
    Clear-Host
    Write-Host "📄 操作日志" -ForegroundColor Cyan
    Write-Host ""

    if (Test-Path $Script:LogFile) {
        Get-Content $Script:LogFile -Encoding UTF8 -Tail 30
    } else {
        Write-Host "暂无日志" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "按任意键返回菜单..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Show-Menu
}

function Show-ImportExportMenu {
    Clear-Host
    Write-Host "📦 导入/导出" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [1] 导出账号数据" -ForegroundColor White
    Write-Host "  [2] 导入账号数据" -ForegroundColor White
    Write-Host "  [0] 返回" -ForegroundColor Gray
    Write-Host ""

    $choice = Read-Host "请选择"
    switch ($choice) {
        '1' {
            $path = Export-Accounts
            Write-Host "已导出到: $path" -ForegroundColor Green
            Start-Sleep 1
            Show-ImportExportMenu
        }
        '2' {
            $path = Read-Host "请输入导入文件路径"
            Import-Accounts -ImportPath $path
            Start-Sleep 1
            Show-ImportExportMenu
        }
        '0' { Show-Menu }
        default {
            Write-Host "无效选项" -ForegroundColor Red
            Start-Sleep 1
            Show-ImportExportMenu
        }
    }
}

# ============ 命令行入口 ============

function Main {
    switch ($Command) {
        'menu' { Show-Menu }
        'add' {
            if (-not $Name) {
                Write-Host "用法: .\TraeWorkAccountSwitcher.ps1 -Command add -Name <账号名> [-MachineId <机器码>]" -ForegroundColor Yellow
                return
            }
            Add-Account -AccountName $Name -CustomMachineId $MachineId
        }
        'list' {
            Initialize-Storage
            $data = Get-Content $Script:AccountsFile -Encoding UTF8 | ConvertFrom-Json
            $accounts = $data.accounts
            $currentId = $data.currentAccountId

            if ($accounts.PSObject.Properties.Count -eq 0) {
                Write-Host "暂无账号" -ForegroundColor Yellow
                return
            }

            foreach ($prop in $accounts.PSObject.Properties) {
                $acc = $prop.Value
                $isCurrent = ($acc.id -eq $currentId)
                $marker = if ($isCurrent) { " 👈 当前" } else { "" }
                Write-Host "$($acc.name)$marker" -ForegroundColor $(if ($isCurrent) { "Green" } else { "White" })
                Write-Host "  机器码: $($acc.machineId)" -ForegroundColor Gray
                Write-Host "  创建时间: $($acc.createdAt)" -ForegroundColor Gray
                if ($acc.lastUsedAt) { Write-Host "  上次使用: $($acc.lastUsedAt)" -ForegroundColor Gray }
                Write-Host ""
            }
        }
        'switch' {
            if (-not $Name) {
                Write-Host "用法: .\TraeWorkAccountSwitcher.ps1 -Command switch -Name <账号名>" -ForegroundColor Yellow
                return
            }
            Switch-Account -AccountName $Name
        }
        'delete' {
            if (-not $Name) {
                Write-Host "用法: .\TraeWorkAccountSwitcher.ps1 -Command delete -Name <账号名>" -ForegroundColor Yellow
                return
            }
            Delete-Account -AccountName $Name
        }
        'export' {
            Export-Accounts
        }
        'import' {
            # 交互式导入
            $path = Read-Host "请输入导入文件路径"
            Import-Accounts -ImportPath $path
        }
    }
}

# ============ 启动 ============
Main
---
name: "trae-work-account-switcher"
description: "Trae Work 桌面端账号切换工具。管理多账号、每个账号绑定独立机器码、一键切换无需验证码。当用户需要切换 Trae Work 账号、管理多个 Trae 账号、或要求绑定不同机器码时调用。"
---

# Trae Work 账号切换工具

管理 Trae Work (TRAE SOLO CN) 多账号，每个账号绑定独立机器码，一键切换无需验证码。

## 工作原理

1. **保存账号快照**：保存每个账号的完整配置（storage.json、machineid、TinyStorage、Local Storage 等）
2. **切换流程**：关闭 Trae Work → 写入目标账号配置 → 清理缓存 → 启动 Trae Work
3. **机器码独立**：每个账号自动分配唯一 UUID 机器码，切换时自动写入

## 文件位置

- **GUI 图形界面版**: `trae-account-switcher\TraeWorkAccountSwitcher-GUI.ps1`
- **命令行版**: `trae-account-switcher\TraeWorkAccountSwitcher.ps1`
- **快捷启动**: `trae-account-switcher\启动账号切换工具.bat`（双击运行）

## 使用方法

### 方式一：GUI 图形界面（推荐）
1. 双击 `启动账号切换工具.bat`
2. 点击「📥 添加当前账号」捕获当前 Trae Work 登录状态
3. 在列表中选中账号，点击「🔄 切换到选中账号」
4. 工具自动关闭 Trae Work → 切换配置 → 重启 Trae Work

### 方式二：命令行
```powershell
# 打开交互菜单
.\TraeWorkAccountSwitcher.ps1

# 直接切换
.\TraeWorkAccountSwitcher.ps1 -Command switch -Name "账号1"

# 列出所有账号
.\TraeWorkAccountSwitcher.ps1 -Command list
```

## 数据存储

- **账号配置**: `%APPDATA%\TraeWorkSwitcher\accounts.json`
- **账号配置备份**: `%APPDATA%\TraeWorkSwitcher\profiles\<id>\`
- **操作日志**: `%APPDATA%\TraeWorkSwitcher\switcher.log`
- **Trae Work 数据**: `%APPDATA%\TRAE SOLO CN\`

## 注意事项

- 切换账号前请保存工作内容，Trae Work 会自动关闭并重启
- 首次添加账号时，请先登录目标账号再点击添加
- 每个账号自动分配唯一机器码，也可手动指定
- 删除账号会同时删除对应的配置备份，不可恢复
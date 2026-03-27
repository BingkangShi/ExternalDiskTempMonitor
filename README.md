# ExternalDiskTempMonitor

ExternalDiskTempMonitor 是一款专为 macOS 设计的外置硬盘温度监控工具。它可以实时监控连接到 Mac 的外部硬盘温度，并在屏幕顶部状态栏（如果屏幕包含刘海，会自动避让并悬浮显示）中显示。

## 功能特性

- **极简无感监控**：菜单栏只显示一个 macOS 原生的外接硬盘图标（`externaldrive`），实现“0占用”零打扰模式。
- **详实的状态报告**：点击菜单栏的硬盘图标，下拉菜单会显示所有已连接外置硬盘的**完整卷名称**和实时温度。
- **智能空闲提示**：当没有任何外接硬盘时，菜单栏仅显示硬盘图标，点击下拉菜单会提示 `///No Ex Disk///`。
- **完善的设备兼容**：能够智能识别 SD 卡等原生无 SMART 传感器的设备，并在下拉菜单中对其温度显示为 `N/A` 而非将其意外隐藏。

## 环境要求

1. macOS（支持 Apple Silicon 与 Intel）。
2. 需要安装 **smartmontools** (用于 smartctl 命令)：
   ```bash
   brew install smartmontools
   ```
3. 需要开发工具包（编译工具 swiftc，如果你打算自己编译）：
   ```bash
   xcode-select --install
   ```

## 安装与使用

在终端中定位到本项目目录并运行：
```bash
./install.sh
```

**该安装脚本将会自动执行以下操作**：
1. 编译 `main.swift` 为可执行文件 `ExternalDiskTempMonitor.app`。
2. 将程序安装到系统的 `/Applications/ExternalDiskTempMonitor.app`。
3. 如果在此之前有运行该程序的历史实例，脚本会将其结束进程。
4. **开机自设定配置**：自动在 `~/Library/LaunchAgents` 中生成并加载对应的 `.plist` 守护文件。

### 如何设定为随系统启动而启动（默认开启）
`install.sh` 脚本在安装过程中会**自动为您启用**开机自启动。
核心原理是在 `~/Library/LaunchAgents/com.user.externaldisktempmonitor.plist` 创建配置文件并调用 `launchctl load`。系统会在每次您登录时自动在后台打开此应用。

### 如何取消系统自启动
如果您不希望继续让它开机自启动，可以通过以下命令取消：
```bash
launchctl unload ~/Library/LaunchAgents/com.user.externaldisktempmonitor.plist
# 移除守护文件
rm ~/Library/LaunchAgents/com.user.externaldisktempmonitor.plist
```
*(取消自启动后，您仍然可以手动前往**应用程序**文件夹双击 `ExternalDiskTempMonitor.app` 启动它)*

## 卸载
1. 停止当前运行：
   点击顶部状态栏的 `///No Ex Disk///`（或温度监控信息）触发下拉菜单，点击 `Quit ExternalDiskTempMonitor`。
2. 移除开机自启动配置文件（如上）。
3. 前往 `/Applications/` 文件夹删除 `ExternalDiskTempMonitor.app`。

<div align="center">

<img src="logo.png" width="200" alt="EasyTierManager Logo" />

# EasyTierManager

macOS 原生 GUI 管理器（SwiftUI + AppKit），用于管理 [EasyTier](https://github.com/EasyTier/Easytier) 虚拟组网。

<p>
  <img alt="Platform" src="https://img.shields.io/badge/macOS-13%2B-111111?style=flat-square&logo=apple" />
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.0-F05138?style=flat-square&logo=swift" />
  <img alt="Build" src="https://img.shields.io/badge/Build-XcodeGen-0A84FF?style=flat-square" />
  <a href="https://github.com/EasyTier/EasyTierManager/releases" target="_blank" rel="noopener noreferrer">
    <img alt="Version" src="https://img.shields.io/github/v/release/EasyTier/EasyTierManager?style=flat-square&logo=github" />
  </a>
  <a href="https://github.com/EasyTier/EasyTierManager/stargazers" target="_blank" rel="noopener noreferrer">
    <img alt="Stars" src="https://img.shields.io/github/stars/EasyTier/EasyTierManager?style=flat-square&logo=github" />
  </a>
</p>

</div>

---

## 项目简介

EasyTierManager 是一款基于 EasyTier 内核的原生 macOS 虚拟组网管理客户端，提供直观的图形界面来管理 EasyTier 网络连接与节点。

你可以在应用中完成网络的创建、编辑、启动与停止，实时查看网络节点状态，而无需手动编辑配置文件或使用命令行。

## 项目说明

EasyTierManager 是一个纯 AI Vibe Coding 产物，全部代码由 AI 生成，未经人工审查。

项目在需求梳理、架构设计、功能实现、文档维护等环节全程与 AI 协作，用于验证 AI 驱动的 macOS 原生应用开发全流程可行性。

## 核心功能

| 功能 | 说明 |
| --- | --- |
| 网络管理 | 创建、编辑、删除 EasyTier 虚拟网络连接 |
| 一键启停 | 快速启动或停止已配置的网络连接 |
| 节点监控 | 实时查看网络中所有节点的在线状态与延迟 |
| 自动连接 | 支持应用启动时自动连接指定网络 |
| 核心更新 | 自动检测 EasyTier 最新版本并一键下载升级 |
| 系统托盘 | 菜单栏快捷操作，支持隐藏程序坞图标 |

## 系统要求

- macOS Ventura (13.0) 及以上
- Apple Silicon (arm64) 或 Intel (x86_64)

## 安装

### 下载 DMG

从 [GitHub Releases](https://github.com/EasyTier/EasyTierManager/releases) 下载对应架构的 `.dmg` 文件，挂载后将 `EasyTierManager.app` 拖入 `/Applications`。

> CI 仅自动发布 Apple Silicon (arm64) 版本。Intel 用户请使用 Homebrew 安装或参考下方「本地构建」自行打包。

### Homebrew

```bash
brew tap begitcn/homebrew-tap
brew install --cask easytiermanager
```

### 本地构建

```bash
# 克隆仓库
git clone https://github.com/EasyTier/EasyTierManager.git
cd EasyTierManager

# 安装依赖（XcodeGen）
brew install xcodegen

# 运行打包脚本，自动下载 EasyTier 核心二进制并构建 DMG
bash build-release.sh

# 执行后可以在 dist/ 目录找到 DMG 安装包
```

---

> [!IMPORTANT]
> **安装后首次打开遇到问题？** 由于 GitHub Actions 构建的版本未经 Apple 公证，macOS 可能会拦截。请按以下顺序尝试：

> **1. 系统提示“无法验证开发者”**
>
> 打开 **系统设置 → 隐私与安全性**，向下滚动找到 EasyTierManager，点击「仍要打开」。

> **2. 提示“已损坏”，无法打开**
>
> 终端执行以下命令移除隔离标记：
> ```bash
> sudo xattr -dr com.apple.quarantine /Applications/EasyTierManager.app
> ```


---

## 卸载

### DMG 安装卸载

```bash
# 退出应用
killall EasyTierManager 2>/dev/null

# 卸载特权助手
sudo /Applications/EasyTierManager.app/Contents/Library/HelperTools/EasyTierHelper unload 2>/dev/null
sudo rm -f /Library/PrivilegedHelperTools/EasyTierHelper
sudo rm -f /Library/LaunchDaemons/EasyTierHelper.plist

# 删除应用
rm -rf /Applications/EasyTierManager.app

# 删除配置文件
rm -rf ~/Library/Application\ Support/com.easytier.manager/
rm -rf ~/Library/Caches/com.easytier.manager/
rm -rf ~/Library/Preferences/com.easytier.manager.plist
```

### Homebrew 安装卸载

```bash
brew uninstall --cask easytiermanager
```

之后请参考上方 DMG 卸载中的步骤手动清理残余文件（配置文件、缓存、特权助手等）。

## 开发

```bash
# 开发模式：下载 EasyTier 二进制 + 生成 Xcode 项目
bash build-release.sh --dev

# 打开项目
open EasyTierManager.xcodeproj

# 在 Xcode 中按 ⌘R 构建并运行
```

`build-release.sh` 提供三种模式：

| 命令 | 说明 |
| --- | --- |
| `bash build-release.sh` | 完整打包：下载二进制 → 编译 → 嵌入核心 → 生成 DMG |
| `bash build-release.sh --download` | 仅下载并缓存 EasyTier 核心二进制到 `Helpers/` |
| `bash build-release.sh --dev` | 下载二进制 + 生成 .xcodeproj，适合 Xcode 开发 |

EasyTier 二进制下载后缓存在 `~/Library/Caches/com.easytier.manager/easytier-binaries/`，避免重复下载。

## 架构

- **前端**：SwiftUI + AppKit，手动管理 AppDelegate 与 NSMenu
- **特权助手**：`EasyTierHelper` — 通过 launchd 以 root 权限运行的 XPC 服务，负责启动/停止 easytier-core 进程
- **核心组件**：easytier-core（组网守护进程）与 easytier-cli（命令行工具）嵌入在 app bundle 中

## 数据目录

配置与运行数据存放路径：

| 路径 | 说明 |
| --- | --- |
| `~/Library/Application Support/com.easytier.manager/` | 网络配置与应用状态 |
| `EasyTierManager.app/Contents/Helpers/` | EasyTier 核心二进制（easytier-core / easytier-cli） |
| `EasyTierManager.app/Contents/Library/HelperTools/EasyTierHelper` | 特权助手二进制 |
| `EasyTierManager.app/Contents/Library/LaunchDaemons/EasyTierHelper.plist` | launchd 配置文件 |
| `/Library/PrivilegedHelperTools/EasyTierHelper` | 安装后的特权助手（符号链接） |

## 常见问题

### 核心二进制未找到

应用首次启动时会在 `Contents/Helpers/` 下寻找 easytier-core。如未找到，进入 **设置 → EasyTier**，点击「检查更新」下载最新核心，或使用 `build-release.sh --download` 手动放置。

## 致谢

感谢 [EasyTier](https://github.com/EasyTier/Easytier) 项目提供优秀的开源虚拟组网工具，为本项目提供了核心能力支撑。

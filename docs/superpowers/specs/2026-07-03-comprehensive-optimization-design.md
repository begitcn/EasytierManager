# EasyTierManager 全面优化设计方案

日期：2026-07-03
状态：设计完成，待实施

## 目标

全面优化 EasyTierManager macOS 应用，达成：
- **高性能**：减少不必要的 I/O、轮询、CPU 消耗
- **稳定运行**：作为常开工具，后台时自动节流，崩溃自恢复
- **低内存**：避免内存泄漏，减少常驻内存占用
- **交互友好**：键盘快捷键、状态实时反馈、增强菜单栏

## 优化项清单

### A. 内存与性能优化

| # | 优化项 | 文件 | 预期收益 |
|---|--------|------|---------|
| A1 | NetworkStore 写入防抖 | `Services/NetworkStore.swift` | I/O 减少 90%+ |
| A2 | TOML 配置读取缓存 | `Services/NetworkStore.swift`, `UI/ConnectionsView.swift` | 避免反复读盘 |
| A3 | 后台时暂停轮询 | `Services/EasyTierService.swift`, `UI/NodesView.swift` | 降低无效 CPU |
| A4 | 结构化 Task 生命周期 | `UI/ConnectionsView.swift` | 防止 Task 泄漏 |
| A5 | 版本检测缓存 | `Services/EasyTierService.swift`, `UI/SettingsView.swift` | 减少子进程调用 |
| A6 | 信号处理非阻塞化 | `System/AppDelegate.swift` | 避免线程阻塞 |
| A7 | SwiftUI Body 优化 | `UI/ConnectionsView.swift` | 减少重复计算 |

### B. 交互体验改进

| # | 优化项 | 文件 | 说明 |
|---|--------|------|------|
| B1 | 键盘快捷键 | `UI/ConnectionsView.swift`, `UI/NodesView.swift`, `UI/MainView.swift` | Cmd+N/E/R/1/2/3 |
| B2 | 菜单栏状态显示 | `System/StatusBarController.swift` | 显示活跃连接数 |
| B3 | 网络列表搜索 | `UI/ConnectionsView.swift` | 按名称过滤 |
| B4 | 连接状态反馈 | `UI/ConnectionsView.swift` | 脉冲动画/加载态 |

## 实现细节

### A1 NetworkStore 写入防抖

```swift
// 改动
private var saveTask: Task<Void, Never>?

private func scheduleSave() {
    saveTask?.cancel()
    saveTask = Task {
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard !Task.isCancelled else { return }
        performSave()
    }
}

private func performSave() {
    guard let data = try? JSONEncoder().encode(networks) else { return }
    try? data.write(to: saveURL, options: .atomic)
}
```

- `addNetwork` → `scheduleSave()`
- `updateNetwork` → `scheduleSave()`
- `removeNetwork` → `scheduleSave()`
- `updateStatus` → 不触发保存（状态是运行时信息，不需要持久化）

### A2 TOML 配置缓存

`NetworkStore` 增加：
```swift
@Published private(set) var configCache: [UUID: EasyTierConfig] = [:]

func cacheConfig(_ config: EasyTierConfig, for id: UUID) {
    configCache[id] = config
}

func invalidateConfig(for id: UUID) {
    configCache.removeValue(forKey: id)
}
```

`ConnectionsView.reloadDetailConfig()` 和 `allUsedPorts()` 改为读缓存。

缓存更新时机：
- `saveEditor()` 保存后 → `cacheConfig`
- `deleteNetwork` 删除后 → `invalidateConfig`
- `importConfig` 导入后 → `cacheConfig`

### A3 后台暂停轮询

`EasyTierService` 增加 `isAppActive` 标志：
- `AppDelegate.applicationDidResignActive` → 设为 false
- `AppDelegate.applicationDidBecomeActive` → 设为 true
- `performHealthCheck()` 开头检查标志

`NodesView.refreshNodes()` 开头也检查。

### A4 结构化 Task

`ConnectionsView` 增加 `@State private var currentTask: Task<Void, Never>?`。

`toggleConnection()`, `connectAll()`, `deleteNetwork()` 开始时 cancel 旧 task，结束时置 nil。

`onDisappear` 取消 `currentTask`。

### A5 版本检测缓存

`EasyTierService` 增加：
```swift
private var cachedCoreVersion: String?
```

`detectEasytierVersion()` 改为读取缓存，添加强制刷新按钮。

### A6 信号处理非阻塞

`forceStopAll` 增加 async 重载，`handleTerminationSignal` 使用 Task 等待。

### A7 SwiftUI Body 优化

将 `detailRow`, `formField`, `formToggle`, `coloredStatusRow` 等内联视图提取为独立的 `private struct`，减少不必要的 body 重新计算。

### B1 键盘快捷键

```swift
// ConnectionsView
.buttonStyle(...)
.keyboardShortcut("n", modifiers: .command)  // 新建

// 编辑按钮
.keyboardShortcut("e", modifiers: .command)

// 删除按钮
.keyboardShortcut(.delete, modifiers: .command)

// 切换连接
.keyboardShortcut(.return, modifiers: .command)

// MainView 导航
// Cmd+1 = 连接, Cmd+2 = 节点, Cmd+3 = 设置
```

### B2 菜单栏状态

`StatusBarController` 通过 Combine 订阅 `NetworkStore.$networks`，动态更新菜单项，显示已连接网络数量。

### B3 网络搜索

ConnectionsView 列表上方添加搜索框，绑定 `@State searchText`，列表过滤。

### B4 连接状态反馈

已连接状态的网络图标添加脉冲动画：使用 `PhaseAnimator` 或重复的 `withAnimation`。

## 实施顺序

1. A1 NetworkStore 写入防抖（独立、高收益）
2. A2 TOML 配置缓存（依赖 A1 的 configCache）
3. A5 版本检测缓存（独立）
4. A4 结构化 Task 生命周期（独立）
5. A3 后台暂停轮询（独立）
6. A7 SwiftUI Body 优化（独立）
7. A6 信号处理非阻塞（独立）
8. B1 键盘快捷键（独立）
9. B3 网络列表搜索（独立）
10. B2 菜单栏状态（独立）
11. B4 连接状态反馈（独立）

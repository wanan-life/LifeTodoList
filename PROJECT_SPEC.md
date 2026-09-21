# LifeTodoList - 极简状态栏Todo管理应用

## 项目概述

一个运行在macOS状态栏的极简Todo管理应用，支持多项目管理，快速增删改查任务。

---

## 核心功能需求

### 1. 状态栏交互
- 应用启动后在状态栏显示图标（建议使用 SF Symbol: `checklist`）
- 点击图标弹出下拉面板（Popover）
- 不在Dock显示图标（纯状态栏应用）

### 2. 项目管理
- 创建/编辑/删除项目
- 每个项目有名称和可选颜色标识
- 项目列表可排序
- 支持默认项目"收件箱"（不可删除）

### 3. 任务管理
- 在项目下快速创建任务（回车即可创建）
- 点击任务切换完成状态（完成后显示删除线）
- 已完成任务旁显示"清除"按钮
- 支持编辑任务内容
- 支持删除未完成任务

### 4. 历史记录管理窗口
- 独立的设置/管理窗口（从Popover中打开）
- 查看所有项目及其任务（包括已清除的）
- 筛选功能：全部/进行中/已完成/已归档
- 恢复已归档的任务
- 永久删除任务
- 数据统计展示

---

## 你可能遗漏的问题与建议

### 数据持久化
- **问题**：数据如何存储？应用退出后数据是否保留？
- **建议**：使用 SwiftData (macOS 14+) 或 CoreData 进行本地持久化
- **考虑**：是否需要 iCloud 同步？（多设备场景）

### 任务状态模型
- **问题**：任务有几种状态？
- **建议**：设计三种状态
  - `pending` - 进行中
  - `completed` - 已完成（显示删除线，可清除）
  - `archived` - 已归档（从列表隐藏，但在管理窗口可见）

### 快捷操作
- **问题**：如何快速添加任务？
- **建议**：
  - 全局快捷键唤起应用（如 `⌘⇧T`）
  - 在Popover顶部显示快速输入框
  - 支持 `⌘N` 新建任务、`⌘⌫` 删除任务

### 数据安全
- **问题**：误删任务怎么办？
- **建议**：
  - 删除操作先归档，不立即永久删除
  - 提供"撤销"功能（⌘Z）
  - 管理窗口可恢复已归档任务

### 任务排序
- **问题**：任务显示顺序？
- **建议**：
  - 默认按创建时间（新任务在底部）
  - 已完成任务自动移到列表底部
  - 支持拖拽手动排序

### 时间维度
- **问题**：是否需要截止日期？
- **建议**：极简版本可不支持，但预留字段
  - 可选功能：任务添加创建时间戳
  - 可选功能：完成时间戳（用于统计）

### 数据导出
- **问题**：数据备份需求？
- **建议**：
  - 管理窗口提供导出功能（JSON/CSV）
  - 可选：导入功能

### 空状态处理
- **问题**：没有项目/任务时显示什么？
- **建议**：友好的空状态提示和快速创建引导

### 性能考虑
- **问题**：大量任务时的性能？
- **建议**：
  - Popover只显示进行中和最近完成的任务
  - 分页加载（如只显示最近50条）
  - 历史数据在管理窗口懒加载

---

## 技术方案

### 最低系统版本
- **推荐**：macOS 14.0+（使用 SwiftData + MenuBarExtra）
- **可选**：macOS 13.0+（使用 CoreData + MenuBarExtra）

### 技术栈
```
- SwiftUI（界面）
- SwiftData（数据持久化）
- MenuBarExtra（状态栏）
- AppStorage（用户偏好设置）
```

### 数据模型

```swift
// 项目
@Model
class Project {
    var id: UUID
    var name: String
    var colorHex: String?
    var order: Int
    var isDefault: Bool  // 默认收件箱项目
    var createdAt: Date

    @Relationship(deleteRule: .cascade)
    var tasks: [TodoTask]
}

// 任务
@Model
class TodoTask {
    var id: UUID
    var content: String
    var status: TaskStatus  // pending, completed, archived
    var order: Int
    var createdAt: Date
    var completedAt: Date?
    var archivedAt: Date?

    var project: Project?
}

enum TaskStatus: String, Codable {
    case pending
    case completed
    case archived
}
```

### 应用架构

```
LifeTodoList/
├── App/
│   └── LifeTodoListApp.swift      # 应用入口，配置MenuBarExtra
├── Models/
│   ├── Project.swift              # 项目模型
│   └── TodoTask.swift             # 任务模型
├── Views/
│   ├── MenuBar/
│   │   ├── MenuBarView.swift      # 状态栏Popover主视图
│   │   ├── ProjectListView.swift  # 项目列表
│   │   ├── TaskListView.swift     # 任务列表
│   │   └── QuickAddView.swift     # 快速添加输入框
│   ├── Management/
│   │   ├── ManagementWindow.swift # 管理窗口
│   │   ├── AllProjectsView.swift  # 所有项目视图
│   │   └── TaskHistoryView.swift  # 任务历史视图
│   └── Components/
│       ├── TaskRowView.swift      # 任务行组件
│       ├── ProjectRowView.swift   # 项目行组件
│       └── EmptyStateView.swift   # 空状态组件
├── ViewModels/
│   ├── ProjectViewModel.swift     # 项目业务逻辑
│   └── TaskViewModel.swift        # 任务业务逻辑
├── Services/
│   ├── DataService.swift          # 数据服务
│   └── ExportService.swift        # 导出服务
└── Resources/
    └── Assets.xcassets            # 资源文件
```

---

## UI 设计规范

### Popover 面板
- 宽度：300pt
- 最大高度：500pt（超出滚动）
- 圆角：10pt
- 背景：系统 Popover 背景色

### 布局结构（Popover）
```
┌─────────────────────────────┐
│ [+] 快速添加任务...    [⚙️] │  ← 顶部栏
├─────────────────────────────┤
│ 📁 项目A              [▼]  │  ← 可折叠项目
│   ○ 任务1                   │
│   ○ 任务2                   │
│   ✓ 任务3 (删除线)    [×]  │  ← 已完成，显示清除按钮
├─────────────────────────────┤
│ 📁 项目B              [▼]  │
│   ○ 任务4                   │
└─────────────────────────────┘
```

### 管理窗口
- 窗口大小：800 × 600（可调整）
- 左侧：项目列表侧边栏
- 右侧：任务详情/列表
- 顶部：筛选和搜索

---

## 开发阶段规划

### Phase 1: 基础框架
- [ ] 配置状态栏应用（MenuBarExtra）
- [ ] 隐藏Dock图标
- [ ] 创建基本Popover界面
- [ ] 设置SwiftData数据模型

### Phase 2: 核心功能
- [ ] 项目CRUD
- [ ] 任务CRUD
- [ ] 任务状态切换（完成/未完成）
- [ ] 任务清除（归档）

### Phase 3: 管理窗口
- [ ] 创建独立管理窗口
- [ ] 项目管理界面
- [ ] 任务历史查看
- [ ] 筛选功能
- [ ] 恢复归档任务

### Phase 4: 增强功能
- [ ] 全局快捷键
- [ ] 拖拽排序
- [ ] 数据导出
- [ ] 空状态优化
- [ ] 动画效果

### Phase 5: 完善
- [ ] 错误处理
- [ ] 性能优化
- [ ] 应用图标设计
- [ ] 测试与修复

---

## 关键实现要点

### 1. 状态栏应用配置
```swift
@main
struct LifeTodoListApp: App {
    var body: some Scene {
        MenuBarExtra("LifeTodoList", systemImage: "checklist") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)  // 使用窗口样式以支持复杂UI

        Window("管理", id: "management") {
            ManagementWindow()
        }
    }
}
```

### 2. 隐藏Dock图标
在 `Info.plist` 中添加：
```xml
<key>LSUIElement</key>
<true/>
```

### 3. 任务完成动画
```swift
Text(task.content)
    .strikethrough(task.status == .completed, color: .gray)
    .foregroundColor(task.status == .completed ? .gray : .primary)
    .animation(.easeInOut(duration: 0.2), value: task.status)
```

---

## 开始开发

准备好后，请告诉我从哪个阶段开始，我将逐步实现每个功能模块。

建议从 **Phase 1: 基础框架** 开始，先搭建状态栏应用的基本骨架。

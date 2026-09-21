//
//  ManagementView.swift
//  LifeTodoList
//

import SwiftUI
import SwiftData

struct ManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AppCoordinator
    @Query(sort: \Project.order) private var projects: [Project]
    @Query private var allTasks: [TodoTask]

    @State private var filterStatus: TaskFilterStatus = .all
    @State private var searchText = ""
    @State private var isAddingProject = false
    @State private var newProjectName = ""

    var body: some View {
        NavigationSplitView {
            sidebarView
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .background(.regularMaterial)
        .tint(.teal)
    }

    private var sidebarView: some View {
        List(selection: $coordinator.selection) {
            Section {
                NavigationLink(value: SidebarItem.board) {
                    sidebarLabel("任务看板", symbol: "rectangle.split.3x1", count: pendingTasks)
                }
                NavigationLink(value: SidebarItem.allTasks) {
                    sidebarLabel("所有任务", symbol: "checklist", count: totalTasks)
                }
                NavigationLink(value: SidebarItem.allArchived) {
                    sidebarLabel("已归档", symbol: "archivebox", count: archivedTasks)
                }
            }

            Section {
                ForEach(projects) { project in
                    NavigationLink(value: SidebarItem.project(project)) {
                        sidebarLabel(project.name, symbol: "folder", count: project.pendingTasksCount)
                    }
                    .contextMenu {
                        if !project.isDefault {
                            Button("删除项目", systemImage: "trash", role: .destructive) {
                                modelContext.delete(project)
                                coordinator.selection = .board
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("项目")
                    Spacer()
                    Button { isAddingProject = true } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help("新建项目")
                    .popover(isPresented: $isAddingProject) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("新建项目").font(.headline)
                            TextField("项目名称", text: $newProjectName)
                                .onSubmit(createProject)
                            HStack {
                                Spacer()
                                Button("创建", action: createProject)
                                    .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        .padding(16)
                        .frame(width: 240)
                    }
                }
            }

            Section {
                NavigationLink(value: SidebarItem.settings) {
                    Label("设置", systemImage: "gearshape")
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(.ultraThinMaterial)
        .frame(minWidth: 190, idealWidth: 215)
    }

    private func sidebarLabel(_ title: String, symbol: String, count: Int) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).frame(width: 18)
            Text(title)
            Spacer(minLength: 4)
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch coordinator.selection {
        case .board:
            BoardView(projectFilter: nil)
        case .allArchived:
            AllArchivedView(tasks: archivedTasksList, searchText: $searchText)
        case .allTasks:
            AllTasksView(tasks: allTasks, filterStatus: $filterStatus, searchText: $searchText)
        case .project(let project):
            BoardView(projectFilter: project)
        case .settings:
            SettingsView()
        }
    }

    private var totalTasks: Int {
        allTasks.count
    }

    private var pendingTasks: Int {
        allTasks.filter { $0.status == .pending }.count
    }

    private var archivedTasks: Int {
        allTasks.filter { $0.status == .archived }.count
    }

    private var archivedTasksList: [TodoTask] {
        allTasks.filter { $0.status == .archived }
            .sorted { ($0.archivedAt ?? Date()) > ($1.archivedAt ?? Date()) }
    }

    private func createProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let project = Project(name: name, order: (projects.map(\.order).max() ?? 0) + 1)
        modelContext.insert(project)
        coordinator.selection = .project(project)
        newProjectName = ""
        isAddingProject = false
    }
}

enum SidebarItem: Hashable {
    case board
    case allArchived
    case allTasks
    case project(Project)
    case settings
}

// MARK: - Task Filter Status
enum TaskFilterStatus: String, CaseIterable {
    case all = "全部"
    case pending = "进行中"
    case completed = "已完成"
    case archived = "已归档"
}

// MARK: - All Archived View
struct AllArchivedView: View {
    @Environment(\.modelContext) private var modelContext
    let tasks: [TodoTask]
    @Binding var searchText: String

    var body: some View {
        VStack(spacing: 0) {
            // 搜索栏
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索归档任务...", text: $searchText)
                        .textFieldStyle(.plain)

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.05))
                )

                Spacer()

                // 清空所有归档按钮
                if !tasks.isEmpty {
                    Button(action: deleteAllArchived) {
                        Label("清空归档", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
            .padding()

            Divider()

            if filteredTasks.isEmpty {
                ContentUnavailableView {
                    Label("没有归档任务", systemImage: "archivebox")
                } description: {
                    Text("已清除的任务会显示在这里")
                }
            } else {
                List {
                    ForEach(filteredTasks) { task in
                        ArchivedTaskRowView(task: task)
                    }
                    .onDelete(perform: deleteTasks)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("已归档任务")
    }

    private var filteredTasks: [TodoTask] {
        if searchText.isEmpty {
            return tasks
        }
        return tasks.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
    }

    private func deleteTasks(at offsets: IndexSet) {
        for index in offsets {
            let task = filteredTasks[index]
            modelContext.delete(task)
        }
    }

    private func deleteAllArchived() {
        for task in tasks {
            modelContext.delete(task)
        }
    }
}

// MARK: - Archived Task Row View
struct ArchivedTaskRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var task: TodoTask

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "archivebox.fill")
                .foregroundColor(.gray)
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text(task.content)
                    .strikethrough(color: .gray)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    if let projectName = task.project?.name {
                        Label(projectName, systemImage: "folder")
                    }

                    if let archivedAt = task.archivedAt {
                        Label(formatDate(archivedAt), systemImage: "clock")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            // 恢复按钮
            Button(action: { task.restore() }) {
                Label("恢复", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            // 永久删除
            Button(action: { modelContext.delete(task) }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - All Tasks View
struct AllTasksView: View {
    @Environment(\.modelContext) private var modelContext
    let tasks: [TodoTask]
    @Binding var filterStatus: TaskFilterStatus
    @Binding var searchText: String

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索任务...", text: $searchText)
                        .textFieldStyle(.plain)

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.05))
                )

                Spacer()

                Picker("筛选", selection: $filterStatus) {
                    ForEach(TaskFilterStatus.allCases, id: \.self) { status in
                        Text(status.rawValue).tag(status)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            }
            .padding()

            Divider()

            if filteredTasks.isEmpty {
                ContentUnavailableView {
                    Label("没有任务", systemImage: "tray")
                } description: {
                    Text("当前筛选条件下没有任务")
                }
            } else {
                List {
                    ForEach(filteredTasks) { task in
                        ManagementTaskRowView(task: task, showProject: true)
                    }
                    .onDelete(perform: deleteTasks)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("所有任务")
    }

    private var filteredTasks: [TodoTask] {
        var result = tasks.sorted { $0.createdAt > $1.createdAt }

        switch filterStatus {
        case .all:
            break
        case .pending:
            result = result.filter { $0.status == .pending }
        case .completed:
            result = result.filter { $0.status == .completed }
        case .archived:
            result = result.filter { $0.status == .archived }
        }

        if !searchText.isEmpty {
            result = result.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
        }

        return result
    }

    private func deleteTasks(at offsets: IndexSet) {
        for index in offsets {
            let task = filteredTasks[index]
            modelContext.delete(task)
        }
    }
}

// MARK: - Project Detail View
struct ProjectDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: Project
    @Binding var filterStatus: TaskFilterStatus
    @Binding var searchText: String

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            toolbarView

            Divider()

            // 任务列表
            if filteredTasks.isEmpty {
                ContentUnavailableView {
                    Label("没有任务", systemImage: "tray")
                } description: {
                    Text("当前筛选条件下没有任务")
                }
            } else {
                List {
                    ForEach(filteredTasks) { task in
                        ManagementTaskRowView(task: task, showProject: false)
                    }
                    .onDelete(perform: deleteTasks)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(project.name)
    }

    private var toolbarView: some View {
        HStack {
            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索任务...", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.05))
            )

            Spacer()

            // 筛选器
            Picker("筛选", selection: $filterStatus) {
                ForEach(TaskFilterStatus.allCases, id: \.self) { status in
                    Text(status.rawValue).tag(status)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
        }
        .padding()
    }

    private var filteredTasks: [TodoTask] {
        var tasks = project.tasks.sorted { $0.order < $1.order }

        // 按状态筛选
        switch filterStatus {
        case .all:
            break
        case .pending:
            tasks = tasks.filter { $0.status == .pending }
        case .completed:
            tasks = tasks.filter { $0.status == .completed }
        case .archived:
            tasks = tasks.filter { $0.status == .archived }
        }

        // 按搜索词筛选
        if !searchText.isEmpty {
            tasks = tasks.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
        }

        return tasks
    }

    private func deleteTasks(at offsets: IndexSet) {
        for index in offsets {
            let task = filteredTasks[index]
            modelContext.delete(task)
        }
    }
}

// MARK: - Management Task Row View
struct ManagementTaskRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var task: TodoTask
    var showProject: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // 状态指示器
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                // 任务内容
                Text(task.content)
                    .strikethrough(task.status != .pending, color: .gray)
                    .foregroundColor(task.status == .pending ? .primary : .secondary)

                // 时间信息
                HStack(spacing: 8) {
                    if showProject, let projectName = task.project?.name {
                        Label(projectName, systemImage: "folder")
                            .foregroundColor(.blue)
                    }

                    Label(formatDate(task.createdAt), systemImage: "clock")

                    if let completedAt = task.completedAt {
                        Label(formatDate(completedAt), systemImage: "checkmark.circle")
                            .foregroundColor(.green)
                    }

                    if let archivedAt = task.archivedAt {
                        Label(formatDate(archivedAt), systemImage: "archivebox")
                            .foregroundColor(.gray)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            // 操作按钮
            actionButtons
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch task.status {
        case .pending: return .orange
        case .completed: return .green
        case .archived: return .gray
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            // 恢复按钮（归档任务）
            if task.status == .archived {
                Button(action: { task.restore() }) {
                    Label("恢复", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // 切换完成状态（非归档任务）
            if task.status != .archived {
                Button(action: { task.toggleComplete() }) {
                    Label(
                        task.status == .pending ? "完成" : "取消完成",
                        systemImage: task.status == .pending ? "checkmark" : "arrow.uturn.backward"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // 永久删除按钮
            Button(action: { modelContext.delete(task) }) {
                Label("删除", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }
}

#Preview {
    ManagementView()
        .modelContainer(for: [Project.self, TodoTask.self], inMemory: true)
}

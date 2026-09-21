//
//  MenuBarView.swift
//  LifeTodoList
//

import SwiftUI
import SwiftData

struct MenuBarView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AppCoordinator
    @Query(sort: \Project.order) private var projects: [Project]

    @State private var newTaskText = ""
    @State private var selectedProjectId: UUID?
    @State private var isAddingProject = false
    @State private var newProjectName = ""

    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            headerView

            Divider()

            // 项目和任务列表
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(projects) { project in
                        ProjectSectionView(
                            project: project,
                            selectedProjectId: $selectedProjectId,
                            newTaskText: $newTaskText
                        )
                    }
                }
                .padding(.vertical, 8)
            }

            Divider()

            // 底部按钮
            footerView
        }
        .frame(width: 320, height: 450)
    }

    // MARK: - Header View
    private var headerView: some View {
        HStack {
            // 新建项目按钮
            Button(action: { isAddingProject = true }) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isAddingProject) {
                addProjectPopover
            }

            Spacer()

            Text("LifeTodo")
                .font(.headline)
                .foregroundColor(.secondary)

            Spacer()

            Button(action: { coordinator.openManagement(.settings) }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help("设置")

            Button(action: { coordinator.openManagement() }) {
                Image(systemName: "rectangle.split.3x1")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help("打开任务管理")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Footer View
    private var footerView: some View {
        HStack {
            Text("\(totalPendingTasks) 个待办")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Add Project Popover
    private var addProjectPopover: some View {
        VStack(spacing: 12) {
            Text("新建项目")
                .font(.headline)

            TextField("项目名称", text: $newProjectName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)

            HStack {
                Button("取消") {
                    newProjectName = ""
                    isAddingProject = false
                }
                .buttonStyle(.plain)

                Spacer()

                Button("创建") {
                    createProject()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 250)
    }

    // MARK: - Helper Methods
    private var totalPendingTasks: Int {
        projects.reduce(0) { $0 + $1.pendingTasksCount }
    }

    private func createProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let maxOrder = projects.map(\.order).max() ?? 0
        let project = Project(name: name, order: maxOrder + 1)
        modelContext.insert(project)

        newProjectName = ""
        isAddingProject = false
    }
}

// MARK: - Project Section View
struct ProjectSectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: Project
    @Binding var selectedProjectId: UUID?
    @Binding var newTaskText: String

    @State private var isExpanded = true
    @State private var isEditing = false
    @State private var editedName = ""

    var body: some View {
        VStack(spacing: 4) {
            // 项目标题行
            projectHeader

            // 任务列表
            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(project.activeTasks) { task in
                        TaskRowView(task: task)
                    }

                    // 快速添加任务
                    quickAddTaskView
                }
                .padding(.leading, 20)
            }
        }
        .padding(.horizontal, 12)
    }

    private var projectHeader: some View {
        HStack {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 16)

            Image(systemName: "folder.fill")
                .foregroundColor(project.isDefault ? .blue : .orange)
                .font(.system(size: 12))

            if isEditing {
                TextField("项目名称", text: $editedName, onCommit: saveProjectName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .onSubmit { saveProjectName() }
            } else {
                Text(project.name)
                    .font(.system(size: 13, weight: .medium))
            }

            Spacer()

            if project.pendingTasksCount > 0 {
                Text("\(project.pendingTasksCount)")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.blue))
            }

            // 删除项目按钮（非默认项目）
            if !project.isDefault {
                Button(action: deleteProject) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .opacity(0.6)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())  // 让整个区域可点击
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.05))
        )
        .onTapGesture(count: 2) {
            // 双击编辑项目名称（非默认项目）
            if !project.isDefault {
                editedName = project.name
                isEditing = true
            }
        }
        .onTapGesture(count: 1) {
            // 单击展开/收起
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }

    private var quickAddTaskView: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            TextField("添加任务...", text: $newTaskText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onSubmit {
                    addTask()
                }
                .onTapGesture {
                    selectedProjectId = project.id
                }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .opacity(selectedProjectId == project.id || newTaskText.isEmpty ? 1 : 0.5)
    }

    private func addTask() {
        let content = newTaskText.trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return }

        let maxOrder = project.tasks.map(\.order).max() ?? 0
        let task = TodoTask(content: content, order: maxOrder + 1)
        task.project = project
        modelContext.insert(task)

        newTaskText = ""
    }

    private func saveProjectName() {
        let name = editedName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty {
            project.name = name
        }
        isEditing = false
    }

    private func deleteProject() {
        modelContext.delete(project)
    }
}

// MARK: - Task Row View
struct TaskRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var task: TodoTask

    @State private var isHovering = false
    @State private var isEditing = false
    @State private var editedContent = ""

    var body: some View {
        HStack(spacing: 8) {
            // 完成状态按钮
            Button(action: { task.toggleComplete() }) {
                Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(task.status == .completed ? .green : .secondary)
            }
            .buttonStyle(.plain)

            // 任务内容
            if isEditing {
                TextField("任务内容", text: $editedContent, onCommit: saveTaskContent)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit { saveTaskContent() }
            } else {
                Text(task.content)
                    .font(.system(size: 12))
                    .strikethrough(task.status == .completed, color: .gray)
                    .foregroundColor(task.status == .completed ? .gray : .primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture(count: 2) {
                        editedContent = task.content
                        isEditing = true
                    }
            }

            // 清除按钮（已完成任务）- 悬停时显示
            if task.status == .completed {
                Button(action: { task.archive() }) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 1 : 0)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())  // 让整个区域可以触发 hover
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovering ? Color.primary.opacity(0.05) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .animation(.easeInOut(duration: 0.15), value: task.status)
    }

    private func saveTaskContent() {
        let content = editedContent.trimmingCharacters(in: .whitespaces)
        if !content.isEmpty {
            task.content = content
        }
        isEditing = false
    }
}

#Preview {
    MenuBarView()
        .modelContainer(for: [Project.self, TodoTask.self, BoardColumn.self], inMemory: true)
}

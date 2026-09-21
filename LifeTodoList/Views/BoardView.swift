import SwiftData
import SwiftUI

struct BoardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BoardColumn.order) private var columns: [BoardColumn]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query private var tasks: [TodoTask]

    let projectFilter: Project?

    @State private var draftColumnName = ""
    @State private var showingNewColumn = false
    @State private var showingRename = false
    @State private var showingDelete = false
    @State private var selectedColumn: BoardColumn?
    @State private var editingTask: TodoTask?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(projectFilter?.name ?? "任务看板")
                        .font(.title2.weight(.semibold))
                    Text("\(pendingCount) 项待办")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    draftColumnName = ""
                    showingNewColumn = true
                } label: {
                    Label("新建栏目", systemImage: "plus.rectangle.on.rectangle")
                }
                .help("新建栏目")
            }
            .padding(.leading, 24)
            .padding(.trailing, 20)
            .padding(.top, 22)
            .padding(.bottom, 18)

            Divider()

            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(columns) { column in
                            columnView(column)
                                .frame(width: max(290, geometry.size.width / CGFloat(max(columns.count, 1))))
                            if column.id != columns.last?.id {
                                Divider()
                            }
                        }
                    }
                    .frame(minHeight: geometry.size.height, alignment: .top)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(.regularMaterial)
        .alert("新建栏目", isPresented: $showingNewColumn) {
            TextField("栏目名称", text: $draftColumnName)
            Button("创建", action: createColumn)
            Button("取消", role: .cancel) { }
        }
        .alert("重命名栏目", isPresented: $showingRename) {
            TextField("栏目名称", text: $draftColumnName)
            Button("保存", action: renameColumn)
            Button("取消", role: .cancel) { }
        }
        .alert("删除栏目", isPresented: $showingDelete) {
            Button("删除", role: .destructive, action: deleteColumn)
            Button("取消", role: .cancel) { }
        } message: {
            Text("栏目中的任务会移动到其他栏目。")
        }
        .sheet(item: $editingTask) { task in
            BoardTaskEditor(task: task, columns: columns, projects: projects)
                .frame(width: 430)
                .padding(22)
        }
    }

    private var pendingCount: Int {
        tasks.filter { $0.status == .pending && (projectFilter == nil || $0.project?.id == projectFilter?.id) }.count
    }

    private func columnView(_ column: BoardColumn) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: column.symbolName)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(column.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(tasks(in: column).count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Menu {
                    Button("重命名", systemImage: "pencil") {
                        selectedColumn = column
                        draftColumnName = column.name
                        showingRename = true
                    }
                    Button("左移", systemImage: "arrow.left") { moveColumn(column, by: -1) }
                        .disabled(columns.first?.id == column.id)
                    Button("右移", systemImage: "arrow.right") { moveColumn(column, by: 1) }
                        .disabled(columns.last?.id == column.id)
                    Divider()
                    Button("删除栏目", systemImage: "trash", role: .destructive) {
                        selectedColumn = column
                        showingDelete = true
                    }
                    .disabled(columns.count < 2)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 26)
                .help("栏目操作")
            }
            .padding(.horizontal, 20)
            .frame(height: 62)

            Divider().padding(.horizontal, 20)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(tasks(in: column)) { task in
                        BoardTaskRow(task: task, columns: columns) {
                            editingTask = task
                        }
                        Divider().padding(.leading, 52)
                    }
                    BoardQuickAdd(column: column, project: projectFilter ?? projects.first(where: \.isDefault))
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .dropDestination(for: String.self) { identifiers, _ in
            guard let id = identifiers.first.flatMap(UUID.init(uuidString:)),
                  let task = tasks.first(where: { $0.id == id }) else { return false }
            task.boardColumn = column
            return true
        }
    }

    private func tasks(in column: BoardColumn) -> [TodoTask] {
        tasks.filter { task in
            task.status != .archived &&
            (task.boardColumn?.id == column.id || (task.boardColumn == nil && columns.first?.id == column.id)) &&
            (projectFilter == nil || task.project?.id == projectFilter?.id)
        }
        .sorted {
            if $0.status != $1.status { return $0.status == .pending }
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.createdAt < $1.createdAt
        }
    }

    private func createColumn() {
        let name = draftColumnName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        modelContext.insert(BoardColumn(name: name, order: (columns.map(\.order).max() ?? -1) + 1))
    }

    private func renameColumn() {
        let name = draftColumnName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        selectedColumn?.name = name
    }

    private func moveColumn(_ column: BoardColumn, by offset: Int) {
        guard let index = columns.firstIndex(where: { $0.id == column.id }),
              columns.indices.contains(index + offset) else { return }
        let other = columns[index + offset]
        let oldOrder = column.order
        column.order = other.order
        other.order = oldOrder
    }

    private func deleteColumn() {
        guard let column = selectedColumn,
              let destination = columns.first(where: { $0.id != column.id }) else { return }
        for task in tasks where task.boardColumn?.id == column.id ||
            (task.boardColumn == nil && columns.first?.id == column.id) {
            task.boardColumn = destination
        }
        modelContext.delete(column)
        selectedColumn = nil
    }
}

private struct BoardQuickAdd: View {
    @Environment(\.modelContext) private var modelContext
    let column: BoardColumn
    let project: Project?
    @State private var text = ""

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "plus")
                .foregroundStyle(.secondary)
            TextField("添加任务", text: $text)
                .textFieldStyle(.plain)
                .onSubmit(addTask)
            if !text.isEmpty {
                Button(action: addTask) {
                    Image(systemName: "arrow.up.circle.fill")
                }
                .buttonStyle(.plain)
                .help("创建任务")
            }
        }
        .padding(.vertical, 9)
    }

    private func addTask() {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        let task = TodoTask(content: content)
        task.boardColumn = column
        task.project = project
        modelContext.insert(task)
        text = ""
    }
}

private struct BoardTaskRow: View {
    @Bindable var task: TodoTask
    let columns: [BoardColumn]
    let edit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { task.toggleComplete() } label: {
                Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(task.status == .completed ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help(task.status == .completed ? "标记未完成" : "完成任务")
            VStack(alignment: .leading, spacing: 6) {
                Text(task.content)
                    .strikethrough(task.status == .completed)
                    .foregroundStyle(task.status == .completed ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, perform: edit)
                if task.project != nil || task.claimedBy != nil {
                    HStack(spacing: 10) {
                        if let project = task.project {
                            Label(project.name, systemImage: "folder")
                        }
                        if let claimedBy = task.claimedBy {
                            Label(claimedBy, systemImage: "person.crop.circle")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
            Button(action: edit) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("任务详情")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .draggable(task.id.uuidString)
        .contextMenu {
            Button("编辑", systemImage: "pencil", action: edit)
            Menu("移动到栏目", systemImage: "arrow.right") {
                ForEach(columns) { column in
                    Button(column.name) { task.boardColumn = column }
                }
            }
            if task.status == .completed {
                Button("归档", systemImage: "archivebox") { task.archive() }
            }
        }
    }
}

private struct BoardTaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var task: TodoTask
    let columns: [BoardColumn]
    let projects: [Project]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("任务详情").font(.title3.weight(.semibold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .help("关闭")
            }
            TextField("任务内容", text: $task.content, axis: .vertical)
                .lineLimit(2...5)
            Picker("栏目", selection: Binding(
                get: { task.boardColumn?.id ?? columns.first?.id ?? UUID() },
                set: { id in task.boardColumn = columns.first(where: { $0.id == id }) }
            )) {
                ForEach(columns) { column in Text(column.name).tag(column.id) }
            }
            Picker("项目", selection: Binding(
                get: { task.project?.id ?? projects.first?.id ?? UUID() },
                set: { id in task.project = projects.first(where: { $0.id == id }) }
            )) {
                ForEach(projects) { project in Text(project.name).tag(project.id) }
            }
            if let claimedBy = task.claimedBy {
                LabeledContent("领取人", value: claimedBy)
            }
            if let report = task.progressReport {
                VStack(alignment: .leading, spacing: 5) {
                    Text("最近进度").font(.caption).foregroundStyle(.secondary)
                    Text(report)
                }
            }
            HStack {
                Button(task.status == .completed ? "恢复待办" : "完成任务") {
                    task.toggleComplete()
                }
                Spacer()
                if task.status == .completed {
                    Button("归档") {
                        task.archive()
                        dismiss()
                    }
                }
            }
        }
    }
}

import AppKit
import Combine
import SwiftData
import SwiftUI

@main
struct LifeTodoListApp: App {
    @NSApplicationDelegateAdaptor(LifeTodoAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class LifeTodoAppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let schema = Schema([Project.self, TodoTask.self, BoardColumn.self])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            try seedDefaults(in: container.mainContext)
            coordinator = AppCoordinator(modelContainer: container)
            coordinator?.start()
        } catch {
            fatalError("无法初始化任务数据: \(error)")
        }
    }

    private func seedDefaults(in context: ModelContext) throws {
        if try context.fetch(FetchDescriptor<Project>(predicate: #Predicate { $0.isDefault == true })).isEmpty {
            context.insert(Project(name: "收件箱", order: 0, isDefault: true))
        }
        if try context.fetch(FetchDescriptor<BoardColumn>()).isEmpty {
            context.insert(BoardColumn(name: "稍后", order: 0, symbolName: "tray"))
            context.insert(BoardColumn(name: "本周", order: 1, symbolName: "calendar"))
            context.insert(BoardColumn(name: "今天", order: 2, symbolName: "sun.max"))
        }
        try context.save()
    }
}

@MainActor
final class AppCoordinator: NSObject, ObservableObject, NSWindowDelegate {
    @Published var selection: SidebarItem = .board

    let mcpServer: MCPServer
    private let modelContainer: ModelContainer
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var managementWindow: NSWindow?

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.mcpServer = MCPServer(modelContainer: modelContainer)
    }

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "LifeTodo")
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        statusItem = item
        updateMCP(enabled: UserDefaults.standard.object(forKey: "mcpEnabled") as? Bool ?? true)
    }

    @objc private func statusItemClicked() {
        if UserDefaults.standard.string(forKey: "statusBarMode") == "window" {
            if let window = managementWindow,
               window.isVisible,
               !window.isMiniaturized,
               window.isKeyWindow {
                window.orderOut(nil)
            } else {
                openManagement(selection)
            }
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover?.isShown == true {
            popover?.performClose(nil)
            return
        }
        if popover == nil {
            let panel = NSPopover()
            panel.behavior = .transient
            panel.contentViewController = NSHostingController(
                rootView: MenuBarView()
                    .environmentObject(self)
                    .modelContainer(modelContainer)
            )
            popover = panel
        }
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func openManagement(_ destination: SidebarItem = .board) {
        selection = destination
        popover?.performClose(nil)
        if managementWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1180, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "LifeTodo"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.minSize = NSSize(width: 800, height: 520)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentViewController = NSHostingController(
                rootView: ManagementView()
                    .environmentObject(self)
                    .modelContainer(modelContainer)
            )
            window.setContentSize(NSSize(width: 1180, height: 720))
            window.center()
            managementWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        if managementWindow?.isMiniaturized == true {
            managementWindow?.deminiaturize(nil)
        }
        managementWindow?.makeKeyAndOrderFront(nil)
        managementWindow?.orderFrontRegardless()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if UserDefaults.standard.bool(forKey: "quitOnWindowClose") {
            NSApp.terminate(nil)
        } else {
            sender.orderOut(nil)
        }
        return false
    }

    func updateMCP(enabled: Bool) {
        if enabled {
            mcpServer.start()
        } else {
            mcpServer.stop()
        }
    }
}

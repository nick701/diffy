import AppKit
import Combine
import DiffyCore
import SwiftUI

@MainActor
final class StatusItemManager: NSObject {
    private let store: DiffyStore
    private let onOpenWindow: () -> Void
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var cancellables: Set<AnyCancellable> = []
    private var popoverDismissObservers: [NSObjectProtocol] = []
    private var lastBadgeState: (added: Int, removed: Int, repoCount: Int, colors: DiffColors)?

    init(store: DiffyStore, onOpenWindow: @escaping () -> Void) {
        self.store = store
        self.onOpenWindow = onOpenWindow
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 420, height: 520)
        popover.contentViewController = NSHostingController(
            rootView: PopoverContentView(store: store, onOpenWindow: { [weak self] in
                self?.popover.performClose(nil)
                self?.onOpenWindow()
            })
        )

        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleClick(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        installPopoverDismissObservers()

        store.$repositories
            .combineLatest(store.$summaries)
            .sink { [weak self] repositories, summaries in
                self?.updateBadge(repositories: repositories, summaries: summaries)
            }
            .store(in: &cancellables)
    }

    private func updateBadge(repositories: [RepositoryConfig], summaries: [UUID: RepoDiffSummary]) {
        guard let button = statusItem.button else { return }

        if repositories.isEmpty {
            if lastBadgeState != nil {
                button.image = nil
                button.title = "Diffy"
                button.imagePosition = .noImage
                button.toolTip = "Diffy — no repositories"
                lastBadgeState = nil
            }
            return
        }

        var totalAdded = 0
        var totalRemoved = 0
        for repository in repositories {
            if let summary = summaries[repository.id] {
                totalAdded += summary.addedLines
                totalRemoved += summary.removedLines
            }
        }

        let colors = repositories.first?.diffColors ?? .default
        let newState = (added: totalAdded, removed: totalRemoved, repoCount: repositories.count, colors: colors)
        if let last = lastBadgeState,
           last.added == newState.added,
           last.removed == newState.removed,
           last.repoCount == newState.repoCount,
           last.colors == newState.colors {
            return
        }

        button.title = ""
        button.image = BadgeRenderer.image(added: totalAdded, removed: totalRemoved, colors: colors)
        button.imagePosition = .imageOnly
        button.toolTip = "Diffy — \(repositories.count) \(repositories.count == 1 ? "repo" : "repos")"
        lastBadgeState = newState
    }

    @objc private func handleClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Diffy", action: #selector(menuOpen), keyEquivalent: "").target = self
        menu.addItem(NSMenuItem.separator())
        let quit = menu.addItem(withTitle: "Quit Diffy", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuOpen() {
        onOpenWindow()
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }

    private func installPopoverDismissObservers() {
        popoverDismissObservers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard
                    let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                    app.bundleIdentifier != Bundle.main.bundleIdentifier
                else { return }
                Task { @MainActor in
                    self?.popover.performClose(nil)
                }
            }
        )
    }
}

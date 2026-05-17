import AppKit
import Combine
import DiffyCore
import SwiftUI

@MainActor
final class StatusItemManager: NSObject {
    private let store: DiffyStore
    private let onOpenWindow: () -> Void
    private var cancellables: Set<AnyCancellable> = []
    private var popoverDismissObservers: [NSObjectProtocol] = []
    private var globalMouseMonitor: Any?
    private var items: [UUID: GroupStatusItem] = [:]
    private var groupOrder: [UUID] = []

    init(store: DiffyStore, onOpenWindow: @escaping () -> Void) {
        self.store = store
        self.onOpenWindow = onOpenWindow
        super.init()

        installPopoverDismissObservers()

        store.$groups
            .combineLatest(store.$repositories, store.$summaries)
            .sink { [weak self] groups, repositories, summaries in
                self?.update(groups: groups, repositories: repositories, summaries: summaries)
            }
            .store(in: &cancellables)
    }

    private func update(
        groups: [RepositoryGroup],
        repositories: [RepositoryConfig],
        summaries: [UUID: RepoDiffSummary]
    ) {
        let desiredOrder = groups.filter { !$0.isHidden }.map { $0.id }

        if desiredOrder != groupOrder {
            // If the new order is the current order with some entries removed
            // (i.e. pure deletion / hide), only tear down the gone items so the
            // surviving icons don't flicker. Any reorder or addition falls back
            // to a full rebuild because AppKit appends new status items to the end.
            let isPureDeletion = groupOrder.filter { desiredOrder.contains($0) } == desiredOrder

            if isPureDeletion {
                let removed = Set(groupOrder).subtracting(desiredOrder)
                for id in removed {
                    if let item = items[id] {
                        NSStatusBar.system.removeStatusItem(item.statusItem)
                        items.removeValue(forKey: id)
                    }
                }
            } else {
                for (_, item) in items {
                    NSStatusBar.system.removeStatusItem(item.statusItem)
                }
                items.removeAll(keepingCapacity: true)
                for group in groups where !group.isHidden {
                    items[group.id] = makeStatusItem(for: group)
                }
            }

            groupOrder = desiredOrder
        }

        for group in groups {
            guard var item = items[group.id] else { continue }
            let visibleRepos = repositories.filter { $0.groupID == group.id && !$0.isHidden }
            var added = 0
            var removed = 0
            for repo in visibleRepos {
                if let summary = summaries[repo.id] {
                    added += summary.addedLines
                    removed += summary.removedLines
                }
            }

            let displayName = group.name.isEmpty ? "Diffy" : group.name
            let newState = BadgeState(
                displayName: displayName,
                added: added,
                removed: removed,
                visibleRepoCount: visibleRepos.count,
                colors: group.diffColors,
                badgeLabel: group.badgeLabel
            )

            if item.lastBadgeState != newState {
                if let button = item.statusItem.button {
                    button.title = ""
                    button.image = BadgeRenderer.image(
                        added: added,
                        removed: removed,
                        colors: group.diffColors,
                        badgeLabel: group.badgeLabel
                    )
                    button.imagePosition = .imageOnly
                    button.toolTip = "\(displayName) — \(visibleRepos.count) visible \(visibleRepos.count == 1 ? "repo" : "repos")"
                }
                item.lastBadgeState = newState
                items[group.id] = item
            }
        }
    }

    private func makeStatusItem(for group: RepositoryGroup) -> GroupStatusItem {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 420, height: 520)
        popover.contentViewController = NSHostingController(
            rootView: PopoverContentView(
                store: store,
                groupID: group.id,
                onOpenWindow: { [weak self, weak popover] in
                    popover?.performClose(nil)
                    self?.onOpenWindow()
                }
            )
        )

        let handler = StatusItemClickHandler(groupID: group.id) { [weak self] event in
            self?.handleClick(groupID: group.id, event: event)
        }

        statusItem.button?.target = handler
        statusItem.button?.action = #selector(StatusItemClickHandler.handle(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        return GroupStatusItem(
            statusItem: statusItem,
            popover: popover,
            clickHandler: handler,
            lastBadgeState: nil
        )
    }

    private func handleClick(groupID: UUID, event: NSEvent?) {
        guard let item = items[groupID] else { return }
        guard let event = event ?? NSApp.currentEvent else {
            togglePopover(item: item)
            return
        }

        if event.type == .rightMouseUp {
            showContextMenu(for: item)
        } else {
            togglePopover(item: item)
        }
    }

    private func togglePopover(item: GroupStatusItem) {
        guard let button = item.statusItem.button else { return }
        if item.popover.isShown {
            item.popover.performClose(nil)
        } else {
            for other in items.values where other.popover.isShown {
                other.popover.performClose(nil)
            }
            item.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showContextMenu(for item: GroupStatusItem) {
        let menu = NSMenu()
        let open = menu.addItem(withTitle: "Open Diffy", action: #selector(menuOpen), keyEquivalent: "")
        open.target = self
        menu.addItem(NSMenuItem.separator())
        let quit = menu.addItem(withTitle: "Quit Diffy", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        item.statusItem.menu = menu
        item.statusItem.button?.performClick(nil)
        item.statusItem.menu = nil
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
                    guard let self else { return }
                    for item in self.items.values where item.popover.isShown {
                        item.popover.performClose(nil)
                    }
                }
            }
        )

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                for item in self.items.values where item.popover.isShown {
                    item.popover.performClose(nil)
                }
            }
        }
    }
}

private struct GroupStatusItem {
    let statusItem: NSStatusItem
    let popover: NSPopover
    let clickHandler: StatusItemClickHandler
    var lastBadgeState: BadgeState?
}

struct BadgeState: Equatable {
    let displayName: String
    let added: Int
    let removed: Int
    let visibleRepoCount: Int
    let colors: DiffColors
    let badgeLabel: BadgeLabel?
}

@MainActor
private final class StatusItemClickHandler: NSObject {
    let groupID: UUID
    private let onClick: (NSEvent?) -> Void

    init(groupID: UUID, onClick: @escaping (NSEvent?) -> Void) {
        self.groupID = groupID
        self.onClick = onClick
    }

    @objc func handle(_ sender: Any?) {
        onClick(NSApp.currentEvent)
    }
}

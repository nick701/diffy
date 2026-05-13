import AppKit
import Combine
import DiffyCore
import SwiftUI

@MainActor
final class StatusItemManager {
    private let store: DiffyStore
    private var controllers: [UUID: RepoStatusItemController] = [:]
    private var emptyController: EmptyStatusItemController?
    private var cancellables: Set<AnyCancellable> = []

    init(store: DiffyStore) {
        self.store = store

        store.$repositories
            .combineLatest(store.$summaries)
            .sink { [weak self] repositories, summaries in
                self?.sync(repositories: repositories, summaries: summaries)
            }
            .store(in: &cancellables)
    }

    private func sync(repositories: [RepositoryConfig], summaries: [UUID: RepoDiffSummary]) {
        let ids = Set(repositories.map(\.id))
        for removedID in Set(controllers.keys).subtracting(ids) {
            controllers[removedID]?.dispose()
            controllers.removeValue(forKey: removedID)
        }

        if repositories.isEmpty {
            if emptyController == nil {
                emptyController = EmptyStatusItemController(store: store)
            }
        } else {
            emptyController?.dispose()
            emptyController = nil
        }

        for repository in repositories {
            let controller = controllers[repository.id] ?? RepoStatusItemController(store: store, repositoryID: repository.id)
            controllers[repository.id] = controller
            controller.update(summary: summaries[repository.id] ?? .empty(for: repository))
        }
    }
}

@MainActor
private final class RepoStatusItemController: NSObject {
    private let store: DiffyStore
    private let repositoryID: UUID
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var currentSummary: RepoDiffSummary?
    private var notificationObservers: [NSObjectProtocol] = []

    init(store: DiffyStore, repositoryID: UUID) {
        self.store = store
        self.repositoryID = repositoryID
        super.init()

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: RepoPopoverView(store: store, repositoryID: repositoryID))

        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        installCloseObservers()
    }

    func update(summary: RepoDiffSummary) {
        currentSummary = summary
        popover.contentSize = PopoverSizing.size(for: summary)
        statusItem.button?.image = BadgeRenderer.image(added: summary.addedLines, removed: summary.removedLines, colors: summary.repository.diffColors)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = summary.repository.displayName
    }

    func dispose() {
        notificationObservers.forEach {
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        notificationObservers.removeAll()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            if let currentSummary {
                popover.contentSize = PopoverSizing.size(for: currentSummary)
            }
            store.refresh(repositoryID: repositoryID)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func installCloseObservers() {
        notificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.popover.performClose(nil)
                }
            }
        )

        notificationObservers.append(
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

@MainActor
private final class EmptyStatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var notificationObservers: [NSObjectProtocol] = []

    init(store: DiffyStore) {
        super.init()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 340, height: 160)
        popover.contentViewController = NSHostingController(rootView: EmptyPopoverView(store: store))
        statusItem.button?.title = "Diffy"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        installCloseObservers()
    }

    func dispose() {
        notificationObservers.forEach {
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        notificationObservers.removeAll()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func installCloseObservers() {
        notificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.popover.performClose(nil)
                }
            }
        )

        notificationObservers.append(
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

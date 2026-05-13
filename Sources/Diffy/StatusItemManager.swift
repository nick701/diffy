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

    init(store: DiffyStore, repositoryID: UUID) {
        self.store = store
        self.repositoryID = repositoryID
        super.init()

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 420, height: 480)
        popover.contentViewController = NSHostingController(rootView: RepoPopoverView(store: store, repositoryID: repositoryID))

        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
    }

    func update(summary: RepoDiffSummary) {
        statusItem.button?.attributedTitle = BadgeFormatter.badge(added: summary.addedLines, removed: summary.removedLines)
        statusItem.button?.toolTip = summary.repository.displayName
    }

    func dispose() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            store.refresh(repositoryID: repositoryID)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

@MainActor
private final class EmptyStatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()

    init(store: DiffyStore) {
        super.init()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 340, height: 160)
        popover.contentViewController = NSHostingController(rootView: EmptyPopoverView(store: store))
        statusItem.button?.title = "Diffy"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
    }

    func dispose() {
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
}

private enum BadgeFormatter {
    static func badge(added: Int, removed: Int) -> NSAttributedString {
        let text = NSMutableAttributedString()
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        text.append(NSAttributedString(string: "+\(added)", attributes: [.foregroundColor: NSColor.systemGreen, .font: font]))
        text.append(NSAttributedString(string: " / ", attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: font]))
        text.append(NSAttributedString(string: "-\(removed)", attributes: [.foregroundColor: NSColor.systemRed, .font: font]))
        return text
    }
}

import Foundation
import Sparkle

@MainActor
final class UpdaterController {
    private let controller: SPUStandardUpdaterController?

    var canCheckForUpdates: Bool {
        controller != nil
    }

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        guard
            info["SUFeedURL"] as? String != nil,
            info["SUPublicEDKey"] as? String != nil
        else {
            controller = nil
            return
        }

        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

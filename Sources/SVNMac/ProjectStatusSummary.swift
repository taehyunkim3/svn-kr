import Foundation
import SVNCore

struct ProjectStatusSummary: Equatable {
    var localChangeCount = 0
    var conflictCount = 0
    var lockCount = 0
    var needsUpdate = false
}

struct RevertRequest: Identifiable, Equatable, Sendable {
    let entry: SVNStatusEntry
    var id: String { entry.path }
}

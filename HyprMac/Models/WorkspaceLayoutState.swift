// The layout each workspace is in right now, and the master size the
// keyboard resize gave it. Runtime state, not a preference: it lives in
// UserDefaults (per Mac, like the menu bar style), so a cycle never
// rewrites config.json or wakes iCloud and the file watcher.

import Foundation
import Combine

/// Per-workspace layout picks and master sizes. Main thread only.
final class WorkspaceLayoutState: ObservableObject {
    static let shared = WorkspaceLayoutState()

    static let activeKey = "workspaceActiveLayouts"
    static let masterFractionKey = "workspaceMasterFractions"

    /// The layout each workspace was last switched to. A workspace with no
    /// entry, or one whose entry is no longer enabled there, shows its
    /// default (`LayoutCycle.current`).
    @Published private(set) var active: [Int: TilingLayout]
    /// Master sizes the keyboard resize set. A workspace with no entry uses
    /// the global master size from Settings.
    @Published private(set) var masterFractions: [Int: CGFloat]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let rawActive = defaults.dictionary(forKey: Self.activeKey) as? [String: String] ?? [:]
        active = Dictionary(uniqueKeysWithValues: rawActive.compactMap { key, value in
            guard let workspace = Int(key), let layout = TilingLayout(rawValue: value) else { return nil }
            return (workspace, layout)
        })
        let rawFractions = defaults.dictionary(forKey: Self.masterFractionKey) as? [String: Double] ?? [:]
        masterFractions = Dictionary(uniqueKeysWithValues: rawFractions.compactMap { key, value in
            Int(key).map { ($0, TileArrangement.clampedFraction(CGFloat(value))) }
        })
    }

    /// nil forgets the pick, so the workspace shows its default.
    func setActive(_ layout: TilingLayout?, forWorkspace workspace: Int) {
        guard active[workspace] != layout else { return }
        active[workspace] = layout
        defaults.set(Dictionary(uniqueKeysWithValues: active.map { (String($0.key), $0.value.rawValue) }),
                     forKey: Self.activeKey)
    }

    /// nil goes back to the global master size.
    func setMasterFraction(_ fraction: CGFloat?, forWorkspace workspace: Int) {
        let clamped = fraction.map(TileArrangement.clampedFraction)
        guard masterFractions[workspace] != clamped else { return }
        masterFractions[workspace] = clamped
        defaults.set(Dictionary(uniqueKeysWithValues: masterFractions.map { (String($0.key), Double($0.value)) }),
                     forKey: Self.masterFractionKey)
    }

    /// Settings' master size is the one every workspace uses again.
    func clearMasterFractions() {
        guard !masterFractions.isEmpty else { return }
        masterFractions = [:]
        defaults.removeObject(forKey: Self.masterFractionKey)
    }
}

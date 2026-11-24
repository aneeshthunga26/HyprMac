// "Use macOS Desktops" mode: each HyprMac workspace is one of the user's
// Mission Control Desktops. Everything here is either a read (which
// Desktops exist, which one each display shows) or the Desktop shortcut
// macOS already offers ("Switch to Desktop N"). Nothing moves another
// app's window between Spaces: with SIP on, macOS refuses that
// (`docs/desktop-switching-notes.md`), so windows move between Desktops
// only through Mission Control and HyprMac follows.

import Cocoa

// MARK: - SkyLight reads

@_silgen_name("SLSMainConnectionID")
private func SLSMainConnectionID() -> Int32

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray?

/// One display's Spaces as Mission Control orders them.
struct DisplayDesktops: Equatable {
    struct Space: Equatable {
        let id: UInt64
        /// A Desktop the user made (type 0). Full-screen apps and other
        /// system Spaces are not Desktops and never map to a workspace.
        let isDesktop: Bool
    }

    /// `"Main"` when "Displays have separate Spaces" is off, else the display's UUID.
    let displayIdentifier: String
    let spaces: [Space]
    let currentSpaceID: UInt64?

    var desktopIDs: [UInt64] { spaces.filter(\.isDesktop).map(\.id) }

    /// Parse one entry of `CGSCopyManagedDisplaySpaces`. nil when it has
    /// no identifier.
    init?(managedDisplay entry: [String: Any]) {
        guard let identifier = entry["Display Identifier"] as? String else { return nil }
        displayIdentifier = identifier
        let rawSpaces = entry["Spaces"] as? [[String: Any]] ?? []
        spaces = rawSpaces.compactMap { space in
            guard let id = (space["id64"] as? NSNumber) ?? (space["ManagedSpaceID"] as? NSNumber) else { return nil }
            return Space(id: id.uint64Value, isDesktop: (space["type"] as? NSNumber)?.intValue ?? 0 == 0)
        }
        let current = entry["Current Space"] as? [String: Any]
        currentSpaceID = ((current?["id64"] as? NSNumber) ?? (current?["ManagedSpaceID"] as? NSNumber))?.uint64Value
    }

    init(displayIdentifier: String, spaces: [Space], currentSpaceID: UInt64?) {
        self.displayIdentifier = displayIdentifier
        self.spaces = spaces
        self.currentSpaceID = currentSpaceID
    }

    /// The live Spaces of every display, in Mission Control order.
    static func current() -> [DisplayDesktops] {
        guard let raw = CGSCopyManagedDisplaySpaces(SLSMainConnectionID()) as? [[String: Any]] else { return [] }
        return raw.compactMap(DisplayDesktops.init(managedDisplay:))
    }
}

// MARK: - workspace ↔ Desktop map

/// Which Desktop each workspace is, and which workspace each display
/// shows. Pure: built from the Spaces snapshot and the workspace homes.
///
/// A display's workspaces (its homes, lowest first) take its Desktops in
/// order: on one display, workspace N is Desktop N. A workspace past the
/// display's last Desktop has none. Full-screen Spaces are skipped. With
/// "Displays have separate Spaces" off there is one list for every
/// display, and only the first display's workspaces map.
struct NativeDesktopMap: Equatable {
    struct Desktop: Equatable {
        /// The display's key in the caller's terms (`WorkspaceManager.screenID`).
        let screenKey: Int
        let spaceID: UInt64
        /// Mission Control's number for the Desktop, counted across every
        /// display: the N in "Switch to Desktop N".
        let number: Int
    }

    /// One display as the caller sees it.
    struct Screen: Equatable {
        let key: Int
        /// The display's UUID, matched against `DisplayDesktops.displayIdentifier`.
        let uuid: String?
        /// Its workspaces, lowest first.
        let workspaces: [Int]
    }

    private(set) var desktops: [Int: Desktop] = [:]
    /// Display → the workspace its current Space is. Missing when the
    /// display shows a Space no workspace maps to (a full-screen app, or a
    /// Desktop past the last workspace).
    private(set) var visible: [Int: Int] = [:]
    /// Displays whose current Space no workspace maps to.
    private(set) var unmapped: Set<Int> = []
    /// Workspaces that would need a Desktop the display does not have.
    private(set) var missing: [Int] = []

    init(displays: [DisplayDesktops], screens: [Screen]) {
        // Mission Control numbers Desktops across displays in this order
        var numbers: [UInt64: Int] = [:]
        var next = 1
        for display in displays {
            for id in display.desktopIDs {
                numbers[id] = next
                next += 1
            }
        }
        let shared = displays.count == 1 && (displays.first?.displayIdentifier == "Main" || screens.count == 1)
        for (index, screen) in screens.enumerated() {
            let display: DisplayDesktops?
            if shared {
                // one list for every display: only the first maps
                display = index == 0 ? displays.first : nil
            } else {
                display = displays.first { $0.displayIdentifier.caseInsensitiveCompare(screen.uuid ?? "") == .orderedSame }
            }
            guard let display else {
                missing += screen.workspaces
                unmapped.insert(screen.key)
                continue
            }
            let ids = display.desktopIDs
            var currentMapped = false
            for (position, workspace) in screen.workspaces.enumerated() {
                guard position < ids.count, let number = numbers[ids[position]] else {
                    missing.append(workspace)
                    continue
                }
                desktops[workspace] = Desktop(screenKey: screen.key, spaceID: ids[position], number: number)
                if ids[position] == display.currentSpaceID {
                    visible[screen.key] = workspace
                    currentMapped = true
                }
            }
            if !currentMapped { unmapped.insert(screen.key) }
        }
        missing.sort()
    }

    /// The workspace a Space is, if any.
    func workspace(forSpace spaceID: UInt64) -> Int? {
        desktops.first { $0.value.spaceID == spaceID }?.key
    }
}

// MARK: - the Desktop shortcuts

/// The "Switch to Desktop N" shortcuts from System Settings → Keyboard →
/// Keyboard Shortcuts → Mission Control. HyprMac switches Desktops by
/// posting them, the only switch that keeps the Dock, Mission Control and
/// the slide animation in step without SIP changes.
struct DesktopShortcut: Equatable {
    let keyCode: CGKeyCode
    let flags: CGEventFlags

    /// Symbolic hotkey ids: Desktop 1 is 118, up to Desktop 16 at 133.
    static func hotkeyID(forDesktop number: Int) -> Int? {
        (1...16).contains(number) ? 117 + number : nil
    }

    /// The shortcut for Desktop `number` from the `AppleSymbolicHotKeys`
    /// dictionary, or nil when it is missing or turned off. Turned off is
    /// the macOS default, so a fresh Mac needs them turned on first.
    static func parse(_ hotkeys: [String: Any], desktop number: Int) -> DesktopShortcut? {
        guard let id = hotkeyID(forDesktop: number),
              let entry = hotkeys[String(id)] as? [String: Any],
              (entry["enabled"] as? NSNumber)?.boolValue == true,
              let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [NSNumber], parameters.count >= 3 else { return nil }
        let keyCode = parameters[1].intValue
        // 65535 is "no key"
        guard keyCode >= 0, keyCode < 0xFFFF else { return nil }
        return DesktopShortcut(keyCode: CGKeyCode(keyCode),
                               flags: CGEventFlags(rawValue: UInt64(parameters[2].uint64Value)))
    }

    /// The live shortcuts.
    static func currentHotkeys() -> [String: Any] {
        UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys") ?? [:]
    }

    /// Marks HyprMac's own posted shortcut, so the Hypr event tap lets it
    /// through untouched.
    static let eventMarker: Int64 = 0x4859_5052_4D44 // "HYPRMD"

    /// Post the shortcut: key down, key up, carrying only its own modifiers.
    func post() {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: Self.eventMarker)
            event.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - status for Settings

/// What Settings says about the Desktops mode on this Mac. Pure.
struct NativeDesktopStatus: Equatable {
    /// Workspaces that have a Desktop, lowest first.
    let mapped: [Int]
    /// Workspaces whose display has too few Desktops.
    let missing: [Int]
    /// Mapped workspaces whose "Switch to Desktop N" shortcut is off.
    let shortcutsOff: [Int]
    /// More than one display with "Displays have separate Spaces" off.
    let sharedSpacesOnSeveralDisplays: Bool

    var isReady: Bool { !mapped.isEmpty && shortcutsOff.isEmpty && !sharedSpacesOnSeveralDisplays }

    init(map: NativeDesktopMap, hotkeys: [String: Any], displays: [DisplayDesktops], screenCount: Int) {
        mapped = map.desktops.keys.sorted()
        missing = map.missing
        shortcutsOff = mapped.filter { workspace in
            guard let number = map.desktops[workspace]?.number else { return true }
            return DesktopShortcut.parse(hotkeys, desktop: number) == nil
        }
        sharedSpacesOnSeveralDisplays = screenCount > 1 && displays.count == 1
    }
}

extension NSScreen {
    /// The display's UUID string, as CoreGraphics names it in the Spaces list.
    var displayUUIDString: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}

// Settings → Workspaces → macOS Desktops. The switch that makes each
// workspace one of this Mac's Mission Control Desktops, and what macOS
// needs set up for it: enough Desktops, their shortcuts, and Spaces that
// keep their order.

import SwiftUI

struct MacDesktopsPanel: View {
    @ObservedObject var config = UserConfig.shared
    @State private var status: NativeDesktopStatus?
    @State private var rearrangesSpaces = false

    var body: some View {
        SettingsCard("macOS Desktops",
                  footer: "HyprMac can't put a window on a Desktop that isn't showing: drag it there in Mission "
                    + "Control and HyprMac follows. Moving a window to a hidden workspace, saving and restoring "
                    + "layouts, and app pins to hidden workspaces are off in this mode.") {
            SettingsRow("Use macOS Desktops for workspaces", icon: "rectangle.3.group",
                    subtitle: "Each workspace is one of your Mission Control Desktops, so Hypr+number slides "
                        + "to it like Ctrl+number. Turning this on or off restarts tiling.",
                    divider: config.useMacDesktops) {
                Toggle("", isOn: $config.useMacDesktops)
                    .toggleStyle(HyprToggleStyle())
                    .labelsHidden()
            }
            if config.useMacDesktops, let status {
                desktopsRow(status)
                shortcutsRow(status)
                if status.sharedSpacesOnSeveralDisplays {
                    SettingsRow("Displays share one set of Spaces", icon: "exclamationmark.triangle",
                            subtitle: "Turn on “Displays have separate Spaces” in Desktop & Dock, then log out and "
                                + "back in. Until then only the first display's workspaces have Desktops.") {
                        Button("Desktop & Dock…") { open("x-apple.systempreferences:com.apple.Desktop-Settings.extension") }
                            .controlSize(.small)
                    }
                }
                SettingsRow(rearrangesSpaces ? "Spaces rearrange themselves" : "Spaces keep their order",
                        icon: rearrangesSpaces ? "exclamationmark.triangle" : "checkmark.circle",
                        subtitle: rearrangesSpaces
                            ? "Turn off “Automatically rearrange Spaces based on most recent use” in Desktop & Dock, "
                                + "or workspace numbers will move between Desktops."
                            : nil,
                        divider: false) {
                    if rearrangesSpaces {
                        Button("Desktop & Dock…") { open("x-apple.systempreferences:com.apple.Desktop-Settings.extension") }
                            .controlSize(.small)
                    }
                }
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: config.useMacDesktops) { _ in refresh() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)) { _ in
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func desktopsRow(_ status: NativeDesktopStatus) -> some View {
        let ok = status.missing.isEmpty
        return SettingsRow(ok ? "Every workspace has a Desktop" : "\(status.missing.count) workspace(s) need a Desktop",
                       icon: ok ? "checkmark.circle" : "plus.rectangle.on.rectangle",
                       subtitle: ok
                           ? "Workspaces \(Self.ranges(status.mapped)) are Desktops in Mission Control order."
                           : "Workspaces \(Self.ranges(status.mapped).ifEmpty("none")) have one. Add Desktops in "
                               + "Mission Control for \(Self.ranges(status.missing)); until then Hypr+number shows a note.") {
            if !ok {
                Button("Mission Control") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
                }
                .controlSize(.small)
            }
        }
    }

    private func shortcutsRow(_ status: NativeDesktopStatus) -> some View {
        let ok = status.shortcutsOff.isEmpty
        return SettingsRow(ok ? "Desktop shortcuts are on" : "Turn on the Desktop shortcuts",
                       icon: ok ? "checkmark.circle" : "keyboard",
                       subtitle: ok
                           ? "HyprMac switches Desktops with them."
                           : "In Keyboard Shortcuts → Mission Control, turn on “Switch to Desktop N” for workspaces "
                               + "\(Self.ranges(status.shortcutsOff)). HyprMac switches Desktops with them.") {
            if !ok {
                Button("Keyboard Shortcuts…") {
                    open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts")
                }
                .controlSize(.small)
            }
        }
    }

    private func refresh() {
        guard config.useMacDesktops else { status = nil; return }
        let displays = DisplayDesktops.current()
        let screens = WorkspaceManager.leftToRight(NSScreen.screens.filter { !config.disabledMonitors.contains($0.localizedName) })
        let names = screens.map(\.localizedName)
        let mapping = WorkspaceHomeResolver.mapping(forDisplays: names, perSet: config.workspaceMonitorsPerDisplaySet,
                                                    fallback: config.workspaceMonitors)
        let homes = WorkspaceHomeResolver.resolve(enabledNames: names, mapping: mapping).homes
        let mapScreens = screens.enumerated().map { index, screen in
            NativeDesktopMap.Screen(key: index, uuid: screen.displayUUIDString,
                                    workspaces: Constants.workspaceRange.filter { homes[$0 - 1] == index })
        }
        let map = NativeDesktopMap(displays: displays, screens: mapScreens)
        status = NativeDesktopStatus(map: map, hotkeys: DesktopShortcut.currentHotkeys(),
                                     displays: displays, screenCount: screens.count)
        // the Dock's default is to rearrange
        rearrangesSpaces = UserDefaults(suiteName: "com.apple.dock")?.object(forKey: "mru-spaces") as? Bool ?? true
    }

    private func open(_ link: String) {
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }

    /// "1–3, 5, 7–10".
    static func ranges(_ numbers: [Int]) -> String {
        var parts: [String] = []
        var start: Int?
        var previous: Int?
        for number in numbers.sorted() {
            if let p = previous, number == p + 1 {
                previous = number
                continue
            }
            if let s = start, let p = previous { parts.append(s == p ? "\(s)" : "\(s)–\(p)") }
            start = number
            previous = number
        }
        if let s = start, let p = previous { parts.append(s == p ? "\(s)" : "\(s)–\(p)") }
        return parts.joined(separator: ", ")
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

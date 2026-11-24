import XCTest
import Cocoa
@testable import HyprMac

// "Use macOS Desktops": the Spaces parse, the workspace ↔ Desktop map, the
// Desktop shortcuts, the Settings status, and the workspace model in that
// mode (no parking, drift follows the shown Desktop, the shown workspace
// comes from macOS).

final class MacDesktopsMapTests: XCTestCase {
    private func display(_ id: String, desktops: [UInt64], fullScreen: [UInt64] = [], current: UInt64?) -> DisplayDesktops {
        DisplayDesktops(displayIdentifier: id,
                        spaces: desktops.map { .init(id: $0, isDesktop: true) }
                            + fullScreen.map { .init(id: $0, isDesktop: false) },
                        currentSpaceID: current)
    }

    func testTheManagedDisplayDictionaryParses() throws {
        let entry: [String: Any] = [
            "Display Identifier": "AAAA",
            "Current Space": ["id64": NSNumber(value: 7), "type": NSNumber(value: 0)],
            "Spaces": [["id64": NSNumber(value: 3), "type": NSNumber(value: 0)],
                       ["ManagedSpaceID": NSNumber(value: 7), "type": NSNumber(value: 0)],
                       ["id64": NSNumber(value: 9), "type": NSNumber(value: 4)]],
        ]
        let parsed = try XCTUnwrap(DisplayDesktops(managedDisplay: entry))
        XCTAssertEqual(parsed.displayIdentifier, "AAAA")
        XCTAssertEqual(parsed.desktopIDs, [3, 7], "the full-screen Space is not a Desktop")
        XCTAssertEqual(parsed.currentSpaceID, 7)
        XCTAssertNil(DisplayDesktops(managedDisplay: ["Spaces": []]))
    }

    func testOneDisplayMapsWorkspaceNToDesktopN() {
        let map = NativeDesktopMap(displays: [display("A", desktops: [11, 12, 13], current: 12)],
                                   screens: [.init(key: 1, uuid: "A", workspaces: Array(1...10))])
        XCTAssertEqual(map.desktops[1], .init(screenKey: 1, spaceID: 11, number: 1))
        XCTAssertEqual(map.desktops[3], .init(screenKey: 1, spaceID: 13, number: 3))
        XCTAssertNil(map.desktops[4])
        XCTAssertEqual(map.missing, Array(4...10))
        XCTAssertEqual(map.visible[1], 2)
        XCTAssertTrue(map.unmapped.isEmpty)
        XCTAssertEqual(map.workspace(forSpace: 13), 3)
    }

    func testAFullScreenSpaceIsSkippedAndShowsNoWorkspace() {
        let map = NativeDesktopMap(displays: [display("A", desktops: [11, 12], fullScreen: [99], current: 99)],
                                   screens: [.init(key: 1, uuid: "A", workspaces: [1, 2, 3])])
        XCTAssertEqual(map.desktops.keys.sorted(), [1, 2])
        XCTAssertNil(map.visible[1])
        XCTAssertEqual(map.unmapped, [1])
    }

    // Mission Control numbers Desktops across displays: the second
    // display's first Desktop is "Desktop 4" when the first has three
    func testSeparateDisplaysNumberDesktopsAcrossBoth() {
        let map = NativeDesktopMap(
            displays: [display("LEFT", desktops: [1, 2, 3], current: 1),
                       display("RIGHT", desktops: [21, 22], current: 22)],
            screens: [.init(key: 10, uuid: "left", workspaces: [1, 3, 5, 7, 9]),
                      .init(key: 20, uuid: "RIGHT", workspaces: [2, 4, 6, 8, 10])])
        XCTAssertEqual(map.desktops[1]?.number, 1)
        XCTAssertEqual(map.desktops[5]?.number, 3)
        XCTAssertEqual(map.desktops[2], .init(screenKey: 20, spaceID: 21, number: 4))
        XCTAssertEqual(map.desktops[4]?.number, 5)
        XCTAssertEqual(map.visible, [10: 1, 20: 4])
        XCTAssertEqual(map.missing, [6, 7, 8, 9, 10])
    }

    func testSharedSpacesMapOnlyTheFirstDisplay() {
        let map = NativeDesktopMap(displays: [display("Main", desktops: [1, 2], current: 2)],
                                   screens: [.init(key: 10, uuid: "x", workspaces: [1, 3]),
                                             .init(key: 20, uuid: "y", workspaces: [2, 4])])
        XCTAssertEqual(map.desktops.keys.sorted(), [1, 3])
        XCTAssertEqual(map.visible, [10: 3])
        XCTAssertEqual(map.missing, [2, 4])
        XCTAssertEqual(map.unmapped, [20])
    }

    func testADisplayMissingFromTheSpacesListHasNoDesktops() {
        let map = NativeDesktopMap(displays: [display("A", desktops: [1], current: 1),
                                              display("B", desktops: [2], current: 2)],
                                   screens: [.init(key: 1, uuid: "A", workspaces: [1]),
                                             .init(key: 2, uuid: "C", workspaces: [2])])
        XCTAssertEqual(map.desktops.keys.sorted(), [1])
        XCTAssertEqual(map.missing, [2])
        XCTAssertEqual(map.unmapped, [2])
    }
}

final class DesktopShortcutTests: XCTestCase {
    private func hotkeys(_ entries: [Int: (enabled: Bool, keyCode: Int, flags: Int)]) -> [String: Any] {
        Dictionary(uniqueKeysWithValues: entries.map { id, entry in
            (String(id), ["enabled": NSNumber(value: entry.enabled),
                          "value": ["parameters": [NSNumber(value: 65535), NSNumber(value: entry.keyCode),
                                                   NSNumber(value: entry.flags)], "type": "standard"]] as [String: Any])
        })
    }

    func testAnEnabledShortcutParses() throws {
        let shortcut = try XCTUnwrap(DesktopShortcut.parse(hotkeys([119: (true, 19, 262_144)]), desktop: 2))
        XCTAssertEqual(shortcut.keyCode, 19)
        XCTAssertEqual(shortcut.flags, .maskControl)
    }

    func testOffMissingOrKeylessIsNil() {
        XCTAssertNil(DesktopShortcut.parse(hotkeys([118: (false, 18, 262_144)]), desktop: 1))
        XCTAssertNil(DesktopShortcut.parse([:], desktop: 1))
        XCTAssertNil(DesktopShortcut.parse(hotkeys([118: (true, 65535, 0)]), desktop: 1))
        XCTAssertNil(DesktopShortcut.parse(hotkeys([118: (true, 18, 262_144)]), desktop: 17), "no Desktop 17 shortcut")
    }

    func testDesktopIDsRunFrom118() {
        XCTAssertEqual(DesktopShortcut.hotkeyID(forDesktop: 1), 118)
        XCTAssertEqual(DesktopShortcut.hotkeyID(forDesktop: 10), 127)
        XCTAssertEqual(DesktopShortcut.hotkeyID(forDesktop: 16), 133)
        XCTAssertNil(DesktopShortcut.hotkeyID(forDesktop: 0))
    }

    func testTheStatusNamesWhatIsMissing() {
        let displays = [DisplayDesktops(displayIdentifier: "A",
                                        spaces: [1, 2, 3].map { .init(id: $0, isDesktop: true) },
                                        currentSpaceID: 1)]
        let map = NativeDesktopMap(displays: displays, screens: [.init(key: 1, uuid: "A", workspaces: Array(1...10))])
        let status = NativeDesktopStatus(map: map, hotkeys: hotkeys([118: (true, 18, 262_144), 119: (false, 19, 262_144)]),
                                         displays: displays, screenCount: 1)
        XCTAssertEqual(status.mapped, [1, 2, 3])
        XCTAssertEqual(status.missing, Array(4...10))
        XCTAssertEqual(status.shortcutsOff, [2, 3])
        XCTAssertFalse(status.isReady)
        XCTAssertFalse(status.sharedSpacesOnSeveralDisplays)
    }

    func testRangesReadLikeAPerson() {
        XCTAssertEqual(MacDesktopsPanel.ranges([1, 2, 3, 5, 7, 8, 9, 10]), "1–3, 5, 7–10")
        XCTAssertEqual(MacDesktopsPanel.ranges([4]), "4")
        XCTAssertEqual(MacDesktopsPanel.ranges([]), "")
    }
}

final class MacDesktopsWorkspaceTests: XCTestCase {
    private func desktops(_ ids: [UInt64], current: UInt64) -> [DisplayDesktops] {
        [DisplayDesktops(displayIdentifier: "Main", spaces: ids.map { .init(id: $0, isDesktop: true) },
                         currentSpaceID: current)]
    }

    func testTheShownWorkspaceComesFromMacOS() {
        let screen = DesktopsTestScreen()
        let workspaces = WorkspaceManager(displayManager: DisplayManager(screenSource: { [screen] }))
        workspaces.initializeMonitors()
        XCTAssertEqual(workspaces.workspaceForScreen(screen), 1)

        // off: nothing reads the Spaces
        XCTAssertTrue(workspaces.syncWithMacDesktops(desktops([5, 6, 7], current: 7)).isEmpty)

        workspaces.usesMacDesktops = true
        XCTAssertEqual(workspaces.syncWithMacDesktops(desktops([5, 6, 7], current: 7)), [screen])
        XCTAssertEqual(workspaces.workspaceForScreen(screen), 3)
        XCTAssertTrue(workspaces.syncWithMacDesktops(desktops([5, 6, 7], current: 7)).isEmpty, "no change, none reported")
        XCTAssertFalse(workspaces.showsUnmappedDesktop(screen))

        // a full-screen app's Space keeps the workspace and marks the display
        let withFullScreen = [DisplayDesktops(displayIdentifier: "Main",
                                              spaces: [5, 6, 7].map { .init(id: $0, isDesktop: true) }
                                                + [.init(id: 50, isDesktop: false)],
                                              currentSpaceID: 50)]
        XCTAssertTrue(workspaces.syncWithMacDesktops(withFullScreen).isEmpty)
        XCTAssertEqual(workspaces.workspaceForScreen(screen), 3)
        XCTAssertTrue(workspaces.showsUnmappedDesktop(screen))
    }

    func testRegularWindowsAreNeverParkedButTheScratchpadIs() {
        let screen = DesktopsTestScreen()
        let workspaces = WorkspaceManager(displayManager: DisplayManager(screenSource: { [screen] }))
        workspaces.usesMacDesktops = true
        let window = DesktopsRecordingWindow(id: 31)
        workspaces.hideInCorner(window, on: screen)
        XCTAssertTrue(window.positions.isEmpty)
        workspaces.hideInCorner(window, on: screen, scratchpad: true)
        XCTAssertEqual(window.positions, [workspaces.hidePosition()])
    }

    // a window seen on screen belongs to the workspace the display shows,
    // even when its recorded workspace calls this display home, and a
    // floater too
    func testDriftFollowsTheShownDesktop() {
        let screen = DesktopsTestScreen()
        let display = DisplayManager(screenSource: { [screen] })
        let workspaces = WorkspaceManager(displayManager: display)
        workspaces.initializeMonitors()
        workspaces.usesMacDesktops = true
        workspaces.syncWithMacDesktops(desktops([5, 6, 7], current: 6))
        XCTAssertEqual(workspaces.workspaceForScreen(screen), 2)
        let cache = WindowStateCache()
        let svc = WindowDiscoveryService(stateCache: cache, accessibility: StubAccessibility(),
                                         displayManager: display, workspaceManager: workspaces,
                                         bundleIDForPID: { _ in nil }, isWindowSizeSettable: { _ in true })
        let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
        let tiled = DesktopsFramedWindow(id: 41, frame: frame)
        let floater = DesktopsFramedWindow(id: 42, frame: frame)
        cache.knownWindowIDs = [41, 42]
        cache.floatingWindowIDs = [42]
        for id: CGWindowID in [41, 42] {
            cache.windowOwners[id] = 8500
            workspaces.assignWindow(id, toWorkspace: 1)
        }

        let changes = svc.computeChanges(snapshot: [tiled, floater], runningPIDs: [8500], excludedBundleIDs: [],
                                         focusedWindowID: 0, unreadableWindowIDs: [])
        XCTAssertEqual(changes.screenDrift.map(\.windowID).sorted(), [41, 42])
        XCTAssertTrue(changes.screenDrift.allSatisfy { $0.fromWorkspace == 1 && $0.toWorkspace == 2 })
    }

    // seen live in a VM: the windows of the Desktop that left read as
    // background tabs, and the tab hold running out handled them as closes
    func testWindowsOnAHiddenDesktopAreNeitherHeldNorClosed() {
        let screen = DesktopsTestScreen()
        let display = DisplayManager(screenSource: { [screen] })
        let workspaces = WorkspaceManager(displayManager: display)
        workspaces.initializeMonitors()
        workspaces.usesMacDesktops = true
        workspaces.syncWithMacDesktops(desktops([5, 6], current: 5))
        let cache = WindowStateCache()
        let access = StubAccessibility()
        let svc = WindowDiscoveryService(stateCache: cache, accessibility: access,
                                         displayManager: display, workspaceManager: workspaces,
                                         bundleIDForPID: { _ in nil }, isWindowSizeSettable: { _ in true })
        let windows = (61...63).map { DesktopsFramedWindow(id: CGWindowID($0), frame: CGRect(x: 100, y: 100, width: 600, height: 500)) }
        for w in windows {
            cache.knownWindowIDs.insert(w.windowID)
            cache.windowOwners[w.windowID] = 8500
            workspaces.assignWindow(w.windowID, toWorkspace: 1)
        }
        _ = svc.computeChanges(snapshot: windows, runningPIDs: [8500], excludedBundleIDs: [],
                               focusedWindowID: 0, unreadableWindowIDs: [])

        // Desktop 2 shows: every walk misses Desktop 1's windows, long past any hold
        workspaces.syncWithMacDesktops(desktops([5, 6], current: 6))
        for _ in 0..<6 {
            let changes = svc.computeChanges(snapshot: [], runningPIDs: [8500], excludedBundleIDs: [],
                                             focusedWindowID: 0, unreadableWindowIDs: [])
            XCTAssertTrue(changes.goneIDs.isEmpty)
        }
        XCTAssertEqual(cache.knownWindowIDs, [61, 62, 63])
        XCTAssertTrue(cache.hiddenWindowIDs.isEmpty)
        XCTAssertEqual(workspaces.windowIDs(onWorkspace: 1), [61, 62, 63])

        // Desktop 1 again: the same windows, still known, nothing new or returned
        workspaces.syncWithMacDesktops(desktops([5, 6], current: 5))
        let back = svc.computeChanges(snapshot: windows, runningPIDs: [8500], excludedBundleIDs: [],
                                      focusedWindowID: 0, unreadableWindowIDs: [])
        XCTAssertTrue(back.newWindows.isEmpty)
        XCTAssertTrue(back.returned.isEmpty)
        XCTAssertTrue(back.screenDrift.isEmpty)
    }

    // the same windows in HyprMac's own workspaces: the display is ws1's
    // home, so a window there is where it belongs
    func testWithoutDesktopsTheHomeScreenRuleStands() {
        let screen = DesktopsTestScreen()
        let display = DisplayManager(screenSource: { [screen] })
        let workspaces = WorkspaceManager(displayManager: display)
        workspaces.initializeMonitors()
        _ = workspaces.switchWorkspace(2, cursorScreen: screen)
        let cache = WindowStateCache()
        let svc = WindowDiscoveryService(stateCache: cache, accessibility: StubAccessibility(),
                                         displayManager: display, workspaceManager: workspaces,
                                         bundleIDForPID: { _ in nil }, isWindowSizeSettable: { _ in true })
        let tiled = DesktopsFramedWindow(id: 51, frame: CGRect(x: 100, y: 100, width: 800, height: 600))
        cache.knownWindowIDs = [51]
        cache.windowOwners[51] = 8500
        workspaces.assignWindow(51, toWorkspace: 1)
        let changes = svc.computeChanges(snapshot: [tiled], runningPIDs: [8500], excludedBundleIDs: [],
                                         focusedWindowID: 0, unreadableWindowIDs: [])
        XCTAssertTrue(changes.screenDrift.isEmpty)
    }

    func testTheSettingLivesInTheMonitorConfigAndToleratesJunk() throws {
        let saved = try JSONDecoder().decode(SavedMonitorConfig.self,
                                             from: Data(#"{"useMacDesktops":true,"disabledMonitors":[]}"#.utf8))
        XCTAssertEqual(saved.useMacDesktops, true)
        let junk = try JSONDecoder().decode(SavedMonitorConfig.self,
                                            from: Data(#"{"useMacDesktops":"yes","disabledMonitors":["X"]}"#.utf8))
        XCTAssertNil(junk.useMacDesktops)
        XCTAssertEqual(junk.disabledMonitors, ["X"])
        let roundTrip = try JSONDecoder().decode(SavedMonitorConfig.self, from: try JSONEncoder().encode(saved))
        XCTAssertEqual(roundTrip.useMacDesktops, true)
    }

}

private final class DesktopsTestScreen: SyntheticScreen {
    override var frame: NSRect { NSRect(x: 0, y: 0, width: 1600, height: 1000) }
    override var visibleFrame: NSRect { frame }
}

private final class DesktopsFramedWindow: HyprWindow {
    let storedFrame: CGRect
    init(id: CGWindowID, frame: CGRect) {
        storedFrame = frame
        super.init(element: AXUIElementCreateApplication(8500), windowID: id, ownerPID: 8500)
    }
    override func readPosition() -> (AXError, CGPoint?) { (.success, storedFrame.origin) }
    override func readSize() -> (AXError, CGSize?) { (.success, storedFrame.size) }
}

private final class DesktopsRecordingWindow: HyprWindow {
    var positions: [CGPoint] = []
    init(id: CGWindowID) {
        super.init(element: AXUIElementCreateApplication(8500), windowID: id, ownerPID: 8500)
    }
    override func setPositionOnly(_ point: CGPoint) -> AXError {
        positions.append(point)
        return .success
    }
}

# Why workspaces are virtual

CGS private APIs do not work for cross-display moves without disabling SIP,
and yabai's approach needs SIP disabled for Dock.app injection. HyprMac uses
AeroSpace's model instead: workspaces live entirely in userspace, and hidden
windows park off to one side. `docs/architecture.md` "Workspaces" describes how.

## Why not CGS private APIs

- `CGSMoveWindowsToManagedSpace` updates metadata but does not visually move
  windows cross-display.
- `CGSRemoveWindowsFromSpaces` + `CGSAddWindowsToSpaces` has the same visual bug.
- The fix (calling from Dock.app context) requires SIP partially disabled.
- `CGSManagedDisplaySetCurrentSpace` works for switching but does not help
  with window movement.

## Tradeoffs

- A 1 px window sliver stays visible in a screen corner.
- macOS Spaces are bypassed. Use one Space per monitor.
- There is no switch animation.

## The macOS Desktops mode

Settings → Workspaces → macOS Desktops (`useMacDesktops`, per Mac in
`monitor-config.json`) makes each workspace one of the user's Mission Control
Desktops instead. It uses only what still works with SIP on: reading the
Spaces, and switching with the shortcut macOS already offers.

- **Map** (`NativeDesktopMap`): a display's workspaces, lowest first, take
  its Desktops in Mission Control order, so on one display workspace N is
  Desktop N. Full-screen app Spaces are skipped. A workspace past the last
  Desktop has none. With "Displays have separate Spaces" off, only the first
  display's workspaces map.
- **Switch**: Hypr+N posts "Switch to Desktop N" (symbolic hotkeys 118–133,
  read from `com.apple.symbolichotkeys`), marked so the Hypr event tap lets
  it through. The shortcut must be on; off is the macOS default. Mission
  Control numbers Desktops across displays, and the map does too.
- **Shown workspace**: macOS decides. `WorkspaceManager.syncWithMacDesktops`
  reads the current Space of each display on every Space change notification
  and before every poll, so a swipe the notification has not reached yet
  cannot read as the new Desktop's windows drifting onto the old workspace.
  A display on a Space no workspace maps to keeps its workspace and nothing
  on it is reassigned.
- **No parking**: `hideInCorner` parks only scratchpad members. The
  redistribution, the park repair and the re-park after a display change do
  nothing. macOS hides the other Desktops, and discovery expects a known
  window of a hidden workspace to be missing from the walk: it is not a tab
  that left, not held, and not closed, so it keeps its tile and its workspace
  until its Desktop shows. Without that, the native-tab hold ran out on them
  and handled them as closes (seen live in a VM).
- **Drift follows the Desktop**: a window substantially on screen belongs to
  the workspace its display shows, floaters included and whatever its home.
  That is how a window dragged to another Desktop in Mission Control gets its
  new workspace.
- **Refused**: a move to a hidden workspace (Hypr+Shift+N, follow, the
  dedicated workspace), a layout restore, the relaunch handoff and app pins
  to hidden workspaces. A move to a workspace showing on another display is a
  monitor move and still works. Turning the mode on or off restarts tiling;
  `stop()` brings parked windows back first, so none is lost.
- **Not covered yet**: moving a window to another Desktop from the keyboard.
  The only SIP-on way known fakes a title-bar drag across a Desktop switch.
  The scratchpad stays on the Desktop it was summoned on.

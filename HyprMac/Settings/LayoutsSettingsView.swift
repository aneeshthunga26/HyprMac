// Settings → Tiling → Layouts. Which tiling layouts the cycle key steps
// through on every workspace, the one each starts in, the master knobs,
// the menu bar symbol, and a per-workspace override of the list.

import SwiftUI

/// The two layout panels at the top of the Layout tab.
struct LayoutsSettingsSection: View {
    @ObservedObject var config = UserConfig.shared
    @ObservedObject private var layoutState = WorkspaceLayoutState.shared
    @State private var editingWorkspace: EditedWorkspace?

    /// `Identifiable` wrapper so the sheet can be driven by `.sheet(item:)`.
    private struct EditedWorkspace: Identifiable {
        let id: Int
    }

    var body: some View {
        VStack(spacing: HyprSpacing.lg) {
            globalPanel
            workspacesPanel
        }
        .sheet(item: $editingWorkspace) { edited in
            WorkspaceLayoutSheet(config: config, workspace: edited.id)
        }
    }

    // MARK: all workspaces

    private var enabled: [TilingLayout] { LayoutCycle.normalized(config.enabledLayouts) }

    /// The starting layout every workspace without its own list uses.
    private var effectiveDefault: TilingLayout {
        enabled.contains(config.defaultLayout) ? config.defaultLayout : (enabled.first ?? .dwindle)
    }

    private var globalPanel: some View {
        SettingsCard("Layouts",
                     footer: "Click a layout to turn it on or off. At least one stays on. A layout that a window "
                        + "can't shrink into is refused and the workspace keeps the one it had.") {
            VStack(alignment: .leading, spacing: 0) {
                LayoutToggleGrid(enabled: enabled, defaultLayout: effectiveDefault) { layout in
                    config.enabledLayouts = LayoutToggleGrid.toggled(layout, in: enabled)
                }
                .padding(HyprSpacing.md)

                Rectangle().fill(Color.settingsHairline).frame(height: 0.5)

                SettingsRow("Starting layout", icon: "flag",
                        subtitle: "Where a workspace starts, and where it goes back to when its layout is turned off.") {
                    Picker("", selection: Binding(get: { effectiveDefault },
                                                  set: { config.defaultLayout = $0 })) {
                        ForEach(enabled) { layout in
                            Text(layout.displayName).tag(layout)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }
                if enabled.contains(where: \.usesMaster) {
                    SettingsRow("Master size", icon: "rectangle.lefthalf.inset.filled",
                            subtitle: "Share of the screen the master takes. Hypr+Ctrl+Shift+arrows move it per workspace.") {
                        HStack(spacing: HyprSpacing.sm) {
                            Slider(value: Binding(get: { config.layoutMasterFraction },
                                                  set: { config.layoutMasterFraction = ($0 * 20).rounded() / 20 }),
                                   in: 0.15...0.85)
                                .frame(width: 150)
                            HyprChip("\(Int((config.layoutMasterFraction * 100).rounded()))%")
                                .frame(width: 50, alignment: .trailing)
                        }
                    }
                    SettingsRow("Windows in the master area", icon: "square.stack.3d.up") {
                        Stepper(value: Binding(get: { config.layoutMasterCount },
                                               set: { config.layoutMasterCount = TileArrangement.clampedCount($0) }),
                                in: 1...TileArrangement.maxMasterCount) {
                            HyprChip("\(config.layoutMasterCount)")
                        }
                    }
                }
                SettingsRow("Show layout in the menu bar", icon: "menubar.rectangle",
                        subtitle: "A small drawing of the focused workspace's layout, after the workspace glyphs.") {
                    Toggle("", isOn: $config.showLayoutInMenuBar)
                        .toggleStyle(HyprToggleStyle())
                        .labelsHidden()
                }
                SettingsRow("Cycle layouts", icon: "rectangle.3.offgrid",
                        subtitle: "Steps the focused workspace through its enabled layouts.",
                        divider: false) {
                    VStack(alignment: .trailing, spacing: 4) {
                        keyBadge(for: .cycleLayout(1), label: "next")
                        keyBadge(for: .cycleLayout(-1), label: "previous")
                    }
                    .fixedSize()
                }
            }
        }
    }

    @ViewBuilder
    private func keyBadge(for action: Action, label: String) -> some View {
        if let bind = config.keybinds.first(where: { $0.action == action }) {
            HStack(spacing: 4) {
                KeybadgeView(bind: bind, fontSize: 11)
                Text(label).font(.hyprCaption).foregroundStyle(Color.settingsTextMuted)
                    .frame(width: 50, alignment: .leading)
            }
        }
    }

    // MARK: per workspace

    private var workspacesPanel: some View {
        SettingsCard("Per-workspace layouts",
                  footer: "A workspace with its own list cycles through only those layouts. "
                    + "The menu shows the layout each workspace is in now; picking one switches it.") {
            ForEach(Constants.workspaceRange, id: \.self) { workspace in
                workspaceRow(workspace, divider: workspace != Constants.workspaceRange.upperBound)
            }
        }
    }

    private func workspaceRow(_ workspace: Int, divider: Bool) -> some View {
        let own = config.workspaceLayouts[String(workspace)]
        let list = config.enabledLayouts(forWorkspace: workspace)
        let start = LayoutCycle.defaultLayout(forWorkspace: workspace, global: config.enabledLayouts,
                                              globalDefault: config.defaultLayout,
                                              overrides: config.workspaceLayouts)
        let current = LayoutCycle.current(forWorkspace: workspace, active: layoutState.active[workspace],
                                          global: config.enabledLayouts, globalDefault: config.defaultLayout,
                                          overrides: config.workspaceLayouts)
        let subtitle = own == nil
            ? "All workspaces' list"
            : "Own list: \(list.map(\.symbol).joined(separator: " ")) · starts in \(start.displayName)"
        return SettingsRow(UserConfig.workspaceDisplayName(workspace, names: config.workspaceNames),
                       icon: own == nil ? "square.dashed" : "square.fill.on.square",
                       subtitle: subtitle, divider: divider) {
            HStack(spacing: HyprSpacing.sm) {
                Menu {
                    ForEach(list) { layout in
                        Button {
                            NotificationCenter.default.post(
                                name: .hyprMacSetWorkspaceLayout, object: nil,
                                userInfo: ["workspace": workspace, "layout": layout.rawValue])
                        } label: {
                            if layout == current {
                                Label(layout.displayName, systemImage: "checkmark")
                            } else {
                                Text(layout.displayName)
                            }
                        }
                    }
                } label: {
                    Text("\(current.symbol)  \(current.displayName)").font(.hyprMonoSm)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("The layout this workspace is in now")
                Button("Edit…") { editingWorkspace = EditedWorkspace(id: workspace) }
                    .controlSize(.small)
                    .fixedSize()
                    .help("Give this workspace its own layouts")
            }
        }
    }
}

// MARK: - toggle grid

/// Every layout as a card with its thumbnail. A tap turns it on or off.
struct LayoutToggleGrid: View {
    let enabled: [TilingLayout]
    let defaultLayout: TilingLayout?
    let onToggle: (TilingLayout) -> Void

    /// `layout` turned on or off in `list`, in the canonical order. The last
    /// layout on stays on.
    static func toggled(_ layout: TilingLayout, in list: [TilingLayout]) -> [TilingLayout] {
        var set = Set(list)
        if set.contains(layout) {
            guard set.count > 1 else { return LayoutCycle.normalized(list) }
            set.remove(layout)
        } else {
            set.insert(layout)
        }
        return LayoutCycle.normalized(Array(set))
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: HyprSpacing.sm)],
                  spacing: HyprSpacing.sm) {
            ForEach(TilingLayout.allCases) { layout in
                LayoutCard(layout: layout,
                           isOn: enabled.contains(layout),
                           isDefault: layout == defaultLayout,
                           isLastOn: enabled == [layout]) {
                    onToggle(layout)
                }
            }
        }
    }
}

private struct LayoutCard: View {
    let layout: TilingLayout
    let isOn: Bool
    let isDefault: Bool
    let isLastOn: Bool
    let onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                LayoutThumbnail(layout: layout, windowCount: 4, highlighted: isOn)
                    .frame(height: 58)
                HStack(spacing: 4) {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isOn ? Color.hyprCyan : Color.settingsTextMuted)
                    Text(layout.displayName)
                        .font(.hyprCaption.weight(.medium))
                        .foregroundStyle(isOn ? Color.settingsText : Color.settingsTextMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 2)
                    Text(layout.symbol)
                        .font(.hyprMonoXs)
                        .foregroundStyle(Color.settingsTextMuted)
                }
                HStack(spacing: 4) {
                    Text(layout.awesomeName)
                        .font(.hyprMonoXs)
                        .foregroundStyle(Color.settingsTextMuted)
                    Spacer(minLength: 0)
                    if isDefault {
                        Text("START")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .kerning(0.5)
                            .foregroundStyle(Color.hyprCyan)
                    }
                }
            }
            .padding(8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: HyprRadius.md, style: .continuous)
                    .fill(isOn ? Color.hyprCyan.opacity(0.07)
                          : (hovering ? Color.settingsTextMuted.opacity(0.08) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: HyprRadius.md, style: .continuous)
                    .strokeBorder(isOn ? Color.hyprCyan.opacity(0.6) : Color.settingsHairline,
                                  lineWidth: isOn ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(isLastOn ? "\(layout.summary) The last layout on stays on." : layout.summary)
        .accessibilityLabel("\(layout.displayName), \(isOn ? "on" : "off")")
    }
}

// MARK: - thumbnail

/// A small drawing of `layout` with `windowCount` windows, from the same
/// geometry the engine uses.
struct LayoutThumbnail: View {
    let layout: TilingLayout
    let windowCount: Int
    var highlighted = true

    var body: some View {
        GeometryReader { geo in
            let size = DwindleLayout.fitSize(in: geo.size, aspect: 16.0 / 10.0)
            let frame = CGRect(x: (geo.size.width - size.width) / 2, y: (geo.size.height - size.height) / 2,
                               width: size.width, height: size.height)
            let inner = frame.insetBy(dx: 3, dy: 3)
            let rects = thumbnailRects(in: inner)
            let base = highlighted ? Color.hyprCyan : Color.settingsTextMuted

            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.settingsHairline, lineWidth: 0.5)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
            ForEach(Array(rects.enumerated()), id: \.offset) { index, rect in
                RoundedRectangle(cornerRadius: 2)
                    .fill(base.opacity(0.55 - Double(index) * 0.09))
                    .overlay(RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.settingsBackground.opacity(layout == .monocle ? 0.9 : 0), lineWidth: 1))
                    .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                    .position(x: rect.midX, y: rect.midY)
            }
        }
    }

    // monocle's windows share one frame, so they are fanned out a little to
    // read as a stack, the frontmost last
    private func thumbnailRects(in inner: CGRect) -> [CGRect] {
        guard layout == .monocle else {
            return TilingLayoutGeometry.rects(layout, count: windowCount, in: inner, gap: 2)
        }
        let step: CGFloat = 3
        let count = min(windowCount, 3)
        let spread = CGFloat(count - 1) * step
        var rects: [CGRect] = []
        for index in 0..<count {
            let offset = CGFloat(index) * step
            rects.append(CGRect(x: inner.minX + offset, y: inner.minY + offset,
                                width: inner.width - spread, height: inner.height - spread))
        }
        return rects
    }
}

// MARK: - per-workspace sheet

/// One workspace's own layout list and starting layout.
struct WorkspaceLayoutSheet: View {
    @ObservedObject var config: UserConfig
    let workspace: Int
    @Environment(\.dismiss) private var dismiss

    private var override: WorkspaceLayoutOverride? { config.workspaceLayouts[String(workspace)] }
    private var name: String { UserConfig.workspaceDisplayName(workspace, names: config.workspaceNames) }

    var body: some View {
        VStack(alignment: .leading, spacing: HyprSpacing.lg) {
            VStack(alignment: .leading, spacing: HyprSpacing.xs) {
                Text("Layouts for \(name)")
                    .font(.hyprTitle)
                Text("Give this workspace its own layouts to cycle through, or let it use the list every "
                     + "workspace shares.")
                    .font(.hyprCaption)
                    .foregroundStyle(Color.settingsTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HyprPanel {
                SettingsRow("Use its own layouts", icon: "square.fill.on.square",
                        subtitle: override == nil ? "Uses the list for all workspaces." : nil,
                        divider: override != nil) {
                    Toggle("", isOn: Binding(
                        get: { override != nil },
                        set: { on in
                            config.setWorkspaceLayoutOverride(
                                on ? WorkspaceLayoutOverride(enabled: config.enabledLayouts,
                                                             defaultLayout: config.defaultLayout) : nil,
                                forWorkspace: workspace)
                        }))
                        .toggleStyle(HyprToggleStyle())
                        .labelsHidden()
                }
                if let override {
                    let list = LayoutCycle.normalized(override.enabled)
                    SettingsRow("Starting layout", icon: "flag", divider: false) {
                        Picker("", selection: Binding(
                            get: { override.defaultLayout.flatMap { list.contains($0) ? $0 : nil } ?? list[0] },
                            set: { pick in
                                config.setWorkspaceLayoutOverride(
                                    WorkspaceLayoutOverride(enabled: list, defaultLayout: pick),
                                    forWorkspace: workspace)
                            })) {
                            ForEach(list) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 190)
                    }
                }
            }

            if let override {
                let list = LayoutCycle.normalized(override.enabled)
                LayoutToggleGrid(enabled: list,
                                 defaultLayout: override.defaultLayout.flatMap { list.contains($0) ? $0 : nil }
                                    ?? list.first) { layout in
                    config.setWorkspaceLayoutOverride(
                        WorkspaceLayoutOverride(enabled: LayoutToggleGrid.toggled(layout, in: list),
                                                defaultLayout: override.defaultLayout),
                        forWorkspace: workspace)
                }
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(HyprSpacing.xl)
        .frame(width: 560)
    }
}

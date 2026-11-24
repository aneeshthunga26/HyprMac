// The tiling layouts a workspace can use, after awesome's suite: the
// existing BSP dwindle plus master/stack, fair grid, spiral, columns,
// rows, centered master, corner and monocle. Pure: the geometry, the
// per-workspace enable lists and the cycle are all value math, so the
// engine, Settings previews and tests share one copy.

import CoreGraphics

/// One way to arrange a workspace's tiles.
///
/// Raw values are the config wire format (`enabledLayouts`,
/// `workspaceLayouts`, the active-layout store). Never rename one; a
/// value an older build does not know is dropped when it decodes.
enum TilingLayout: String, Codable, CaseIterable, Identifiable, Hashable {
    /// HyprMac's BSP tree: smart insert, split toggles, ratio memory.
    case dwindle
    /// Master column on the left, the stack in a column on the right.
    case tile
    /// Master column on the right, the stack on the left.
    case tileLeft
    /// Master row on top, the stack in a row along the bottom.
    case tileBottom
    /// Master row along the bottom, the stack in a row on top.
    case tileTop
    /// Even grid, filled row by row. A short last row stretches.
    case fair
    /// Even grid, filled column by column. A short last column stretches.
    case fairHorizontal
    /// Each window takes half of what is left, turning clockwise.
    case spiral
    /// Equal columns side by side.
    case columns
    /// Equal rows stacked top to bottom.
    case rows
    /// Master in the middle, the stack split between both sides.
    case centeredMaster
    /// Master in the top left corner, the stack along the right and bottom.
    case corner
    /// Every window fills the workspace; the focused one is on top.
    case monocle

    var id: String { rawValue }

    /// The shipped defaults: one of each family, so the cycle key has
    /// somewhere to go without a trip to Settings.
    static let defaultEnabled: [TilingLayout] = [.dwindle, .tile, .tileBottom, .fair, .monocle]

    var displayName: String {
        switch self {
        case .dwindle: return "Dwindle"
        case .tile: return "Master stack"
        case .tileLeft: return "Master stack (right)"
        case .tileBottom: return "Master stack (row)"
        case .tileTop: return "Master stack (top row)"
        case .fair: return "Grid"
        case .fairHorizontal: return "Grid (by column)"
        case .spiral: return "Spiral"
        case .columns: return "Columns"
        case .rows: return "Rows"
        case .centeredMaster: return "Centered master"
        case .corner: return "Corner"
        case .monocle: return "Monocle"
        }
    }

    /// The awesome layout this one follows, for people coming from it.
    var awesomeName: String {
        switch self {
        case .dwindle: return "dwindle (BSP)"
        case .tile: return "tile"
        case .tileLeft: return "tile.left"
        case .tileBottom: return "tile.bottom"
        case .tileTop: return "tile.top"
        case .fair: return "fair"
        case .fairHorizontal: return "fair.horizontal"
        case .spiral: return "spiral"
        case .columns: return "columns"
        case .rows: return "rows"
        case .centeredMaster: return "centerwork"
        case .corner: return "corner.nw"
        case .monocle: return "max"
        }
    }

    /// A short text symbol in the dwm tradition. The menu bar label can
    /// carry one image and one line of text, so the layout rides in the
    /// text.
    var symbol: String {
        switch self {
        case .dwindle: return "[\\]"
        case .tile: return "[]="
        case .tileLeft: return "=[]"
        case .tileBottom: return "TTT"
        case .tileTop: return "\u{22A5}\u{22A5}\u{22A5}"
        case .fair: return "###"
        case .fairHorizontal: return "#|#"
        case .spiral: return "[@]"
        case .columns: return "|||"
        case .rows: return "\u{2261}"
        case .centeredMaster: return "|M|"
        case .corner: return "[\u{231C}]"
        case .monocle: return "[M]"
        }
    }

    /// One line for the Settings list.
    var summary: String {
        switch self {
        case .dwindle: return "Each window splits the focused tile. Hypr+J flips a split."
        case .tile: return "Master on the left, the rest stacked on the right."
        case .tileLeft: return "Master on the right, the rest stacked on the left."
        case .tileBottom: return "Master across the top, the rest in a row below."
        case .tileTop: return "Master across the bottom, the rest in a row above."
        case .fair: return "An even grid, filled row by row."
        case .fairHorizontal: return "An even grid, filled column by column."
        case .spiral: return "Each window takes half of what is left, turning clockwise."
        case .columns: return "Every window in its own full-height column."
        case .rows: return "Every window in its own full-width row."
        case .centeredMaster: return "Master in the middle, the rest on both sides."
        case .corner: return "Master in the top left, the rest along the right and bottom."
        case .monocle: return "Every window fills the screen. Hypr+arrows step through them."
        }
    }

    /// The BSP tree decides the frames; every other layout derives them
    /// from the window order alone.
    var isTreeDriven: Bool { self == .dwindle }

    /// Master size and master count change this layout.
    var usesMaster: Bool {
        switch self {
        case .tile, .tileLeft, .tileBottom, .tileTop, .centeredMaster, .corner, .spiral: return true
        case .dwindle, .fair, .fairHorizontal, .columns, .rows, .monocle: return false
        }
    }
}

/// What a tree needs to lay itself out: the layout, and the master knobs
/// the master layouts read.
struct TileArrangement: Equatable {
    var layout: TilingLayout
    /// Share of the axis the master takes, clamped to the split ratio
    /// bounds at use.
    var masterFraction: CGFloat
    /// Windows in the master area. At least one.
    var masterCount: Int

    static let defaultMasterFraction: CGFloat = 0.55
    static let defaultMasterCount = 1
    static let maxMasterCount = 4
    /// One keyboard resize step on the master boundary.
    static let masterStep: CGFloat = 0.05

    static let dwindle = TileArrangement(layout: .dwindle,
                                         masterFraction: defaultMasterFraction,
                                         masterCount: defaultMasterCount)

    init(layout: TilingLayout, masterFraction: CGFloat = defaultMasterFraction,
         masterCount: Int = defaultMasterCount) {
        self.layout = layout
        self.masterFraction = masterFraction
        self.masterCount = masterCount
    }

    static func clampedFraction(_ value: CGFloat) -> CGFloat {
        min(max(value, 0.15), 0.85)
    }

    static func clampedCount(_ value: Int) -> Int {
        min(max(value, 1), maxMasterCount)
    }
}

// MARK: - geometry

/// Frames for the order-driven layouts. Every rect is in the same
/// coordinate space as `bounds` (CG, y down: the top is `minY`), already
/// inset by the outer padding. `gap` separates neighbours.
enum TilingLayoutGeometry {
    enum Axis { case horizontal, vertical }

    /// `count` rects for `layout` inside `bounds`, in window order. Dwindle
    /// has no order-driven form; asking for it returns the dwindle preview
    /// so Settings can draw it with the rest.
    static func rects(_ layout: TilingLayout, count: Int, in bounds: CGRect, gap: CGFloat,
                      masterFraction: CGFloat = TileArrangement.defaultMasterFraction,
                      masterCount: Int = TileArrangement.defaultMasterCount) -> [CGRect] {
        guard count > 0 else { return [] }
        guard count > 1 else { return [bounds] }
        let fraction = TileArrangement.clampedFraction(masterFraction)
        let masters = TileArrangement.clampedCount(masterCount)
        switch layout {
        case .dwindle:
            return DwindleLayout.rects(count: count, in: bounds, gap: gap)
        case .tile:
            return masterStack(count, bounds, gap, fraction, masters, axis: .horizontal, masterFirst: true)
        case .tileLeft:
            return masterStack(count, bounds, gap, fraction, masters, axis: .horizontal, masterFirst: false)
        case .tileBottom:
            return masterStack(count, bounds, gap, fraction, masters, axis: .vertical, masterFirst: true)
        case .tileTop:
            return masterStack(count, bounds, gap, fraction, masters, axis: .vertical, masterFirst: false)
        case .fair:
            return grid(count, bounds, gap, byRow: true)
        case .fairHorizontal:
            return grid(count, bounds, gap, byRow: false)
        case .spiral:
            return spiral(count, bounds, gap, fraction)
        case .columns:
            return divide(bounds, into: count, along: .horizontal, gap: gap)
        case .rows:
            return divide(bounds, into: count, along: .vertical, gap: gap)
        case .centeredMaster:
            return centeredMaster(count, bounds, gap, fraction, masters)
        case .corner:
            return corner(count, bounds, gap, fraction)
        case .monocle:
            return Array(repeating: bounds, count: count)
        }
    }

    /// `rect` cut in two along `axis` at `fraction`, `gap` between the parts.
    /// `.horizontal` gives left and right, `.vertical` top and bottom.
    static func split(_ rect: CGRect, along axis: Axis, at fraction: CGFloat,
                      gap: CGFloat) -> (CGRect, CGRect) {
        let halfGap = gap / 2
        switch axis {
        case .horizontal:
            let mid = rect.minX + rect.width * fraction
            return (CGRect(x: rect.minX, y: rect.minY, width: mid - rect.minX - halfGap, height: rect.height),
                    CGRect(x: mid + halfGap, y: rect.minY, width: rect.maxX - mid - halfGap, height: rect.height))
        case .vertical:
            let mid = rect.minY + rect.height * fraction
            return (CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: mid - rect.minY - halfGap),
                    CGRect(x: rect.minX, y: mid + halfGap, width: rect.width, height: rect.maxY - mid - halfGap))
        }
    }

    /// `count` equal parts of `rect` side by side (`.horizontal`) or stacked
    /// (`.vertical`), `gap` between each pair.
    static func divide(_ rect: CGRect, into count: Int, along axis: Axis, gap: CGFloat) -> [CGRect] {
        guard count > 0 else { return [] }
        let n = CGFloat(count)
        switch axis {
        case .horizontal:
            let width = (rect.width - gap * (n - 1)) / n
            return (0..<count).map { i in
                CGRect(x: rect.minX + CGFloat(i) * (width + gap), y: rect.minY, width: width, height: rect.height)
            }
        case .vertical:
            let height = (rect.height - gap * (n - 1)) / n
            return (0..<count).map { i in
                CGRect(x: rect.minX, y: rect.minY + CGFloat(i) * (height + gap), width: rect.width, height: height)
            }
        }
    }

    /// awesome's tile family. `axis` is the master/stack cut: horizontal
    /// puts them side by side, vertical stacks them. `masterFirst` puts the
    /// master on the left or top. Masters and stack windows run across the
    /// cut: stacked in a side-by-side layout, side by side in a stacked one.
    private static func masterStack(_ count: Int, _ bounds: CGRect, _ gap: CGFloat,
                                    _ fraction: CGFloat, _ masters: Int,
                                    axis: Axis, masterFirst: Bool) -> [CGRect] {
        let across: Axis = axis == .horizontal ? .vertical : .horizontal
        // no stack: the masters share the whole area
        guard count > masters else { return divide(bounds, into: count, along: across, gap: gap) }
        let (first, second) = split(bounds, along: axis, at: masterFirst ? fraction : 1 - fraction, gap: gap)
        let masterArea = masterFirst ? first : second
        let stackArea = masterFirst ? second : first
        return divide(masterArea, into: masters, along: across, gap: gap)
            + divide(stackArea, into: count - masters, along: across, gap: gap)
    }

    /// awesome's fair: about square. `byRow` fills rows left to right and
    /// stretches a short last row; otherwise columns, top to bottom.
    private static func grid(_ count: Int, _ bounds: CGRect, _ gap: CGFloat, byRow: Bool) -> [CGRect] {
        let major = Int(ceil(sqrt(Double(count))))
        let lines = Int(ceil(Double(count) / Double(major)))
        // byRow: `lines` rows of up to `major` columns
        let lineRects = divide(bounds, into: lines, along: byRow ? .vertical : .horizontal, gap: gap)
        var result: [CGRect] = []
        var remaining = count
        for (index, line) in lineRects.enumerated() {
            let inLine = index == lines - 1 ? remaining : min(major, remaining)
            result += divide(line, into: inLine, along: byRow ? .horizontal : .vertical, gap: gap)
            remaining -= inLine
        }
        return result
    }

    /// awesome's spiral: the first window takes `fraction` of the width,
    /// each later one half of what is left, turning right, down, left, up.
    private static func spiral(_ count: Int, _ bounds: CGRect, _ gap: CGFloat, _ fraction: CGFloat) -> [CGRect] {
        var result: [CGRect] = []
        var remaining = bounds
        for index in 0..<count {
            if index == count - 1 {
                result.append(remaining)
                break
            }
            let share = index == 0 ? fraction : 0.5
            switch index % 4 {
            case 0:
                let (window, rest) = split(remaining, along: .horizontal, at: share, gap: gap)
                result.append(window); remaining = rest
            case 1:
                let (window, rest) = split(remaining, along: .vertical, at: share, gap: gap)
                result.append(window); remaining = rest
            case 2:
                let (rest, window) = split(remaining, along: .horizontal, at: 1 - share, gap: gap)
                result.append(window); remaining = rest
            default:
                let (rest, window) = split(remaining, along: .vertical, at: 1 - share, gap: gap)
                result.append(window); remaining = rest
            }
        }
        return result
    }

    /// Master column in the middle, `fraction` of the width. The stack
    /// alternates right, left, right… and each side stacks its share. With
    /// one stack window it sits on the right, as in tile.
    private static func centeredMaster(_ count: Int, _ bounds: CGRect, _ gap: CGFloat,
                                       _ fraction: CGFloat, _ masters: Int) -> [CGRect] {
        guard count > masters else { return divide(bounds, into: count, along: .vertical, gap: gap) }
        let stackCount = count - masters
        if stackCount == 1 {
            return masterStack(count, bounds, gap, fraction, masters, axis: .horizontal, masterFirst: true)
        }
        let sideWidth = (bounds.width - bounds.width * fraction) / 2
        let left = CGRect(x: bounds.minX, y: bounds.minY, width: sideWidth - gap / 2, height: bounds.height)
        let center = CGRect(x: bounds.minX + sideWidth + gap / 2, y: bounds.minY,
                            width: bounds.width - 2 * sideWidth - gap, height: bounds.height)
        let right = CGRect(x: bounds.maxX - sideWidth + gap / 2, y: bounds.minY,
                           width: sideWidth - gap / 2, height: bounds.height)
        let rightCount = (stackCount + 1) / 2
        let rightRects = divide(right, into: rightCount, along: .vertical, gap: gap)
        let leftRects = divide(left, into: stackCount - rightCount, along: .vertical, gap: gap)
        var stack: [CGRect] = []
        for index in 0..<stackCount {
            stack.append(index % 2 == 0 ? rightRects[index / 2] : leftRects[index / 2])
        }
        return divide(center, into: masters, along: .vertical, gap: gap) + stack
    }

    /// awesome's corner.nw: one master in the top left, `fraction` of each
    /// side. The stack fills a full-height column on the right first, then a
    /// row under the master.
    private static func corner(_ count: Int, _ bounds: CGRect, _ gap: CGFloat, _ fraction: CGFloat) -> [CGRect] {
        let stackCount = count - 1
        let (masterColumn, rightColumn) = split(bounds, along: .horizontal, at: fraction, gap: gap)
        if stackCount == 1 { return [masterColumn, rightColumn] }
        let (master, bottomRow) = split(masterColumn, along: .vertical, at: fraction, gap: gap)
        let rightCount = (stackCount + 1) / 2
        return [master]
            + divide(rightColumn, into: rightCount, along: .vertical, gap: gap)
            + divide(bottomRow, into: stackCount - rightCount, along: .horizontal, gap: gap)
    }
}

// MARK: - per-workspace settings

/// A workspace's own layout list, in place of the global one.
struct WorkspaceLayoutOverride: Codable, Equatable {
    /// The layouts the cycle key steps through on this workspace. Never
    /// empty once resolved; an empty list falls back to the global one.
    var enabled: [TilingLayout]
    /// The layout the workspace starts in. nil is the first enabled one.
    var defaultLayout: TilingLayout?

    init(enabled: [TilingLayout], defaultLayout: TilingLayout? = nil) {
        self.enabled = enabled
        self.defaultLayout = defaultLayout
    }

    private enum CodingKeys: String, CodingKey { case enabled, defaultLayout }

    // a layout a newer build added is dropped, not the whole override
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? c.decode([String].self, forKey: .enabled)) ?? []
        enabled = raw.compactMap(TilingLayout.init(rawValue:))
        defaultLayout = (try? c.decodeIfPresent(String.self, forKey: .defaultLayout))
            .flatMap { $0 }.flatMap(TilingLayout.init(rawValue:))
    }
}

/// The rules that pick a workspace's layout: which layouts it may use,
/// where it starts, and where the cycle key goes next. Pure.
enum LayoutCycle {
    /// `layouts` in the canonical order, each once. The order the cycle and
    /// Settings use, whatever order a hand edit wrote them in.
    static func normalized(_ layouts: [TilingLayout]) -> [TilingLayout] {
        let set = Set(layouts)
        return TilingLayout.allCases.filter { set.contains($0) }
    }

    /// The layouts `workspace` may use: its override when it has a usable
    /// one, else the global list, else dwindle alone.
    static func enabled(forWorkspace workspace: Int, global: [TilingLayout],
                        overrides: [String: WorkspaceLayoutOverride]) -> [TilingLayout] {
        if let own = overrides[String(workspace)].map({ normalized($0.enabled) }), !own.isEmpty { return own }
        let shared = normalized(global)
        return shared.isEmpty ? [.dwindle] : shared
    }

    /// The layout `workspace` starts in.
    static func defaultLayout(forWorkspace workspace: Int, global: [TilingLayout],
                              globalDefault: TilingLayout?,
                              overrides: [String: WorkspaceLayoutOverride]) -> TilingLayout {
        let list = enabled(forWorkspace: workspace, global: global, overrides: overrides)
        let override = overrides[String(workspace)]
        let usesOwn = override.map { !normalized($0.enabled).isEmpty } ?? false
        let preferred = usesOwn ? override?.defaultLayout : globalDefault
        if let preferred, list.contains(preferred) { return preferred }
        return list[0]
    }

    /// The layout `workspace` shows: the one the user picked while it is
    /// still enabled there, else its default.
    static func current(forWorkspace workspace: Int, active: TilingLayout?, global: [TilingLayout],
                        globalDefault: TilingLayout?,
                        overrides: [String: WorkspaceLayoutOverride]) -> TilingLayout {
        let list = enabled(forWorkspace: workspace, global: global, overrides: overrides)
        if let active, list.contains(active) { return active }
        return defaultLayout(forWorkspace: workspace, global: global,
                             globalDefault: globalDefault, overrides: overrides)
    }

    /// `delta` steps from `current` through `enabled`, wrapping. A current
    /// layout that is not in the list starts from the first.
    static func step(from current: TilingLayout, by delta: Int, in enabled: [TilingLayout]) -> TilingLayout {
        guard !enabled.isEmpty else { return current }
        guard let index = enabled.firstIndex(of: current) else { return enabled[0] }
        let count = enabled.count
        return enabled[((index + delta) % count + count) % count]
    }
}

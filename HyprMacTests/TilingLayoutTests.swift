import XCTest
import Cocoa
@testable import HyprMac

// the awesome-style layouts: their geometry, the per-workspace cycle, the
// order-driven tree, the fit check, the master keys, the config keys and
// the engine laying a workspace out again when its layout changes.

final class TilingLayoutGeometryTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1600, height: 1000)
    private let gap: CGFloat = 10
    private let orderDriven = TilingLayout.allCases.filter { !$0.isTreeDriven }

    func testEveryLayoutGivesOneRectPerWindowInsideTheBounds() {
        for layout in TilingLayout.allCases {
            for count in 0...9 {
                let rects = TilingLayoutGeometry.rects(layout, count: count, in: bounds, gap: gap)
                XCTAssertEqual(rects.count, count, "\(layout) × \(count)")
                for rect in rects {
                    XCTAssertTrue(bounds.insetBy(dx: -0.5, dy: -0.5).contains(rect), "\(layout) × \(count): \(rect)")
                    XCTAssertGreaterThan(rect.width, 0, "\(layout) × \(count)")
                    XCTAssertGreaterThan(rect.height, 0, "\(layout) × \(count)")
                }
            }
        }
    }

    func testOneWindowFillsTheBoundsInEveryLayout() {
        for layout in TilingLayout.allCases {
            XCTAssertEqual(TilingLayoutGeometry.rects(layout, count: 1, in: bounds, gap: gap), [bounds], "\(layout)")
        }
    }

    // tiles never overlap and keep the gap; only monocle stacks on purpose
    func testTiledLayoutsKeepTheGapAndNeverOverlap() {
        for layout in orderDriven where layout != .monocle {
            for count in 2...9 {
                let rects = TilingLayoutGeometry.rects(layout, count: count, in: bounds, gap: gap)
                for i in rects.indices {
                    for j in rects.indices where j > i {
                        let a = rects[i], b = rects[j]
                        let xSeparation = max(a.minX, b.minX) - min(a.maxX, b.maxX)
                        let ySeparation = max(a.minY, b.minY) - min(a.maxY, b.maxY)
                        XCTAssertGreaterThanOrEqual(max(xSeparation, ySeparation), gap - 0.001,
                                                    "\(layout) × \(count): \(a) / \(b)")
                    }
                }
            }
        }
    }

    // the tiles plus the gaps between them cover the whole area
    func testTiledLayoutsLeaveNoHoles() {
        for layout in orderDriven where layout != .monocle {
            for count in 2...9 {
                let rects = TilingLayoutGeometry.rects(layout, count: count, in: bounds, gap: 0)
                let area = rects.reduce(CGFloat(0)) { $0 + $1.width * $1.height }
                XCTAssertEqual(area, bounds.width * bounds.height, accuracy: 1, "\(layout) × \(count)")
            }
        }
    }

    func testTileHasTheMasterOnTheLeftAndTheStackStackedOnTheRight() {
        let rects = TilingLayoutGeometry.rects(.tile, count: 3, in: bounds, gap: 0, masterFraction: 0.6)
        XCTAssertEqual(rects[0], CGRect(x: 0, y: 0, width: 960, height: 1000))
        XCTAssertEqual(rects[1], CGRect(x: 960, y: 0, width: 640, height: 500))
        XCTAssertEqual(rects[2], CGRect(x: 960, y: 500, width: 640, height: 500))
    }

    func testTileLeftMirrorsTile() {
        let rects = TilingLayoutGeometry.rects(.tileLeft, count: 2, in: bounds, gap: 0, masterFraction: 0.6)
        XCTAssertEqual(rects[0], CGRect(x: 640, y: 0, width: 960, height: 1000))
        XCTAssertEqual(rects[1], CGRect(x: 0, y: 0, width: 640, height: 1000))
    }

    func testTileBottomPutsTheMasterOnTopAndTheStackInARow() {
        let rects = TilingLayoutGeometry.rects(.tileBottom, count: 3, in: bounds, gap: 0, masterFraction: 0.5)
        XCTAssertEqual(rects[0], CGRect(x: 0, y: 0, width: 1600, height: 500))
        XCTAssertEqual(rects[1], CGRect(x: 0, y: 500, width: 800, height: 500))
        XCTAssertEqual(rects[2], CGRect(x: 800, y: 500, width: 800, height: 500))
    }

    func testTileTopPutsTheMasterAlongTheBottom() {
        let rects = TilingLayoutGeometry.rects(.tileTop, count: 2, in: bounds, gap: 0, masterFraction: 0.7)
        XCTAssertEqual(rects[0].minY, 300, accuracy: 0.001)
        XCTAssertEqual(rects[0].height, 700, accuracy: 0.001)
        XCTAssertEqual(rects[1].minY, 0)
    }

    func testTwoMastersShareTheMasterColumn() {
        let rects = TilingLayoutGeometry.rects(.tile, count: 3, in: bounds, gap: 0,
                                               masterFraction: 0.5, masterCount: 2)
        XCTAssertEqual(rects[0], CGRect(x: 0, y: 0, width: 800, height: 500))
        XCTAssertEqual(rects[1], CGRect(x: 0, y: 500, width: 800, height: 500))
        XCTAssertEqual(rects[2], CGRect(x: 800, y: 0, width: 800, height: 1000))
    }

    func testWithNoStackTheMastersShareTheWholeArea() {
        let rects = TilingLayoutGeometry.rects(.tile, count: 2, in: bounds, gap: 0, masterCount: 3)
        XCTAssertEqual(rects, [CGRect(x: 0, y: 0, width: 1600, height: 500),
                               CGRect(x: 0, y: 500, width: 1600, height: 500)])
    }

    func testFairFillsRowsAndStretchesAShortLastRow() {
        let rects = TilingLayoutGeometry.rects(.fair, count: 3, in: bounds, gap: 0)
        XCTAssertEqual(rects, [CGRect(x: 0, y: 0, width: 800, height: 500),
                               CGRect(x: 800, y: 0, width: 800, height: 500),
                               CGRect(x: 0, y: 500, width: 1600, height: 500)])
    }

    func testFairHorizontalFillsColumns() {
        let rects = TilingLayoutGeometry.rects(.fairHorizontal, count: 3, in: bounds, gap: 0)
        XCTAssertEqual(rects, [CGRect(x: 0, y: 0, width: 800, height: 500),
                               CGRect(x: 0, y: 500, width: 800, height: 500),
                               CGRect(x: 800, y: 0, width: 800, height: 1000)])
    }

    func testFairGridIsAboutSquare() {
        let rects = TilingLayoutGeometry.rects(.fair, count: 9, in: bounds, gap: 0)
        XCTAssertEqual(Set(rects.map(\.minY)).count, 3)
        XCTAssertEqual(Set(rects.map(\.minX)).count, 3)
    }

    func testColumnsAndRowsAreEqual() {
        XCTAssertEqual(TilingLayoutGeometry.rects(.columns, count: 4, in: bounds, gap: 0).map(\.width),
                       [400, 400, 400, 400])
        XCTAssertEqual(TilingLayoutGeometry.rects(.rows, count: 4, in: bounds, gap: 0).map(\.height),
                       [250, 250, 250, 250])
    }

    func testSpiralTurnsClockwise() {
        let rects = TilingLayoutGeometry.rects(.spiral, count: 4, in: bounds, gap: 0, masterFraction: 0.5)
        XCTAssertEqual(rects[0], CGRect(x: 0, y: 0, width: 800, height: 1000))     // left half
        XCTAssertEqual(rects[1], CGRect(x: 800, y: 0, width: 800, height: 500))    // top right
        XCTAssertEqual(rects[2], CGRect(x: 1200, y: 500, width: 400, height: 500)) // bottom right, right half
        XCTAssertEqual(rects[3], CGRect(x: 800, y: 500, width: 400, height: 500))  // what is left
    }

    func testCenteredMasterSitsInTheMiddleWithTheStackOnBothSides() {
        let rects = TilingLayoutGeometry.rects(.centeredMaster, count: 3, in: bounds, gap: 0, masterFraction: 0.5)
        XCTAssertEqual(rects[0], CGRect(x: 400, y: 0, width: 800, height: 1000))
        XCTAssertEqual(rects[1], CGRect(x: 1200, y: 0, width: 400, height: 1000), "first stack window on the right")
        XCTAssertEqual(rects[2], CGRect(x: 0, y: 0, width: 400, height: 1000), "second on the left")
    }

    func testCenteredMasterWithOneStackWindowIsTile() {
        XCTAssertEqual(TilingLayoutGeometry.rects(.centeredMaster, count: 2, in: bounds, gap: gap),
                       TilingLayoutGeometry.rects(.tile, count: 2, in: bounds, gap: gap))
    }

    func testCornerPutsTheMasterTopLeft() {
        let rects = TilingLayoutGeometry.rects(.corner, count: 4, in: bounds, gap: 0, masterFraction: 0.5)
        XCTAssertEqual(rects[0], CGRect(x: 0, y: 0, width: 800, height: 500))
        // two on the right, one under the master
        XCTAssertEqual(rects[1], CGRect(x: 800, y: 0, width: 800, height: 500))
        XCTAssertEqual(rects[2], CGRect(x: 800, y: 500, width: 800, height: 500))
        XCTAssertEqual(rects[3], CGRect(x: 0, y: 500, width: 800, height: 500))
    }

    func testMonocleStacksEveryWindowOnTheBounds() {
        XCTAssertEqual(TilingLayoutGeometry.rects(.monocle, count: 3, in: bounds, gap: gap),
                       [bounds, bounds, bounds])
    }

    func testMasterFractionIsClamped() {
        let wide = TilingLayoutGeometry.rects(.tile, count: 2, in: bounds, gap: 0, masterFraction: 0.99)
        XCTAssertEqual(wide[0].width, 1600 * 0.85, accuracy: 0.001)
        let narrow = TilingLayoutGeometry.rects(.tile, count: 2, in: bounds, gap: 0, masterFraction: 0.01)
        XCTAssertEqual(narrow[0].width, 1600 * 0.15, accuracy: 0.001)
    }

    func testSymbolsAreDistinctAndShort() {
        let symbols = TilingLayout.allCases.map(\.symbol)
        XCTAssertEqual(Set(symbols).count, symbols.count)
        XCTAssertTrue(symbols.allSatisfy { (1...4).contains($0.count) })
    }
}

final class LayoutCycleTests: XCTestCase {
    func testNormalizedIsCanonicalAndUnique() {
        XCTAssertEqual(LayoutCycle.normalized([.monocle, .dwindle, .monocle, .tile]), [.dwindle, .tile, .monocle])
    }

    func testAWorkspaceWithoutItsOwnListUsesTheGlobalOne() {
        XCTAssertEqual(LayoutCycle.enabled(forWorkspace: 3, global: [.fair, .tile], overrides: [:]), [.tile, .fair])
    }

    func testAnOverrideReplacesTheGlobalList() {
        let overrides = ["3": WorkspaceLayoutOverride(enabled: [.monocle, .columns])]
        XCTAssertEqual(LayoutCycle.enabled(forWorkspace: 3, global: [.dwindle], overrides: overrides),
                       [.columns, .monocle])
        XCTAssertEqual(LayoutCycle.enabled(forWorkspace: 4, global: [.dwindle], overrides: overrides), [.dwindle])
    }

    func testAnEmptyListFallsBack() {
        let overrides = ["3": WorkspaceLayoutOverride(enabled: [])]
        XCTAssertEqual(LayoutCycle.enabled(forWorkspace: 3, global: [.tile], overrides: overrides), [.tile])
        XCTAssertEqual(LayoutCycle.enabled(forWorkspace: 3, global: [], overrides: [:]), [.dwindle])
    }

    func testTheDefaultMustBeEnabled() {
        XCTAssertEqual(LayoutCycle.defaultLayout(forWorkspace: 1, global: [.tile, .fair], globalDefault: .fair,
                                                 overrides: [:]), .fair)
        XCTAssertEqual(LayoutCycle.defaultLayout(forWorkspace: 1, global: [.tile, .fair], globalDefault: .monocle,
                                                 overrides: [:]), .tile)
    }

    func testAnOverrideHasItsOwnDefault() {
        let overrides = ["2": WorkspaceLayoutOverride(enabled: [.tile, .monocle], defaultLayout: .monocle)]
        XCTAssertEqual(LayoutCycle.defaultLayout(forWorkspace: 2, global: [.dwindle], globalDefault: .dwindle,
                                                 overrides: overrides), .monocle)
        // the global default does not leak into an override that names none
        let unnamed = ["2": WorkspaceLayoutOverride(enabled: [.tile, .dwindle])]
        XCTAssertEqual(LayoutCycle.defaultLayout(forWorkspace: 2, global: [.dwindle], globalDefault: .dwindle,
                                                 overrides: unnamed), .dwindle)
    }

    func testThePickHoldsWhileItIsEnabled() {
        XCTAssertEqual(LayoutCycle.current(forWorkspace: 1, active: .fair, global: [.dwindle, .fair],
                                           globalDefault: .dwindle, overrides: [:]), .fair)
        // turned off since: back to the default
        XCTAssertEqual(LayoutCycle.current(forWorkspace: 1, active: .fair, global: [.dwindle, .tile],
                                           globalDefault: .tile, overrides: [:]), .tile)
        XCTAssertEqual(LayoutCycle.current(forWorkspace: 1, active: nil, global: [.dwindle, .tile],
                                           globalDefault: .tile, overrides: [:]), .tile)
    }

    func testStepWrapsBothWays() {
        let list: [TilingLayout] = [.dwindle, .tile, .monocle]
        XCTAssertEqual(LayoutCycle.step(from: .dwindle, by: 1, in: list), .tile)
        XCTAssertEqual(LayoutCycle.step(from: .monocle, by: 1, in: list), .dwindle)
        XCTAssertEqual(LayoutCycle.step(from: .dwindle, by: -1, in: list), .monocle)
        XCTAssertEqual(LayoutCycle.step(from: .fair, by: 1, in: list), .dwindle, "not in the list: the first")
        XCTAssertEqual(LayoutCycle.step(from: .tile, by: 1, in: []), .tile)
    }

    func testTheToggleGridKeepsOneLayoutOn() {
        XCTAssertEqual(LayoutToggleGrid.toggled(.tile, in: [.tile]), [.tile])
        XCTAssertEqual(LayoutToggleGrid.toggled(.tile, in: [.tile, .fair]), [.fair])
        XCTAssertEqual(LayoutToggleGrid.toggled(.dwindle, in: [.fair]), [.dwindle, .fair])
    }

    func testTheActivePickAndMasterSizesPersistPerMac() throws {
        let suite = "TilingLayoutTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = WorkspaceLayoutState(defaults: defaults)
        state.setActive(.monocle, forWorkspace: 4)
        state.setMasterFraction(0.7, forWorkspace: 4)
        state.setMasterFraction(2, forWorkspace: 5)

        let reloaded = WorkspaceLayoutState(defaults: defaults)
        XCTAssertEqual(reloaded.active, [4: .monocle])
        XCTAssertEqual(reloaded.masterFractions[4] ?? 0, 0.7, accuracy: 0.0001)
        XCTAssertEqual(reloaded.masterFractions[5] ?? 0, 0.85, accuracy: 0.0001, "clamped")

        reloaded.setActive(nil, forWorkspace: 4)
        reloaded.clearMasterFractions()
        let cleared = WorkspaceLayoutState(defaults: defaults)
        XCTAssertEqual(cleared.active, [:])
        XCTAssertEqual(cleared.masterFractions, [:])
    }
}

final class OrderedTreeTests: XCTestCase {
    private func orderedTree(_ layout: TilingLayout, ids: [CGWindowID]) -> BSPTree {
        let tree = BSPTree()
        for id in ids { tree.insert(makeWindow(id: id)) }
        tree.arrangement = TileArrangement(layout: layout, masterFraction: 0.5)
        tree.rebalance()
        return tree
    }

    func testAnOrderDrivenLayoutFollowsTheWindowOrder() {
        let tree = orderedTree(.columns, ids: [1, 2, 3])
        let layout = tree.layout(in: defaultRect, gap: 0, padding: 0)
        XCTAssertEqual(layout.map(\.0.windowID), [1, 2, 3])
        XCTAssertEqual(layout.map(\.1), TilingLayoutGeometry.rects(.columns, count: 3, in: defaultRect, gap: 0))
    }

    func testRebalanceKeepsTheOrderAndTheDepthBudget() {
        let tree = BSPTree()
        // a dwindle chain, deeper than a balanced tree needs
        for id: CGWindowID in 1...8 { tree.insert(makeWindow(id: id)) }
        tree.rebalance()
        XCTAssertEqual(tree.allWindows.map(\.windowID), Array(1...8))
        XCTAssertEqual(tree.root.allLeavesRightToLeft().map(\.depth).max(), 3)
        XCTAssertEqual(BSPTree.balancedDepth(forCount: 8), 3)
        XCTAssertEqual(BSPTree.balancedDepth(forCount: 9), 4)
        XCTAssertEqual(BSPTree.balancedDepth(forCount: 1), 0)
    }

    func testAppendGoesLast() {
        let tree = orderedTree(.tile, ids: [1, 2])
        tree.appendBalanced(makeWindow(id: 3))
        XCTAssertEqual(tree.allWindows.map(\.windowID), [1, 2, 3])
    }

    func testRectForNodeIsTheWindowsSlot() {
        let tree = orderedTree(.tile, ids: [1, 2, 3])
        let leaves = Array(tree.root.allLeavesRightToLeft().reversed())
        let slots = TilingLayoutGeometry.rects(.tile, count: 3, in: defaultRect, gap: 0, masterFraction: 0.5)
        for (leaf, slot) in zip(leaves, slots) {
            XCTAssertEqual(tree.rectForNode(leaf, in: defaultRect, gap: 0, padding: 0), slot)
        }
        XCTAssertEqual(tree.rectForNode(tree.root, in: defaultRect, gap: 0, padding: 0), defaultRect)
    }

    func testSwapTradesPlacesInTheOrder() {
        let tree = orderedTree(.tile, ids: [1, 2, 3])
        let windows = tree.allWindows
        tree.swap(windows[0], windows[2])
        XCTAssertEqual(tree.allWindows.map(\.windowID), [3, 2, 1])
    }

    func testADropReordersAndStaysBalanced() throws {
        let tree = orderedTree(.columns, ids: [1, 2, 3, 4])
        let before = try XCTUnwrap(tree.candidateTree(draggedID: 4, targetID: 1, edge: .left, maxDepth: 2))
        XCTAssertEqual(before.allWindows.map(\.windowID), [4, 1, 2, 3])
        XCTAssertEqual(before.arrangement.layout, .columns)
        let after = try XCTUnwrap(tree.candidateTree(draggedID: 1, targetID: 3, edge: .right, maxDepth: 2))
        XCTAssertEqual(after.allWindows.map(\.windowID), [2, 3, 1, 4])
        XCTAssertNotNil(tree.candidateTree(inserting: makeWindow(id: 9), beside: 2, edge: .bottom, maxDepth: 3))
        XCTAssertNil(tree.candidateTree(inserting: makeWindow(id: 9), beside: 2, edge: .bottom, maxDepth: 2),
                     "five windows need depth 3")
    }

    func testRatioWorkIsANoOpOffDwindle() {
        let tree = orderedTree(.tile, ids: [1, 2])
        let before = tree.structuralFingerprint()
        let window = tree.allWindows[0]
        tree.adjustForMinSizes([(window: window, actual: CGSize(width: 1500, height: 900))],
                               in: defaultRect, gap: 8, padding: 8, givingWayOnUserSet: true)
        tree.applyResizeDelta(for: window, newFrame: CGRect(x: 0, y: 0, width: 1200, height: 1000),
                              in: defaultRect, gap: 8, padding: 8)
        tree.toggleSplit(for: window, in: defaultRect, gap: 8, padding: 8)
        XCTAssertEqual(tree.structuralFingerprint(), before)
    }

    func testCloneAndAdoptCarryTheArrangement() {
        let tree = orderedTree(.fair, ids: [1, 2])
        XCTAssertEqual(tree.deepClone().arrangement, tree.arrangement)
        let other = BSPTree()
        other.adopt(tree)
        XCTAssertEqual(other.arrangement.layout, .fair)
    }
}

final class OrderedFitTests: XCTestCase {
    private let engine = LayoutEngine(gapSize: 8, outerPadding: 8, minSlotDimension: 500)

    private func tree(_ layout: TilingLayout, count: Int) -> BSPTree {
        let tree = BSPTree()
        tree.arrangement = TileArrangement(layout: layout)
        for id in 0..<count { tree.appendBalanced(makeWindow(id: CGWindowID(100 + id))) }
        return tree
    }

    func testANewWindowJoinsTheEndOfTheOrder() {
        let t = tree(.tile, count: 2)
        XCTAssertTrue(engine.smartInsertFitting(makeWindow(id: 7), into: t, maxDepth: 3, rect: defaultRect,
                                                minimumSize: { _ in .zero }))
        XCTAssertEqual(t.allWindows.map(\.windowID), [100, 101, 7])
    }

    func testTheSplitBudgetCapsTheCount() {
        let t = tree(.fair, count: 8)
        var refusals: [LayoutEngine.SlotRefusal] = []
        XCTAssertNil(engine.fittingLeaf(for: makeWindow(id: 9), in: t, maxDepth: 3, rect: defaultRect,
                                        minimumSize: { _ in .zero }, noting: { refusals.append($0) }))
        XCTAssertEqual(refusals.first?.depthExhausted, true)
        XCTAssertFalse(engine.smartInsertFitting(makeWindow(id: 9), into: t, maxDepth: 3, rect: defaultRect,
                                                 minimumSize: { _ in .zero }))
        XCTAssertEqual(t.allWindows.count, 8)
    }

    func testAKnownMinimumThatWouldNotFitRefuses() {
        let t = tree(.columns, count: 2)
        let wide = makeWindow(id: 9)
        // a third column on 1904 px is about 630 wide
        XCTAssertFalse(engine.smartInsertFitting(wide, into: t, maxDepth: 3, rect: defaultRect,
                                                 minimumSize: { $0?.windowID == 9 ? CGSize(width: 900, height: 100) : .zero }))
        XCTAssertTrue(engine.smartInsertFitting(wide, into: t, maxDepth: 3, rect: defaultRect,
                                                minimumSize: { $0?.windowID == 9 ? CGSize(width: 600, height: 100) : .zero }))
    }

    func testAnIncumbentsMinimumCountsToo() {
        let t = tree(.columns, count: 2)
        XCTAssertFalse(engine.smartInsertFitting(makeWindow(id: 9), into: t, maxDepth: 3, rect: defaultRect,
                                                 minimumSize: { $0?.windowID == 100 ? CGSize(width: 900, height: 100) : .zero }))
    }

    func testMonocleFitsAnythingThatFitsTheScreen() {
        let t = tree(.monocle, count: 3)
        XCTAssertTrue(engine.smartInsertFitting(makeWindow(id: 9), into: t, maxDepth: 3, rect: defaultRect,
                                                minimumSize: { _ in CGSize(width: 1800, height: 1000) }))
    }
}

final class MasterStepTests: XCTestCase {
    private func step(_ layout: TilingLayout, _ direction: Direction, from fraction: CGFloat = 0.5) -> CGFloat? {
        TilingEngine.steppedMasterFraction(TileArrangement(layout: layout, masterFraction: fraction),
                                           direction: direction)
    }

    func testTheBoundaryFollowsTheArrow() {
        XCTAssertEqual(step(.tile, .right) ?? 0, 0.55, accuracy: 0.0001)
        XCTAssertEqual(step(.tile, .left) ?? 0, 0.45, accuracy: 0.0001)
        XCTAssertEqual(step(.tileLeft, .right) ?? 0, 0.45, accuracy: 0.0001, "a right master shrinks")
        XCTAssertEqual(step(.tileBottom, .down) ?? 0, 0.55, accuracy: 0.0001)
        XCTAssertEqual(step(.tileTop, .down) ?? 0, 0.45, accuracy: 0.0001, "a bottom master shrinks")
    }

    func testAnArrowAlongTheMasterDoesNothing() {
        XCTAssertNil(step(.tile, .up))
        XCTAssertNil(step(.tileBottom, .left))
        XCTAssertNil(step(.fair, .right))
        XCTAssertNil(step(.monocle, .right))
    }

    func testTheBoundsStop() {
        XCTAssertNil(step(.tile, .right, from: 0.85))
        XCTAssertNil(step(.tile, .left, from: 0.15))
    }
}

final class OverlappingTargetTests: XCTestCase {
    func testOnlyOneSharedFrameIsAStack() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertTrue(FrameSizingAttempt.targetsShareAFrame(a, a, slack: 2))
        XCTAssertTrue(FrameSizingAttempt.targetsShareAFrame(a, a.offsetBy(dx: 1, dy: 1), slack: 2))
        XCTAssertFalse(FrameSizingAttempt.targetsShareAFrame(a, CGRect(x: 50, y: 0, width: 100, height: 100), slack: 2),
                       "a partial overlap is still a broken layout")
        XCTAssertFalse(FrameSizingAttempt.targetsShareAFrame(a, CGRect(x: 0, y: 0, width: 100, height: 60), slack: 2))
    }

    // monocle's windows land on one frame and verify; two that overlap
    // without sharing it are still refused
    func testTheValidatorAcceptsAStackButNotAPile() {
        let attempt = FrameSizingAttempt(io: FrameSizingIO.accessibility(windows: [:], currentGeneration: { 0 }))
        let full = CGRect(x: 0, y: 0, width: 600, height: 400)
        let stacked = [FrameSizingAttempt.Target(windowID: 1, frame: full),
                       FrameSizingAttempt.Target(windowID: 2, frame: full)]
        XCTAssertEqual(attempt.validateFrames(targets: stacked, actualFrames: [1: full, 2: full],
                                              usableFrame: full, gap: 8).verdict, .accepted)
        let piled = [FrameSizingAttempt.Target(windowID: 1, frame: full),
                     FrameSizingAttempt.Target(windowID: 2, frame: CGRect(x: 200, y: 0, width: 400, height: 400))]
        XCTAssertEqual(attempt.validateFrames(targets: piled,
                                              actualFrames: [1: full, 2: piled[1].frame],
                                              usableFrame: full, gap: 8).verdict, .rejected(.overlap(1, 2)))
    }
}

final class LayoutConfigTests: XCTestCase {
    func testAConfigWithoutLayoutKeysUsesTheShippedDefaults() throws {
        let json = #"{"keybinds":[],"gapSize":8,"outerPadding":8,"enabled":true}"#
        let saved = try JSONDecoder().decode(SavedConfig.self, from: Data(json.utf8))
        XCTAssertNil(saved.enabledLayouts)
        XCTAssertNil(saved.workspaceLayouts)
        XCTAssertEqual(UserConfig.resolveEnabledLayouts(saved.enabledLayouts), TilingLayout.defaultEnabled)
    }

    func testUnknownLayoutsADifferentBuildWroteAreDropped() throws {
        let json = """
        {"keybinds":[],"gapSize":8,"outerPadding":8,"enabled":true,
         "enabledLayouts":["tile","hexagons","monocle"],
         "defaultLayout":"hexagons",
         "workspaceLayouts":{"2":{"enabled":["fair","hexagons"],"defaultLayout":"fair"},
                             "3":{"enabled":["hexagons"]},
                             "11":{"enabled":["tile"]}},
         "layoutMasterFraction":0.6,"layoutMasterCount":2,"showLayoutInMenuBar":false}
        """
        let saved = try JSONDecoder().decode(SavedConfig.self, from: Data(json.utf8))
        XCTAssertEqual(saved.enabledLayouts, [.tile, .monocle])
        XCTAssertNil(saved.defaultLayout)
        XCTAssertEqual(saved.workspaceLayouts, ["2": WorkspaceLayoutOverride(enabled: [.fair], defaultLayout: .fair)])
        XCTAssertEqual(saved.layoutMasterFraction, 0.6)
        XCTAssertEqual(saved.layoutMasterCount, 2)
        XCTAssertEqual(saved.showLayoutInMenuBar, false)
    }

    func testAnUnreadableLayoutValueCostsOnlyThatKey() throws {
        let json = """
        {"keybinds":[],"gapSize":8,"outerPadding":8,"enabled":true,
         "enabledLayouts":"tile","workspaceNames":{"1":"web"}}
        """
        let saved = try JSONDecoder().decode(SavedConfig.self, from: Data(json.utf8))
        XCTAssertNil(saved.enabledLayouts)
        XCTAssertEqual(saved.workspaceNames, ["1": "web"])
    }

    func testLayoutKeysRoundTrip() throws {
        var saved = SavedConfig.empty
        saved.enabledLayouts = [.dwindle, .centeredMaster]
        saved.defaultLayout = .centeredMaster
        saved.workspaceLayouts = ["5": WorkspaceLayoutOverride(enabled: [.monocle], defaultLayout: nil)]
        let reloaded = try JSONDecoder().decode(SavedConfig.self, from: try JSONEncoder().encode(saved))
        XCTAssertEqual(reloaded.enabledLayouts, [.dwindle, .centeredMaster])
        XCTAssertEqual(reloaded.defaultLayout, .centeredMaster)
        XCTAssertEqual(reloaded.workspaceLayouts?["5"]?.enabled, [.monocle])
    }

    func testCycleLayoutRoundTripsAndAnOlderBuildDropsOnlyThatBind() throws {
        let bind = Keybind(keyCode: 49, modifiers: .hypr, action: .cycleLayout(1))
        let encoded = String(data: try JSONEncoder().encode(bind), encoding: .utf8)!
        XCTAssertTrue(encoded.contains(#""cycleLayout":{"_0":1}"#), encoded)
        let json = """
        {"keybinds":[\(encoded),
            {"action":{"futureLayoutKey":{}},"keyCode":1,"modifiers":1}],
         "gapSize":8,"outerPadding":8,"enabled":true}
        """
        let saved = try JSONDecoder().decode(SavedConfig.self, from: Data(json.utf8))
        XCTAssertEqual(saved.keybinds.map(\.action), [.cycleLayout(1)])
    }

    func testTheCycleKeysShipOnHyprSpace() {
        XCTAssertTrue(Keybind.defaults.contains { $0.action == .cycleLayout(1) && $0.keyCode == 49 && $0.modifiers == .hypr })
        XCTAssertTrue(Keybind.defaults.contains {
            $0.action == .cycleLayout(-1) && $0.keyCode == 49 && $0.modifiers == [.hypr, .shift]
        })
        // a config from before layouts gets them, chords free
        let merged = UserConfig.mergeNewDefaults(saved: [Keybind(keyCode: 15, modifiers: .hypr, action: .retileAll)])
        XCTAssertTrue(merged.contains { $0.action == .cycleLayout(1) })
    }

    func testTheCycleKeyIgnoresAutorepeat() {
        XCTAssertTrue(HotkeyManager.ignoresAutorepeat(.cycleLayout(1)))
        XCTAssertTrue(ActionPolicy.isDroppedMidDisplayTransition(.cycleLayout(1)))
        XCTAssertFalse(ActionPolicy.cancelsPendingRecovery(.cycleLayout(1)))
    }
}

final class LayoutEngineRelayoutTests: XCTestCase {
    private var layouts: [Int: TileArrangement] = [:]

    private func makeEngine(_ screen: NSScreen) -> TilingEngine {
        let engine = TilingEngine(displayManager: DisplayManager(screenSource: { [screen] }),
                                  frameSizingIOFactory: acceptingFrameSizingIOFactory())
        engine.arrangementSource = { [unowned self] in self.layouts[$0] ?? .dwindle }
        return engine
    }

    private func ids(_ engine: TilingEngine, _ screen: NSScreen) -> [CGWindowID] {
        engine.windowIDs(inTreeForWorkspace: 1, screen: screen)
    }

    func testAWorkspaceTilesInItsLayout() throws {
        let screen = LayoutTestScreen()
        let engine = makeEngine(screen)
        layouts[1] = TileArrangement(layout: .tile, masterFraction: 0.5)
        let windows = (1...3).map { makeWindow(id: CGWindowID(8100 + $0)) }
        XCTAssertTrue(engine.tileWindows(windows, onWorkspace: 1, screen: screen).published)

        let rects = engine.intendedTileRects()
        let master = try XCTUnwrap(rects[8101])
        let first = try XCTUnwrap(rects[8102]), second = try XCTUnwrap(rects[8103])
        XCTAssertEqual(master.minY, first.minY, "master starts at the top")
        XCTAssertEqual(master.maxY, second.maxY, accuracy: 0.5, "and runs the full height")
        XCTAssertEqual(first.minX, second.minX, "the stack shares one column")
        XCTAssertLessThan(master.maxX, first.minX)
        XCTAssertEqual(engine.liveArrangement(forWorkspace: 1, screen: screen)?.layout, .tile)
    }

    func testRelayoutAppliesANewLayoutAndMonocleVerifies() {
        let screen = LayoutTestScreen()
        let engine = makeEngine(screen)
        let windows = (1...3).map { makeWindow(id: CGWindowID(8200 + $0)) }
        XCTAssertTrue(engine.tileWindows(windows, onWorkspace: 1, screen: screen).published)

        layouts[1] = TileArrangement(layout: .monocle)
        XCTAssertTrue(engine.relayout(workspace: 1, screen: screen))
        let rects = windows.compactMap { engine.intendedTileRects()[$0.windowID] }
        XCTAssertEqual(rects.count, 3)
        XCTAssertTrue(rects.allSatisfy { $0 == rects.first }, "one shared frame: \(rects)")
        XCTAssertEqual(engine.liveArrangement(forWorkspace: 1, screen: screen)?.layout, .monocle)
        XCTAssertEqual(ids(engine, screen).count, 3)

        layouts[1] = TileArrangement(layout: .columns)
        XCTAssertTrue(engine.relayout(workspace: 1, screen: screen))
        XCTAssertEqual(Set(windows.compactMap { engine.intendedTileRects()[$0.windowID]?.minX }).count, 3)
    }

    func testAnOrderDrivenWorkspaceHoldsUpToTheSplitBudget() {
        let screen = LayoutTestScreen()
        let engine = makeEngine(screen)
        engine.maxSplitsPerMonitor = [screen.localizedName: 2]
        layouts[1] = TileArrangement(layout: .fair)
        let windows = (1...5).map { makeWindow(id: CGWindowID(8300 + $0)) }
        engine.tileWindows(windows, onWorkspace: 1, screen: screen)
        XCTAssertEqual(ids(engine, screen).count, 4, "2 splits hold 4 windows, as in dwindle")
    }

    func testTheScratchpadLayerStaysDwindle() {
        let screen = LayoutTestScreen()
        let engine = makeEngine(screen)
        layouts[TilingEngine.scratchpadWorkspace] = TileArrangement(layout: .monocle)
        let windows = (1...2).map { makeWindow(id: CGWindowID(8400 + $0)) }
        XCTAssertTrue(engine.tileWindows(windows, onWorkspace: TilingEngine.scratchpadWorkspace, screen: screen).published)
        XCTAssertEqual(engine.liveArrangement(forWorkspace: TilingEngine.scratchpadWorkspace, screen: screen)?.layout,
                       .dwindle)
    }
}

private final class LayoutTestScreen: SyntheticScreen {
    override var frame: NSRect { NSRect(x: 0, y: 0, width: 1600, height: 1000) }
    override var visibleFrame: NSRect { frame }
    override var localizedName: String { "layout-test" }
}

final class MenuBarLayoutIconTests: XCTestCase {
    func testEveryLayoutHasATemplateIconOfOneSize() {
        for layout in TilingLayout.allCases {
            let icon = MenuBarPresentation.layoutIcon(layout)
            XCTAssertTrue(icon.isTemplate, "\(layout)")
            XCTAssertEqual(icon.size, NSSize(width: 21, height: 14), "\(layout)")
        }
    }

    // the label is one image: glyphs, icon and tray side by side, one height
    func testTheLabelImageHoldsEveryPartInOneRow() {
        let icon = MenuBarPresentation.layoutIcon(.tile)
        let alone = MenuBarPresentation.labelImage([.image(icon)])
        let withGlyphs = MenuBarPresentation.labelImage(leading: [.text("■ □ ·", size: 12)], layout: .tile)
        let withTray = MenuBarPresentation.labelImage(leading: [.text("■ □ ·", size: 12)], layout: .tile,
                                                      trailing: [.symbol("tray"), .text("2", size: 11)])
        XCTAssertEqual(alone.size.width, icon.size.width)
        XCTAssertGreaterThan(withGlyphs.size.width, alone.size.width)
        XCTAssertGreaterThan(withTray.size.width, withGlyphs.size.width)
        for image in [alone, withGlyphs, withTray] {
            XCTAssertEqual(image.size.height, MenuBarPresentation.labelHeight)
            XCTAssertTrue(image.isTemplate)
        }
    }
}

final class WorkspaceFocusMemoryTests: XCTestCase {
    func testEachWorkspaceRemembersItsLastFocusWhileItShows() {
        let screen = FocusMemoryScreen()
        let workspaces = WorkspaceManager(displayManager: DisplayManager(screenSource: { [screen] }))
        workspaces.initializeMonitors()
        workspaces.assignWindow(1, toWorkspace: 1)
        workspaces.assignWindow(2, toWorkspace: 1)
        workspaces.assignWindow(3, toWorkspace: 2)

        workspaces.noteFocused(2)
        XCTAssertEqual(workspaces.rememberedFocus(on: 1), 2)
        // a focus event from a window on a hidden workspace changes nothing
        workspaces.noteFocused(3)
        XCTAssertNil(workspaces.rememberedFocus(on: 2))

        _ = workspaces.switchWorkspace(2, cursorScreen: screen)
        workspaces.noteFocused(3)
        XCTAssertEqual(workspaces.rememberedFocus(on: 2), 3)
        XCTAssertEqual(workspaces.rememberedFocus(on: 1), 2, "the workspace left keeps its memory")
    }

    func testAWindowThatMovedOrClosedIsForgotten() {
        let screen = FocusMemoryScreen()
        let workspaces = WorkspaceManager(displayManager: DisplayManager(screenSource: { [screen] }))
        workspaces.initializeMonitors()
        workspaces.assignWindow(1, toWorkspace: 1)
        workspaces.noteFocused(1)
        workspaces.moveWindow(1, toWorkspace: 4)
        XCTAssertNil(workspaces.rememberedFocus(on: 1))

        workspaces.assignWindow(5, toWorkspace: 1)
        workspaces.noteFocused(5)
        workspaces.removeWindow(5)
        XCTAssertNil(workspaces.rememberedFocus(on: 1))
        workspaces.noteFocused(0)
        XCTAssertNil(workspaces.rememberedFocus(on: 1))
    }

    func testTheMonocleCycleRunsThroughTilesThenFloaters() {
        XCTAssertEqual(ActionDispatcher.monocleOrder(tiles: [30, 10, 20], floaters: [5, 40]), [30, 10, 20, 5, 40])
        XCTAssertEqual(ActionDispatcher.monocleOrder(tiles: [1, 2], floaters: [2, 3]), [1, 2, 3], "each once")
        XCTAssertEqual(ActionDispatcher.monocleOrder(tiles: [], floaters: [7]), [7])
    }
}

private final class FocusMemoryScreen: SyntheticScreen {
    override var frame: NSRect { NSRect(x: 0, y: 0, width: 1600, height: 1000) }
    override var visibleFrame: NSRect { frame }
}

import Testing
import SwiftUI
@testable import booklist

// MARK: - MasonryLayout.itemWidth

struct MasonryItemWidthTests {

    @Test("Three columns with 12pt spacing")
    func threeColumnWidth() {
        let layout = MasonryLayout(columns: 3, spacing: 12)
        let expected: CGFloat = (300 - 12 * 2) / 3
        #expect(layout.itemWidth(in: 300) == expected)
    }

    @Test("Single column fills full width")
    func singleColumnWidth() {
        let layout = MasonryLayout(columns: 1, spacing: 12)
        #expect(layout.itemWidth(in: 400) == 400)
    }

    @Test("Five columns with spacing")
    func fiveColumnWidth() {
        let layout = MasonryLayout(columns: 5, spacing: 12)
        let expected: CGFloat = (500 - 12 * 4) / 5
        #expect(layout.itemWidth(in: 500) == expected)
    }

    @Test("Zero total width returns non-positive value safely")
    func zeroTotalWidth() {
        let layout = MasonryLayout(columns: 3, spacing: 12)
        #expect(layout.itemWidth(in: 0) <= 0)
    }

    @Test("Item width is always positive across common screen widths")
    func positiveWidthOnRealScreens() {
        let screenWidths: [CGFloat] = [800, 1024, 1280, 1440, 1920, 2560, 3840]
        for width in screenWidths {
            for cols in 1...5 {
                let w = MasonryLayout(columns: cols, spacing: 12).itemWidth(in: width)
                #expect(w > 0, "Expected positive width for \(cols) columns at \(width)pt")
            }
        }
    }

    @Test("Two-column cards are wider than four-column cards at the same total width")
    func columnWidthRatio() {
        let total: CGFloat = 1200
        let two  = MasonryLayout(columns: 2, spacing: 12).itemWidth(in: total)
        let four = MasonryLayout(columns: 4, spacing: 12).itemWidth(in: total)
        #expect(two > four)
    }
}

// MARK: - MasonryLayout.shortestColumn

struct MasonryShortestColumnTests {

    @Test("All equal heights — returns index 0")
    func allEqual() {
        let layout = MasonryLayout(columns: 3, spacing: 12)
        #expect(layout.shortestColumn(in: [100, 100, 100]) == 0)
    }

    @Test("Middle column is shortest")
    func middleShortest() {
        let layout = MasonryLayout(columns: 3, spacing: 12)
        #expect(layout.shortestColumn(in: [200, 50, 150]) == 1)
    }

    @Test("Last column is shortest")
    func lastShortest() {
        let layout = MasonryLayout(columns: 3, spacing: 12)
        #expect(layout.shortestColumn(in: [300, 250, 10]) == 2)
    }

    @Test("Single column always returns 0")
    func singleColumn() {
        let layout = MasonryLayout(columns: 1, spacing: 12)
        #expect(layout.shortestColumn(in: [999]) == 0)
    }

    @Test("Five columns — correctly identifies minimum")
    func fiveColumns() {
        let heights: [CGFloat] = [500, 200, 800, 100, 600]
        let layout = MasonryLayout(columns: 5, spacing: 12)
        #expect(layout.shortestColumn(in: heights) == 3)
    }

    @Test("Stress: 1000 random height arrays all find the true minimum")
    func stressFindsMinimum() {
        let layout = MasonryLayout(columns: 5, spacing: 12)
        for _ in 0..<1_000 {
            let heights: [CGFloat] = (0..<5).map { _ in CGFloat.random(in: 0...2_000) }
            let expected = heights.indices.min(by: { heights[$0] < heights[$1] })!
            #expect(layout.shortestColumn(in: heights) == expected)
        }
    }
}

// MARK: - MasonryLayout.columnCount

struct MasonryColumnCountTests {

    @Test("Scale below 0.80 → 5 columns")
    func fiveColumns() {
        #expect(MasonryLayout.columnCount(for: 0.60) == 5)
        #expect(MasonryLayout.columnCount(for: 0.79) == 5)
    }

    @Test("Boundary 0.80 → 4 columns")
    func boundaryAtEighty() {
        #expect(MasonryLayout.columnCount(for: 0.80) == 4)
    }

    @Test("0.80 ≤ scale < 0.95 → 4 columns")
    func fourColumns() {
        #expect(MasonryLayout.columnCount(for: 0.87) == 4)
        #expect(MasonryLayout.columnCount(for: 0.94) == 4)
    }

    @Test("Boundary 0.95 → 3 columns")
    func boundaryAtNinetyFive() {
        #expect(MasonryLayout.columnCount(for: 0.95) == 3)
    }

    @Test("Default scale 1.0 → 3 columns")
    func defaultScale() {
        #expect(MasonryLayout.columnCount(for: 1.0) == 3)
    }

    @Test("0.95 ≤ scale < 1.15 → 3 columns")
    func threeColumns() {
        #expect(MasonryLayout.columnCount(for: 1.10) == 3)
        #expect(MasonryLayout.columnCount(for: 1.14) == 3)
    }

    @Test("Boundary 1.15 → 2 columns")
    func boundaryAtOnePointFifteen() {
        #expect(MasonryLayout.columnCount(for: 1.15) == 2)
    }

    @Test("1.15 ≤ scale < 1.35 → 2 columns")
    func twoColumns() {
        #expect(MasonryLayout.columnCount(for: 1.25) == 2)
        #expect(MasonryLayout.columnCount(for: 1.34) == 2)
    }

    @Test("Boundary 1.35 → 1 column")
    func boundaryAtOnePointThirtyFive() {
        #expect(MasonryLayout.columnCount(for: 1.35) == 1)
    }

    @Test("Maximum slider value 1.60 → 1 column")
    func maxSlider() {
        #expect(MasonryLayout.columnCount(for: 1.60) == 1)
    }

    @Test("Column count is always 1–5 for any slider value in the allowed range")
    func alwaysValidRange() {
        for scale in stride(from: 0.6, through: 1.6, by: 0.01) {
            let count = MasonryLayout.columnCount(for: scale)
            #expect(count >= 1 && count <= 5, "Unexpected column count \(count) for scale \(scale)")
        }
    }
}

// MARK: - Layout simulation (stress)

struct MasonryLayoutSimulationTests {

    private func simulate(items: Int, columns: Int, spacing: CGFloat = 12) -> [CGFloat] {
        let layout = MasonryLayout(columns: columns, spacing: spacing)
        var colHeights = [CGFloat](repeating: 0, count: columns)
        for _ in 0..<items {
            let col = layout.shortestColumn(in: colHeights)
            colHeights[col] += CGFloat.random(in: 60...500) + spacing
        }
        return colHeights
    }

    @Test("Zero items — all column heights remain zero")
    func zeroItems() {
        for cols in 1...5 {
            let heights = simulate(items: 0, columns: cols)
            #expect(heights.allSatisfy { $0 == 0 })
        }
    }

    @Test("Single item — exactly one column becomes non-zero")
    func singleItem() {
        for cols in 1...5 {
            let heights = simulate(items: 1, columns: cols)
            #expect(heights.filter { $0 > 0 }.count == 1)
        }
    }

    @Test("Column heights never go negative")
    func neverNegative() {
        for cols in 1...5 {
            let heights = simulate(items: 500, columns: cols)
            #expect(heights.allSatisfy { $0 >= 0 })
        }
    }

    @Test("All columns receive items when item count ≥ column count")
    func allColumnsReceiveItems() {
        for cols in 1...5 {
            let heights = simulate(items: cols * 10, columns: cols)
            #expect(heights.allSatisfy { $0 > 0 }, "A column stayed empty for \(cols)-column layout")
        }
    }

    @Test("Stress: 1000 items across 3 columns — heights stay roughly balanced")
    func stressBalanced() {
        let heights = simulate(items: 1_000, columns: 3)
        let maxH = heights.max()!
        let minH = heights.min()!
        // Greedy shortest-column should keep all columns within 10 % of each other
        #expect((maxH - minH) / maxH < 0.10, "Columns diverged: \(heights)")
    }

    @Test("Stress: 5000 items across 5 columns — no crash, all heights positive")
    func stressLarge() {
        let heights = simulate(items: 5_000, columns: 5)
        #expect(heights.allSatisfy { $0 > 0 })
    }

    @Test("Stress: all column counts with 200 items — correct number of column buckets")
    func stressAllColumnCounts() {
        for cols in 1...5 {
            let heights = simulate(items: 200, columns: cols)
            #expect(heights.count == cols)
            #expect(heights.allSatisfy { $0 > 0 })
        }
    }
}

// MARK: - MasonryNavigation

/// Two columns with uneven heights:
///
///     ┌───┐ ┌───┐
///     │ A │ │ B │
///     │   │ └───┘
///     └───┘ ┌───┐
///     ┌───┐ │ D │
///     │ C │ │   │
///     └───┘ │   │
///           └───┘
struct MasonryNavigationTests {
    let a = UUID(), b = UUID(), c = UUID(), d = UUID()

    var frames: [UUID: CGRect] {
        [
            a: CGRect(x: 0,   y: 0,   width: 100, height: 200),
            c: CGRect(x: 0,   y: 212, width: 100, height: 100),
            b: CGRect(x: 112, y: 0,   width: 100, height: 100),
            d: CGRect(x: 112, y: 112, width: 100, height: 300),
        ]
    }

    @Test("Down moves to the next card in the same column")
    func down() {
        #expect(MasonryNavigation.neighbor(of: a, direction: .down, frames: frames) == c)
        #expect(MasonryNavigation.neighbor(of: b, direction: .down, frames: frames) == d)
    }

    @Test("Up moves to the previous card in the same column")
    func up() {
        #expect(MasonryNavigation.neighbor(of: c, direction: .up, frames: frames) == a)
    }

    @Test("Moving past the edge returns nil")
    func edges() {
        #expect(MasonryNavigation.neighbor(of: c, direction: .down, frames: frames) == nil)
        #expect(MasonryNavigation.neighbor(of: a, direction: .up, frames: frames) == nil)
        #expect(MasonryNavigation.neighbor(of: a, direction: .left, frames: frames) == nil)
        #expect(MasonryNavigation.neighbor(of: b, direction: .right, frames: frames) == nil)
    }

    @Test("Right picks the card in the next column closest vertically")
    func right() {
        // A's centre (y 100) is nearer B (50) than D (262)
        #expect(MasonryNavigation.neighbor(of: a, direction: .right, frames: frames) == b)
        // C's centre (y 262) lines up with D
        #expect(MasonryNavigation.neighbor(of: c, direction: .right, frames: frames) == d)
    }

    @Test("Left picks the card in the previous column closest vertically")
    func left() {
        #expect(MasonryNavigation.neighbor(of: d, direction: .left, frames: frames) == c)
        #expect(MasonryNavigation.neighbor(of: b, direction: .left, frames: frames) == a)
    }

    @Test("Unknown card returns nil")
    func unknownID() {
        #expect(MasonryNavigation.neighbor(of: UUID(), direction: .down, frames: frames) == nil)
    }
}

// MARK: - CardSize presets

struct CardSizeTests {

    @Test("Presets map to 5, 3, 2 and 1 columns")
    func presetColumns() {
        let columns = CardSize.allCases.map { MasonryLayout.columnCount(for: $0.scale) }
        #expect(columns == [5, 3, 2, 1])
    }

    @Test("matching finds the preset for its own scale and nil between presets")
    func matching() {
        #expect(CardSize.matching(1.0) == .medium)
        #expect(CardSize.matching(1.5) == .extraLarge)
        #expect(CardSize.matching(0.9) == nil)   // slider value between Small and Medium
    }

    @Test("Stepping moves to the neighbouring preset")
    func stepBetweenPresets() {
        #expect(CardSize.step(from: 1.0, larger: true) == 1.2)
        #expect(CardSize.step(from: 1.0, larger: false) == 0.7)
    }

    @Test("Stepping from an in-between slider value lands on the next preset")
    func stepFromSliderValue() {
        #expect(CardSize.step(from: 0.9, larger: true) == 1.0)
        #expect(CardSize.step(from: 0.9, larger: false) == 0.7)
    }

    @Test("Stepping past either end returns nil")
    func stepAtEnds() {
        #expect(CardSize.step(from: 1.5, larger: true) == nil)
        #expect(CardSize.step(from: 0.7, larger: false) == nil)
        #expect(CardSize.step(from: 1.6, larger: true) == nil)  // slider max
        #expect(CardSize.step(from: 0.6, larger: false) == nil) // slider min
    }
}

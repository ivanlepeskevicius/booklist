import Testing
import SwiftUI
@testable import booklist

@Suite("Color+Hex")
struct ColorHexTests {

    // MARK: - init(hex:) — 6-char

    @Test("6-char hex with hash prefix parses correctly")
    func sixCharWithHash() {
        #expect(Color(hex: "#FF6B6B").toHex() == "#FF6B6B")
    }

    @Test("6-char hex without hash prefix parses correctly")
    func sixCharNoHash() {
        #expect(Color(hex: "FF6B6B").toHex() == "#FF6B6B")
    }

    @Test("Lowercase 6-char hex normalises to uppercase output")
    func sixCharLowercase() {
        #expect(Color(hex: "#ff6b6b").toHex() == "#FF6B6B")
    }

    @Test("Black #000000 round-trips")
    func black() {
        #expect(Color(hex: "#000000").toHex() == "#000000")
    }

    @Test("White #FFFFFF round-trips")
    func white() {
        #expect(Color(hex: "#FFFFFF").toHex() == "#FFFFFF")
    }

    // MARK: - init(hex:) — 3-char shorthand

    @Test("3-char #F00 expands to #FF0000")
    func threeCharRed() {
        #expect(Color(hex: "#F00").toHex() == "#FF0000")
    }

    @Test("3-char #ABC expands to #AABBCC")
    func threeCharABC() {
        #expect(Color(hex: "#ABC").toHex() == "#AABBCC")
    }

    @Test("3-char #FFF expands to #FFFFFF")
    func threeCharWhite() {
        #expect(Color(hex: "#FFF").toHex() == "#FFFFFF")
    }

    @Test("3-char #000 expands to #000000")
    func threeCharBlack() {
        #expect(Color(hex: "#000").toHex() == "#000000")
    }

    // MARK: - init(hex:) — 8-char AARRGGBB

    @Test("8-char AARRGGBB uses RGB, toHex ignores alpha")
    func eightCharOpaque() {
        // #FFFF6B6B: alpha=FF r=FF g=6B b=6B
        #expect(Color(hex: "#FFFF6B6B").toHex() == "#FF6B6B")
    }

    @Test("8-char semi-transparent yields same RGB in toHex")
    func eightCharTransparent() {
        // #80FF6B6B: alpha=80 r=FF g=6B b=6B — toHex still returns RGB only
        #expect(Color(hex: "#80FF6B6B").toHex() == "#FF6B6B")
    }

    // MARK: - init(hex:) — fallback / edge cases

    @Test("Empty string falls back to gray #808080")
    func emptyString() {
        // Length 0 → default case → (128, 128, 128)
        #expect(Color(hex: "").toHex() == "#808080")
    }

    @Test("2-char string falls back to gray #808080")
    func twoChars() {
        // Length 2 → default case
        #expect(Color(hex: "FF").toHex() == "#808080")
    }

    @Test("7-char string falls back to gray #808080")
    func sevenChars() {
        // Length 7 → default case
        #expect(Color(hex: "FFFFFFF").toHex() == "#808080")
    }

    @Test("Non-hex 6-char string scanner yields zero → black")
    func nonHexChars() {
        // "ZZZZZZ" is 6 chars; scanHexInt64 returns 0 → #000000
        #expect(Color(hex: "ZZZZZZ").toHex() == "#000000")
    }

    // MARK: - toHex() — general

    @Test("toHex returns non-nil for standard sRGB colors")
    func toHexNonNil() {
        #expect(Color(hex: "#4A90E2").toHex() != nil)
    }

    @Test("Multiple round-trips are stable")
    func roundTripStability() {
        let original = "#3A7BD5"
        let once = Color(hex: original).toHex()
        let twice = once.flatMap { Color(hex: $0).toHex() }
        #expect(once == original)
        #expect(twice == original)
    }
}

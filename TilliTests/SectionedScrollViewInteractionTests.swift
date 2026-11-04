//
//  SectionedScrollViewInteractionTests.swift
//  TilliTests
//
//  共用捲動容器的實際互動（驗證工具「按」chip、程式捲動）：
//  按 chip 把商品列表捲到該區塊並高亮；捲動時依序高亮、往回也依序；最後幾區很短時也不跳過。
//

import XCTest
import SwiftUI
@testable import Tilli

@MainActor
final class SectionedScrollViewInteractionTests: XCTestCase {

    private let names = ["甲", "乙", "丙", "丁"]

    /// 甲乙丙各 600pt，丁 120pt（很短，丙、丁捲不到頂端）
    private func harness() -> InteractionHarness<some View> {
        InteractionHarness(
            SectionedScrollView(ids: names, title: { Text(verbatim: $0) }) { name in
                Color.gray
                    .frame(height: name == "丁" ? 120 : 600)
                    .overlay(Text(verbatim: "區塊\(name)"))
            }
        )
    }

    func testStartsWithFirstChipHighlighted() {
        XCTAssertEqual(harness().selectedLabels, ["甲"])
    }

    func testTappingChipScrollsListToThatSection() throws {
        let h = harness()
        XCTAssertTrue(h.tap("乙"))
        XCTAssertEqual(try XCTUnwrap(h.mainScrollView).contentOffset.y, 624, accuracy: 1, "捲到乙的頂端（不是 chip 列在捲）")
        XCTAssertEqual(h.selectedLabels, ["乙"])
    }

    func testTappingChipOfCurrentSectionScrollsBackToItsTop() throws {
        let h = harness()
        h.scroll(toY: 300)
        XCTAssertEqual(h.selectedLabels, ["甲"])
        XCTAssertTrue(h.tap("甲"))
        XCTAssertEqual(try XCTUnwrap(h.mainScrollView).contentOffset.y, 0, accuracy: 1)
    }

    func testTappingUnreachableChipGoesToBottomAndKeepsItHighlighted() throws {
        let h = harness()
        XCTAssertTrue(h.tap("丙"))
        let scrollView = try XCTUnwrap(h.mainScrollView)
        let maxY = scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        XCTAssertEqual(scrollView.contentOffset.y, maxY, accuracy: 1, "丙捲不到頂端：停在底部")
        XCTAssertEqual(h.selectedLabels, ["丙"], "點選的高亮維持")
    }

    func testScrollingVisitsEverySectionInOrderBothWays() {
        let h = harness()
        var down: [String] = []
        for y in stride(from: 0.0, through: 1400, by: 40) {
            h.scroll(toY: y)
            if let label = h.selectedLabels.first, down.last != label { down.append(label) }
        }
        XCTAssertEqual(down, ["甲", "乙", "丙", "丁"])
        var up: [String] = []
        for y in stride(from: 1400.0, through: 0, by: -40) {
            h.scroll(toY: y)
            if let label = h.selectedLabels.first, up.last != label { up.append(label) }
        }
        XCTAssertEqual(up, ["丁", "丙", "乙", "甲"])
    }

    func testSingleSectionHasNoChipRow() {
        let h = InteractionHarness(
            SectionedScrollView(ids: ["唯一"], title: { Text(verbatim: $0) }) { _ in Color.gray.frame(height: 300) }
        )
        XCTAssertFalse(h.elements.contains { $0.accessibilityLabel == "唯一" && $0.accessibilityTraits.contains(.button) })
    }
}

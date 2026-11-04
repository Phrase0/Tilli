//
//  SectionHighlightTests.swift
//  TilliTests
//
//  chip 列高亮規則：佔據列表頂端的區塊；最後幾區捲不到頂端時最後一段平均分配、依序不跳過；
//  點選鎖定、版面改變時回到第一個。
//

import XCTest
@testable import Tilli

final class SectionHighlightTests: XCTestCase {

    private enum S: Hashable { case a, b, c, d }
    private let ids: [S] = [.a, .b, .c, .d]
    /// a、b、c 各 600，d 120；可見高度 800 → 最大捲動量 1320+... 依下面的 tops 計算
    private let tops: [S: CGFloat] = [.a: 0, .b: 624, .c: 1248, .d: 1872]
    private let maxY: CGFloat = 1192   // 內容 1992 − 可見 800；c、d 捲不到頂端

    private func active(_ y: CGFloat) -> S? {
        SectionHighlight.active(ids: ids, tops: tops, scrollY: y, maxScrollY: maxY)
    }

    func testTopSectionWhileReachable() {
        XCTAssertEqual(active(0), .a)
        XCTAssertEqual(active(622), .a)
        XCTAssertEqual(active(624), .b)
    }

    func testUnreachableSectionsShareTheLastStretchInOrder() {
        // b 到頂（624）之後到底（1192）這段平均分給 b、c、d
        XCTAssertEqual(active(700), .b)
        XCTAssertEqual(active(624 + 568 / 3 + 1), .c)
        XCTAssertEqual(active(624 + 568 * 2 / 3 + 1), .d)
        XCTAssertEqual(active(maxY), .d)
    }

    func testScrollingDownAndUpVisitsEverySectionInOrder() {
        var down: [S] = []
        for y in stride(from: 0, through: maxY, by: 20) {
            if let s = active(y), down.last != s { down.append(s) }
        }
        XCTAssertEqual(down, [.a, .b, .c, .d])
        var up: [S] = []
        for y in stride(from: maxY, through: 0, by: -20) {
            if let s = active(y), up.last != s { up.append(s) }
        }
        XCTAssertEqual(up, [.d, .c, .b, .a])
    }

    func testLastReachableAtBottomStillLeavesRoomForTheRest() {
        // c 剛好在捲到底時才到頂（最大捲動量 = c 的頂端），d 捲不到：
        // 起點往前移到 b，b 到底這段分給 b、c、d，d 仍會依序亮
        let maxAtC: CGFloat = 1248
        var seen: [S] = []
        for y in stride(from: 0, through: maxAtC, by: 20) {
            if let s = SectionHighlight.active(ids: ids, tops: tops, scrollY: y, maxScrollY: maxAtC), seen.last != s { seen.append(s) }
        }
        if let s = SectionHighlight.active(ids: ids, tops: tops, scrollY: maxAtC, maxScrollY: maxAtC), seen.last != s { seen.append(s) }
        XCTAssertEqual(seen, [.a, .b, .c, .d])
    }

    func testAllReachableUsesTopOnly() {
        let reachable: [S: CGFloat] = [.a: 0, .b: 300, .c: 600, .d: 900]
        XCTAssertEqual(SectionHighlight.active(ids: ids, tops: reachable, scrollY: 650, maxScrollY: 2000), .c)
    }

    func testShortContentHighlightsFirst() {
        // 內容一頁放得下：最大捲動量 0，後面三區都捲不到頂端；沒捲動時是第一個
        let short: [S: CGFloat] = [.a: 0, .b: 100, .c: 200, .d: 300]
        XCTAssertEqual(SectionHighlight.active(ids: ids, tops: short, scrollY: 0, maxScrollY: 0), .a,
                       "沒有可分配的捲動距離：維持頂端規則，不會一進來就高亮最後一個")
    }

    // MARK: - 狀態

    private func state() -> SectionScrollState<S> {
        var s = SectionScrollState<S>()
        s.appear(ids: ids)
        return s
    }

    func testAppearSelectsFirstOnlyOnce() {
        var s = state()
        XCTAssertEqual(s.selected, .a)
        s.select(.c)
        s.appear(ids: ids)
        XCTAssertEqual(s.selected, .c, "切換分頁回來保留")
    }

    func testPinnedIgnoresGeometryUntilUserScrolls() {
        var s = state()
        s.select(.c)
        s.geometryChanged(ids: ids, tops: tops, scrollY: 100, maxScrollY: maxY)
        XCTAssertEqual(s.selected, .c, "點選後鎖定（捲動動畫中、或捲不到頂端時都維持）")
        s.userDidScroll()
        XCTAssertEqual(s.selected, .a, "手指捲動解鎖後依目前位置")
    }

    func testLayoutChangeUnpinsAndFallsBack() {
        var s = state()
        s.select(.b)
        s.layoutChanged(ids: [.a, .c])
        XCTAssertFalse(s.isPinned)
        XCTAssertEqual(s.selected, .a, "原本高亮的區塊不見了回到第一個")
        s.select(.c)
        s.layoutChanged(ids: [.a, .c])
        XCTAssertEqual(s.selected, .c, "還在就保留")
    }

    func testEmptySectionsHaveNoHighlight() {
        var s = SectionScrollState<S>()
        s.appear(ids: [])
        XCTAssertNil(s.selected)
        XCTAssertNil(SectionHighlight.active(ids: [S](), tops: [:], scrollY: 0, maxScrollY: 0))
    }
}

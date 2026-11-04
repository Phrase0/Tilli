//
//  InventorySectionTests.swift
//  TilliTests
//
//  管理商品頁：區塊清單（組合｜套餐｜類別），以及實際點 chip、捲動。
//

import XCTest
import SwiftUI
@testable import Tilli

@MainActor
final class InventorySectionTests: XCTestCase {

    private var fixture: SectionFixture!
    private var viewModel: InventoryViewModel!

    override func setUp() async throws {
        try await super.setUp()
        fixture = try SectionFixture()
        viewModel = InventoryViewModel(dataSource: try fixture.makeDataSource())
        viewModel.updateRepositories(
            productRepository: ProductRepository(container: fixture.container),
            eventRepository: EventRepository(container: fixture.container)
        )
    }

    override func tearDown() async throws {
        viewModel = nil
        fixture = nil
        try await super.tearDown()
    }

    private func category(_ name: String) -> InventorySectionID { .category(fixture.categoryIds[name]!) }

    // MARK: - 區塊清單

    func testComboThenFixedThenCategories() {
        XCTAssertEqual(viewModel.sectionIDs, [.comboBundles, .fixedBundles, category("甜點"), category("飲料"), category("季節")])
    }

    func testSearchListsOnlyMatchingSections() {
        viewModel.searchText = "咖啡"
        XCTAssertEqual(viewModel.sectionIDs, [category("飲料")])
    }

    // MARK: - 實際點 chip、捲動

    private func harness() -> InteractionHarness<some View> {
        InteractionHarness(
            NavigationStack {
                InventoryView(
                    event: viewModel.event,
                    viewModel: viewModel,
                    showShareSheet: .constant(false),
                    formTarget: .constant(nil)
                )
            }
            .environmentObject(ProductRepository(container: fixture.container))
            .environmentObject(EventRepository(container: fixture.container))
        )
    }

    private var titles: [String] {
        [String.localized("bundleChipCombo"), String.localized("bundleChipFixed"), "甜點", "飲料", "季節"]
    }

    func testTappingChipsScrollsAndHighlights() throws {
        let h = harness()
        XCTAssertEqual(h.selectedLabels, [titles[0]])
        XCTAssertTrue(h.tap("飲料"))
        XCTAssertGreaterThan(try XCTUnwrap(h.mainScrollView).contentOffset.y, 0, "清單有捲動")
        XCTAssertEqual(h.selectedLabels, ["飲料"])
        XCTAssertTrue(h.tap(titles[0]))
        XCTAssertEqual(try XCTUnwrap(h.mainScrollView).contentOffset.y, 0, accuracy: 1)
        XCTAssertEqual(h.selectedLabels, [titles[0]])
    }

    func testScrollingVisitsEverySectionInOrder() throws {
        let h = harness()
        let scrollView = try XCTUnwrap(h.mainScrollView)
        let maxY = scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        XCTAssertGreaterThan(maxY, 0)
        var down: [String] = []
        for y in stride(from: 0, through: maxY, by: 20) {
            h.scroll(toY: y)
            if let label = h.selectedLabels.first, down.last != label { down.append(label) }
        }
        XCTAssertEqual(down, titles)
        var up: [String] = []
        for y in stride(from: maxY, through: 0, by: -20) {
            h.scroll(toY: y)
            if let label = h.selectedLabels.first, up.last != label { up.append(label) }
        }
        XCTAssertEqual(up, titles.reversed())
    }
}

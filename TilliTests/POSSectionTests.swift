//
//  POSSectionTests.swift
//  TilliTests
//
//  收銀頁：區塊清單（chip 列與商品列表的單一定義）、網格／列表設定，以及實際點 chip、捲動。
//

import XCTest
import SwiftUI
@testable import Tilli

@MainActor
final class POSSectionTests: XCTestCase {

    private var fixture: SectionFixture!
    private var viewModel: POSViewModel!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        fixture = try SectionFixture()
        defaults = UserDefaults(suiteName: "POSSectionTests")
        defaults.removePersistentDomain(forName: "POSSectionTests")
        viewModel = POSViewModel(dataSource: try fixture.makeDataSource(), defaults: defaults)
        viewModel.loadProducts()
    }

    override func tearDown() async throws {
        viewModel = nil
        fixture = nil
        try await super.tearDown()
    }

    private func category(_ name: String) -> POSSectionID { .category(fixture.categoryIds[name]!) }

    // MARK: - 區塊清單

    func testBundlesComeFirstThenCategoriesWithProducts() {
        XCTAssertEqual(viewModel.sectionIDs, [.bundles, category("甜點"), category("飲料"), category("季節")])
        XCTAssertEqual(viewModel.sectionTitle(.bundles), String.localized("posBundleSection"))
        XCTAssertEqual(viewModel.sectionTitle(category("飲料")), "飲料")
    }

    func testCategoryWithoutSellableProductsHasNoSection() throws {
        try fixture.setProductDisabled("草莓", true)
        viewModel.loadProducts()
        XCTAssertFalse(viewModel.sectionIDs.contains(category("季節")))
    }

    func testBundleSectionHiddenWhenMemberOffSale() throws {
        try fixture.setProductDisabled("抹茶", true)
        viewModel.loadProducts()
        XCTAssertFalse(viewModel.sectionIDs.contains(.bundles))
    }

    // MARK: - 網格／列表

    func testLayoutModeIsRestoredForNextViewModel() throws {
        XCTAssertEqual(viewModel.layoutMode, .list, "預設列表")
        viewModel.layoutMode = .grid
        viewModel.layoutMode = .list
        let next = POSViewModel(dataSource: try fixture.makeDataSource(), defaults: defaults)
        XCTAssertEqual(next.layoutMode, .list, "離開場次再進來讀回上次的選擇")
        XCTAssertEqual(defaults.string(forKey: "ProductLayoutMode"), "list", "寫進傳入的 defaults")
    }

    // MARK: - 實際點 chip、捲動

    private func harness(_ mode: ProductLayoutMode) -> InteractionHarness<some View> {
        viewModel.layoutMode = mode
        return InteractionHarness(NavigationStack { POSView(viewModel: viewModel) })
    }

    private var titles: [String] { viewModel.sectionIDs.map(viewModel.sectionTitle) }

    func testTappingChipsScrollsAndHighlights() throws {
        for mode in [ProductLayoutMode.list, .grid] {
            let h = harness(mode)
            let bundles = viewModel.sectionTitle(.bundles)
            XCTAssertEqual(h.selectedLabels, [bundles], "\(mode)")
            XCTAssertTrue(h.tap("飲料"), "\(mode)")
            let afterDrinks = try XCTUnwrap(h.mainScrollView).contentOffset.y
            XCTAssertGreaterThan(afterDrinks, 0, "\(mode) 商品列表有捲動")
            XCTAssertEqual(h.selectedLabels, ["飲料"], "\(mode)")
            XCTAssertTrue(h.tap(bundles), "\(mode)")
            XCTAssertEqual(try XCTUnwrap(h.mainScrollView).contentOffset.y, 0, accuracy: 1, "\(mode) 回到最上面")
            XCTAssertEqual(h.selectedLabels, [bundles], "\(mode)")
        }
    }

    func testScrollingVisitsEverySectionInOrder() throws {
        for mode in [ProductLayoutMode.list, .grid] {
            let h = harness(mode)
            let scrollView = try XCTUnwrap(h.mainScrollView)
            let maxY = scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
            XCTAssertGreaterThan(maxY, 0, "\(mode) 內容要能捲動")
            var down: [String] = []
            for y in stride(from: 0, through: maxY, by: 20) {
                h.scroll(toY: y)
                if let label = h.selectedLabels.first, down.last != label { down.append(label) }
            }
            XCTAssertEqual(down, titles, "\(mode) 往下依序")
            var up: [String] = []
            for y in stride(from: maxY, through: 0, by: -20) {
                h.scroll(toY: y)
                if let label = h.selectedLabels.first, up.last != label { up.append(label) }
            }
            XCTAssertEqual(up, titles.reversed(), "\(mode) 往上依序")
        }
    }
}

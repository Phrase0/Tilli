//
//  BundleOrderTests.swift
//  TilliTests
//
//  套餐／組合的顯示順序：sortOrder 優先，相同時依建立時間；新增的排在同 kind 最後。
//

import XCTest
@testable import Tilli

@MainActor
final class BundleOrderTests: XCTestCase {

    private func bundle(_ name: String, created: TimeInterval, order: Int, mode: BundleMode = .fixed) -> BundleModel {
        BundleModel.mock(name: name, mode: mode, createdAt: Date(timeIntervalSince1970: created), sortOrder: order)
    }

    func testSortOrderWinsOverCreatedAt() {
        let a = bundle("先建", created: 1, order: 1)
        let b = bundle("後建", created: 2, order: 0)
        XCTAssertEqual([a, b].sortedForDisplay().map(\.name), ["後建", "先建"])
    }

    func testSameSortOrderFallsBackToCreatedAt() {
        let late = bundle("後建", created: 2, order: 0)
        let early = bundle("先建", created: 1, order: 0)
        XCTAssertEqual([late, early].sortedForDisplay().map(\.name), ["先建", "後建"])
    }

    func testSortOrderSurvivesEncodeDecode() throws {
        let b = bundle("A", created: 1, order: 5)
        let decoded = try JSONDecoder().decode(BundleModel.self, from: JSONEncoder().encode(b))
        XCTAssertEqual(decoded.sortOrder, 5)
    }

    func testNewBundleIsAppendedAtEndOfItsKind() {
        let daifuku = ProductModel.mock(name: "大福", price: 40)
        let matcha = ProductModel.mock(name: "抹茶", price: 60)
        var event = EventModel.mock()
        event.bundles = [
            bundle("套餐0", created: 1, order: 0),
            bundle("套餐1", created: 2, order: 1),
            bundle("組合7", created: 3, order: 7, mode: .chooseAny(count: 2)),
        ]
        let vm = BundleFormViewModel(kind: .fixed, editing: nil, event: event, products: [daifuku, matcha])
        vm.name = "新套餐"
        vm.priceText = "90"
        vm.selectedProductIds = [daifuku.id, matcha.id]
        let added = vm.bundlesToSave()?.first { $0.name == "新套餐" }
        XCTAssertEqual(added?.sortOrder, 2, "只看同 kind（套餐）的最大值")
    }
}

//
//  ProductAvailabilityTests.swift
//  TilliTests
//
//  Created by Peiyun on 2026/9/13.
//
//  對應 FEATURE_PLAN_V1.md §2.5（B6）與測試清單 U12。
//

import XCTest
@testable import Tilli

final class ProductAvailabilityTests: XCTestCase {

    private let categoryId = UUID()

    private func category(isDisabled: Bool = false, sortOrder: Int = 0) -> CategoryModel {
        .mock(id: categoryId, isDisabled: isDisabled, sortOrder: sortOrder)
    }

    // MARK: - saleAvailability（純判斷，可測到 fail-closed 分支）

    func testAvailableWhenProductAndCategoryBothEnabled() {
        let product = ProductModel.mock(categoryId: categoryId)
        XCTAssertEqual(product.saleAvailability(in: [category()]), .available)
        XCTAssertTrue(product.isAvailableForSale(in: [category()]))
    }

    func testDisabledProductIsNotAvailable() {
        let product = ProductModel.mock(categoryId: categoryId, isDisabled: true)
        XCTAssertEqual(product.saleAvailability(in: [category()]), .productDisabled)
        XCTAssertFalse(product.isAvailableForSale(in: [category()]))
    }

    func testProductInDisabledCategoryIsNotAvailable() {
        // ⭐ B6：原本 6 處只有 1 處檢查這第二層
        let product = ProductModel.mock(categoryId: categoryId)
        XCTAssertEqual(
            product.saleAvailability(in: [category(isDisabled: true)]),
            .categoryDisabled
        )
        XCTAssertFalse(product.isAvailableForSale(in: [category(isDisabled: true)]))
    }

    /// ⭐ U12：類別不存在時 fail-closed。
    ///
    /// 這裡只測純函式 `saleAvailability` —— `isAvailableForSale` 在這條分支會
    /// `assertionFailure`，Debug 下測試會直接 trap，所以判斷邏輯與副作用是分開的。
    func testMissingCategoryFailsClosed() {
        let product = ProductModel.mock(categoryId: UUID())   // 指向不存在的類別
        XCTAssertEqual(product.saleAvailability(in: [category()]), .categoryMissing)
    }

    func testEmptyCategoryListIsMissingNotAvailable() {
        let product = ProductModel.mock(categoryId: categoryId)
        XCTAssertEqual(product.saleAvailability(in: []), .categoryMissing)
    }

    func testDisabledProductTakesPrecedenceOverMissingCategory() {
        // 商品自己就下架了，不需要再看類別（也就不會誤觸 assertion）
        let product = ProductModel.mock(categoryId: UUID(), isDisabled: true)
        XCTAssertEqual(product.saleAvailability(in: []), .productDisabled)
        XCTAssertFalse(product.isAvailableForSale(in: []))
    }

    // MARK: - [CategoryModel].active / .disabled

    func testActiveFiltersDisabledAndSortsBySortOrder() {
        let categories: [CategoryModel] = [
            .mock(name: "丙", isDisabled: false, sortOrder: 2),
            .mock(name: "停用", isDisabled: true, sortOrder: 1),
            .mock(name: "甲", isDisabled: false, sortOrder: 0),
            .mock(name: "乙", isDisabled: false, sortOrder: 1)
        ]

        XCTAssertEqual(categories.active.map(\.name), ["甲", "乙", "丙"])
    }

    func testDisabledFiltersActiveAndSortsBySortOrder() {
        let categories: [CategoryModel] = [
            .mock(name: "停用B", isDisabled: true, sortOrder: 3),
            .mock(name: "啟用", isDisabled: false, sortOrder: 0),
            .mock(name: "停用A", isDisabled: true, sortOrder: 1)
        ]

        XCTAssertEqual(categories.disabled.map(\.name), ["停用A", "停用B"])
    }

    func testActiveAndDisabledArePartitionOfInput() {
        let categories: [CategoryModel] = [
            .mock(isDisabled: false, sortOrder: 0),
            .mock(isDisabled: true, sortOrder: 1),
            .mock(isDisabled: false, sortOrder: 2)
        ]

        XCTAssertEqual(categories.active.count + categories.disabled.count, categories.count)
    }

    func testEmptyInput() {
        XCTAssertTrue([CategoryModel]().active.isEmpty)
        XCTAssertTrue([CategoryModel]().disabled.isEmpty)
    }
}

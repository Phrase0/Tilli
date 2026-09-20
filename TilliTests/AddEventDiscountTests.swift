//
//  AddEventDiscountTests.swift
//  TilliTests
//
//  Created by Peiyun on 2026/9/20.
//
//  對應 FEATURE_PLAN_V1.md §11 第 3 批的 3.3（折扣管理：分兩區、新增不排序、儲存才排）。
//

import XCTest
@testable import Tilli

@MainActor
final class AddEventDiscountTests: XCTestCase {

    private func makeViewModel() -> AddEventViewModel {
        AddEventViewModel(eventToEdit: nil)
    }

    @discardableResult
    private func add(_ vm: AddEventViewModel, _ type: DiscountType, _ value: String) -> String? {
        if type == .percentage { vm.newPercentageValue = value } else { vm.newAmountValue = value }
        return vm.tryAddDiscount(type: type)
    }

    // MARK: - 型別由「在哪一區輸入」決定

    func testAddingToEachSectionProducesCorrectType() {
        let vm = makeViewModel()

        XCTAssertNil(add(vm, .percentage, "10"))
        XCTAssertNil(add(vm, .amount, "20"))

        XCTAssertEqual(vm.percentageDiscounts.map(\.value), [10])
        XCTAssertEqual(vm.amountDiscounts.map(\.value), [20])
    }

    func testInputFieldIsClearedAfterAdding() {
        let vm = makeViewModel()

        add(vm, .percentage, "10")

        XCTAssertEqual(vm.newPercentageValue, "")
        XCTAssertEqual(vm.newAmountValue, "", "另一區的輸入不該被動到")
    }

    // MARK: - ⭐ 新增時不排序（避免輸入時位置跳動）

    func testNewDiscountsKeepInsertionOrderWhileEditing() {
        let vm = makeViewModel()

        add(vm, .percentage, "20")
        add(vm, .percentage, "5")
        add(vm, .percentage, "10")

        XCTAssertEqual(vm.percentageDiscounts.map(\.value), [20, 5, 10],
                       "編輯中維持輸入順序，新增的接在最後")
    }

    func testDeletingDoesNotReorder() {
        let vm = makeViewModel()

        add(vm, .amount, "50")
        add(vm, .amount, "10")
        add(vm, .amount, "30")
        vm.deleteDiscount(vm.amountDiscounts[1])   // 刪掉 10

        XCTAssertEqual(vm.amountDiscounts.map(\.value), [50, 30])
    }

    // MARK: - ⭐ 儲存時才升冪

    func testSortedForStoragePutsPercentageFirstThenAscending() {
        let discounts: [DiscountModel] = [
            .amount(50), .percentage(20), .amount(10), .percentage(5)
        ]

        let sorted = discounts.sortedForStorage

        XCTAssertEqual(sorted.map(\.type), [.percentage, .percentage, .amount, .amount])
        XCTAssertEqual(sorted.map(\.value), [5, 20, 10, 50])
    }

    func testSortedForStorageHandlesSingleTypeAndEmpty() {
        XCTAssertTrue([DiscountModel]().sortedForStorage.isEmpty)
        XCTAssertEqual(
            [DiscountModel.percentage(20), .percentage(5)].sortedForStorage.map(\.value),
            [5, 20]
        )
    }

    // MARK: - 驗證（各區獨立查重）

    func testDuplicateIsRejectedWithinSameTypeOnly() {
        let vm = makeViewModel()

        add(vm, .percentage, "10")

        XCTAssertNotNil(add(vm, .percentage, "10"), "同一區重複要被擋下")
        XCTAssertNil(add(vm, .amount, "10"), "不同區的相同數值是合法的")
    }

    func testPercentageOverHundredIsRejected() {
        let vm = makeViewModel()

        XCTAssertNotNil(add(vm, .percentage, "101"))
        XCTAssertNil(add(vm, .amount, "101"), "減額折扣沒有 100 的上限")
    }

    func testNonIntegerAndNonPositiveAreRejected() {
        let vm = makeViewModel()

        XCTAssertNotNil(add(vm, .percentage, "10.5"))
        XCTAssertNotNil(add(vm, .amount, "0"))
        XCTAssertNotNil(add(vm, .amount, "-5"))
        XCTAssertNotNil(add(vm, .amount, "abc"))
        XCTAssertTrue(vm.discounts.isEmpty)
    }

    func testEmptyInputIsRejectedWithMessage() {
        let vm = makeViewModel()
        XCTAssertNotNil(vm.tryAddDiscount(type: .percentage))
    }
}

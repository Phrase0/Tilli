//
//  AddEventCategoryInputTests.swift
//  TilliTests
//
//  場次設定的新增類別輸入：與折扣同一套規則（+ 常駐、有誤時不能按、儲存時重複的輸入只清掉）。
//

import XCTest
@testable import Tilli

@MainActor
final class AddEventCategoryInputTests: XCTestCase {

    private func makeViewModel() -> AddEventViewModel {
        AddEventViewModel(eventToEdit: nil)
    }

    func testCannotAddEmptyOrDuplicateCategory() {
        let vm = makeViewModel()
        XCTAssertFalse(vm.canAddCategory, "沒輸入時 + 不能按")

        vm.newCategory = "甜點"
        XCTAssertTrue(vm.canAddCategory)
        XCTAssertNil(vm.tryAddCategory())

        vm.newCategory = " 甜點 "
        XCTAssertFalse(vm.canAddCategory, "重複時 + 不能按")
        XCTAssertEqual(vm.validateCategoryValue(), String.localized("addEventCategoryExists"))

        vm.newCategory = "飲料"
        XCTAssertTrue(vm.canAddCategory)
    }

    func testSavingWithDuplicatePendingCategoryClearsItAndSucceeds() {
        let vm = makeViewModel()
        vm.eventName = "市集"
        vm.newCategory = "甜點"
        XCTAssertNil(vm.tryAddCategory())

        // 輸入欄留著已存在的名稱就按儲存：該類別本來就有，清掉輸入欄、照常儲存
        vm.newCategory = "甜點"
        guard case .success = vm.validateSave() else {
            return XCTFail("重複的未送出類別不應擋住儲存")
        }
        XCTAssertEqual(vm.newCategory, "")
        XCTAssertEqual(vm.categories.count, 1)
    }
}

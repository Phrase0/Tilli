//
//  BundleDuplicationTests.swift
//  TilliTests
//
//  複製場次時套餐與組合的 id 重對應（純函式）。
//

import XCTest
@testable import Tilli

final class BundleDuplicationTests: XCTestCase {

    func testRemapAssignsNewBundleIdsAndNewProductIds() {
        let a = UUID(), b = UUID()
        let newA = UUID(), newB = UUID()
        let original = BundleModel.fixedMock(productIds: [a, b])

        let copy = original.remapped(productIdMap: [a: newA, b: newB])

        XCTAssertNotNil(copy)
        XCTAssertNotEqual(copy?.id, original.id)
        XCTAssertEqual(copy?.productIds, [newA, newB])
    }

    func testRemapKeepsNamePriceModeAndDisabledState() {
        let a = UUID()
        let original = BundleModel.mock(
            name: "雙拼", price: 150, mode: .chooseAny(count: 2),
            productIds: [a], isDisabled: true, imageURL: "https://x/y.jpg",
            createdAt: Date(timeIntervalSince1970: 42)
        )

        let copy = original.remapped(productIdMap: [a: UUID()])

        XCTAssertEqual(copy?.name, "雙拼")
        XCTAssertEqual(copy?.price, 150)
        XCTAssertEqual(copy?.mode, .chooseAny(count: 2))
        XCTAssertEqual(copy?.isDisabled, true)
        XCTAssertEqual(copy?.createdAt, Date(timeIntervalSince1970: 42))
        XCTAssertNil(copy?.imageURL)
    }

    func testRemapReturnsNilWhenAMemberIsMissingFromMap() {
        let a = UUID(), b = UUID()
        let original = BundleModel.fixedMock(productIds: [a, b])

        XCTAssertNil(original.remapped(productIdMap: [a: UUID()]))
    }
}

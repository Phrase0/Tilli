//
//  MoneyFormatTests.swift
//  TilliTests
//
//  畫面金額（MoneyHelper.format）：有小數的幣別，四捨五入後是整數就不顯示小數，有分就顯示兩位；
//  CSV 用的 toDisplayString 維持固定小數位數。
//

import XCTest
@testable import Tilli

final class MoneyFormatTests: XCTestCase {

    func testWholeAmountHidesDecimalsForDecimalCurrency() {
        XCTAssertEqual(MoneyHelper.format(88, currency: .usd), "$88")
    }

    func testAmountWithCentsShowsTwoDecimals() {
        XCTAssertEqual(MoneyHelper.format(Decimal(string: "88.5")!, currency: .usd), "$88.50")
        XCTAssertEqual(MoneyHelper.format(Decimal(string: "88.05")!, currency: .usd), "$88.05")
    }

    func testZeroHidesDecimals() {
        XCTAssertEqual(MoneyHelper.format(0, currency: .eur), "€0")
    }

    func testAmountRoundingToWholeHidesDecimals() {
        XCTAssertEqual(MoneyHelper.format(Decimal(string: "87.999")!, currency: .usd), "$88")
    }

    func testCurrencyCodeOverloadFollowsSameRule() {
        XCTAssertEqual(MoneyHelper.format(88, currencyCode: "GBP"), "£88")
        XCTAssertEqual(MoneyHelper.format(Decimal(string: "88.5")!, currencyCode: "GBP"), "£88.50")
    }

    func testNoDecimalCurrencyUnchanged() {
        XCTAssertEqual(MoneyHelper.format(88, currency: .twd), "NT$88")
        XCTAssertEqual(MoneyHelper.format(Decimal(string: "88.6")!, currency: .twd), "NT$89")
    }

    func testCSVDisplayStringKeepsFixedDecimals() {
        XCTAssertEqual(MoneyHelper.toDisplayString(88, currency: .usd), "88.00")
        XCTAssertEqual(MoneyHelper.toDisplayString(Decimal(string: "88.5")!, currency: .usd), "88.50")
    }
}

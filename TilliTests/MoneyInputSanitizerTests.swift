//
//  MoneyInputSanitizerTests.swift
//  TilliTests
//
//  MoneyHelper.sanitizeInput：商品價格、套餐／組合價格、現金收款共用的金額輸入整理。
//

import XCTest
@testable import Tilli

final class MoneyInputSanitizerTests: XCTestCase {

    func testZeroDecimalCurrencyDropsDecimalPointAndLetters() {
        XCTAssertEqual(MoneyHelper.sanitizeInput("1a2.5", currency: .twd), "125")
    }

    func testDecimalCurrencyKeepsFirstPointAndLimitsFraction() {
        XCTAssertEqual(MoneyHelper.sanitizeInput("12.345", currency: .usd), "12.34")
        XCTAssertEqual(MoneyHelper.sanitizeInput("1.2.3", currency: .usd), "1.2")
        XCTAssertEqual(MoneyHelper.sanitizeInput("5.", currency: .usd), "5.")
    }

    func testIntegerDigitsAreCappedWhenLimitGiven() {
        XCTAssertEqual(MoneyHelper.sanitizeInput("12345678901", currency: .twd, maxIntegerDigits: 10), "1234567890")
        XCTAssertEqual(MoneyHelper.sanitizeInput("12345678901.5", currency: .usd, maxIntegerDigits: 10), "1234567890.5")
        XCTAssertEqual(MoneyHelper.sanitizeInput("12345678901", currency: .twd), "12345678901")
    }

    func testEmptyInputStaysEmpty() {
        XCTAssertEqual(MoneyHelper.sanitizeInput("", currency: .usd), "")
    }

    @MainActor
    func testBundleFormUsesSameRulesAsProductForm() {
        let viewModel = BundleFormViewModel(kind: .fixed, editing: nil, event: .mock(currency: "USD"), products: [])
        viewModel.priceText = "12345678901.999"

        viewModel.sanitizePrice()

        XCTAssertEqual(viewModel.priceText, "1234567890.99")
    }
}

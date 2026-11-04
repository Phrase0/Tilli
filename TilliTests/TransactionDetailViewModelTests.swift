//
//  TransactionDetailViewModelTests.swift
//  TilliTests
//
//  交易明細頁 ViewModel 與共用的交易顯示文字（交易編號、付款方式）。
//

import XCTest
@testable import Tilli

@MainActor
final class TransactionDetailViewModelTests: XCTestCase {

    private func transaction(currency: String = "TWD", paymentMethod: PaymentMethod = .cash) -> TransactionModel {
        TransactionModel(
            id: UUID(uuidString: "abcdef12-3456-7890-abcd-ef1234567890")!,
            eventId: UUID(),
            eventTitle: "測試場次",
            currency: currency,
            items: [],
            totalAmount: 0,
            paymentMethod: paymentMethod,
            timestamp: Date()
        )
    }

    func testTransactionNumberUsesFirstEightCharactersUppercased() {
        XCTAssertEqual(TransactionModel.displayNumber(for: UUID(uuidString: "abcdef12-3456-7890-abcd-ef1234567890")!), "TXNABCDEF12")
        XCTAssertEqual(TransactionDetailViewModel(transaction: transaction()).transactionNumber, "TXNABCDEF12")
    }

    func testPaymentMethodTextIsLocalized() {
        XCTAssertEqual(TransactionDetailViewModel(transaction: transaction(paymentMethod: .cash)).paymentMethodText,
                       String.localized("transactionPaymentCash"))
        XCTAssertEqual(TransactionDetailViewModel(transaction: transaction(paymentMethod: .ePayment)).paymentMethodText,
                       String.localized("transactionPaymentEPayment"))
    }

    func testAmountsUseTheTransactionCurrency() {
        let viewModel = TransactionDetailViewModel(transaction: transaction(currency: "USD"))
        XCTAssertEqual(viewModel.formatAmount(Decimal(string: "1.5")!), MoneyHelper.format(Decimal(string: "1.5")!, currencyCode: "USD"))
        XCTAssertEqual(viewModel.currency, "USD")
    }
}

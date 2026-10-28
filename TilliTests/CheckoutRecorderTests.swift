import XCTest
@testable import Tilli

final class CheckoutRecorderTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000)

    private func record(
        items: [SummaryItemModel],
        deductions: [RevenueAllocator.BundleDeduction] = [],
        discounts: [AppliedDiscount] = [],
        total: Decimal
    ) -> CheckoutRecorder.Record {
        CheckoutRecorder.makeRecord(
            event: .mock(),
            items: items,
            bundleDeductions: deductions,
            appliedDiscounts: discounts,
            totalAmount: total,
            paymentMethod: .cash,
            occurredAt: nil,
            now: now
        )
    }

    func testStockUpdatesAccumulateRowsOfSameProduct() {
        let daifuku = UUID()
        let items = [
            SummaryItemModel.mock(productId: daifuku, quantity: 3),
            SummaryItemModel.mock(productId: daifuku, quantity: 1)
        ]
        let result = CheckoutRecorder.stockUpdates(for: items, currentStock: [daifuku: 10])
        XCTAssertEqual(result[daifuku], 6)
    }

    func testStockUpdatesClampAtZeroAndSkipUnknownProducts() {
        let a = UUID()
        let items = [
            SummaryItemModel.mock(productId: a, quantity: 5),
            SummaryItemModel.mock(productId: UUID(), quantity: 1)
        ]
        let result = CheckoutRecorder.stockUpdates(for: items, currentStock: [a: 2])
        XCTAssertEqual(result, [a: 0])
    }

    func testDiscountsAreSanitizedAgainstSubtotalAfterBundleDeductions() {
        let bundleId = UUID()
        var item = SummaryItemModel.mock(price: 100, quantity: 2)
        item.bundleId = bundleId
        item.bundleKind = .fixed
        let r = record(
            items: [item],
            deductions: [.init(bundleId: bundleId, amount: 20)],
            discounts: [.mock(type: .amount, value: 1000, amount: 1000)],
            total: 0
        )
        XCTAssertEqual(r.transaction.appliedDiscounts.first?.amount, 180)
    }

    func testOnlyFixedBundleRowsTagInventoryChangesWithBundle() {
        let bundleId = UUID()
        var fixedRow = SummaryItemModel.mock(name: "套餐內")
        fixedRow.bundleId = bundleId
        fixedRow.bundleName = "套餐A"
        fixedRow.bundleKind = .fixed
        var comboRow = SummaryItemModel.mock(name: "組合內")
        comboRow.bundleId = UUID()
        comboRow.bundleName = "組合B"
        comboRow.bundleKind = .chooseAny
        let plain = SummaryItemModel.mock(name: "單點")

        let r = record(items: [fixedRow, comboRow, plain], total: 300)
        XCTAssertEqual(r.inventoryChanges.count, 3)
        XCTAssertEqual(r.inventoryChanges[0].bundleId, bundleId)
        XCTAssertEqual(r.inventoryChanges[0].bundleName, "套餐A")
        XCTAssertNil(r.inventoryChanges[1].bundleId)
        XCTAssertNil(r.inventoryChanges[1].bundleName)
        XCTAssertNil(r.inventoryChanges[2].bundleId)
        XCTAssertTrue(r.inventoryChanges.allSatisfy { $0.reason == .salesOut && $0.transactionId == r.transaction.id })
    }

    func testRecordedTransactionReconciles() {
        let bundleId = UUID()
        var a = SummaryItemModel.mock(price: 60)
        var b = SummaryItemModel.mock(price: 60)
        a.bundleId = bundleId; a.bundleKind = .fixed
        b.bundleId = bundleId; b.bundleKind = .fixed
        let single = SummaryItemModel.mock(price: 80)
        let r = record(
            items: [a, b, single],
            deductions: [.init(bundleId: bundleId, amount: 20)],
            discounts: [.mock(type: .amount, value: 30, amount: 30)],
            total: 150
        )
        let revenue = r.transaction.items.reduce(Decimal(0)) { MoneyHelper.add($0, $1.actualRevenue) }
        XCTAssertEqual(revenue, r.transaction.totalAmount)
    }
}

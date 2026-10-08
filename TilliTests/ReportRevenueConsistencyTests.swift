//
//  ReportRevenueConsistencyTests.swift
//  TilliTests
//
//  Created by Peiyun on 2026/10/8.
//
//  ⭐ R2／A6：銷售分析的總營收 == 商品績效的實際營收加總 == 類別分析加總。
//  對應 FEATURE_PLAN_V1.md §11 第 4 批的 4.3／4.4。
//
//  原本兩張報表口徑不同（一個用 totalAmount、一個在報表端重新攤提），
//  只是「目前巧合一致」。現在攤提在結帳時寫進 SummaryItem，報表只加總。
//

import XCTest
import CoreData
@testable import Tilli

@MainActor
final class ReportRevenueConsistencyTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var dataSource: EventDataSource!

    override func setUp() async throws {
        try await super.setUp()
        container = TestStore.makeInMemoryContainer()
        let eventId = try seed()

        let event = EventRepository(container: container).fetchEvent(by: eventId)!
        dataSource = EventDataSource(event: event)
        dataSource.attach(
            eventRepository: EventRepository(container: container),
            productRepository: ProductRepository(container: container),
            transactionRepository: TransactionRepository(container: container),
            inventoryChangeRepository: InventoryChangeRepository(container: container)
        )
    }

    override func tearDown() async throws {
        dataSource = nil
        container = nil
        try await super.tearDown()
    }

    /// 含折扣、不含折扣、補記帳、除不盡的交易各一筆以上
    private func seed() throws -> UUID {
        let context = container.viewContext

        let event = CDEventEntity(context: context)
        event.id = UUID()
        event.title = "測試場次"
        event.startDate = Date()
        event.createdAt = Date()
        event.currency = "TWD"
        event.dateType = EventDateType.single.rawValue

        let dessert = UUID()
        let drink = UUID()
        let a = SummaryItemModel.mock(name: "大福", price: 45, categoryId: dessert, category: "甜點", quantity: 3)
        let b = SummaryItemModel.mock(name: "銅鑼燒", price: 38, categoryId: dessert, category: "甜點")
        let c = SummaryItemModel.mock(name: "麥茶", price: 25, categoryId: drink, category: "飲料", quantity: 2)

        func addTransaction(_ items: [SummaryItemModel], discounts: [DiscountModel], occurredAt: Date? = nil) {
            let subtotal = items.subtotal
            let applied = DiscountCalculator.applied(for: discounts, subtotal: subtotal)

            let entity = CDTransactionEntity(context: context)
            entity.id = UUID()
            entity.eventId = event.id
            entity.eventTitle = event.title
            entity.currency = "TWD"
            entity.totalAmount = NSDecimalNumber(decimal: DiscountCalculator.total(subtotal: subtotal, discounts: discounts))
            entity.paymentMethod = PaymentMethod.cash.rawValue
            entity.timestamp = Date()
            entity.occurredAt = occurredAt
            entity.items = RevenueAllocator.allocate(items, discounts: applied, currency: "TWD")
            entity.appliedDiscounts = applied
            entity.event = event
        }

        addTransaction([a, b, c], discounts: [])
        addTransaction([a, b, c], discounts: [.percentage(15)])                    // 除不盡
        addTransaction([a, c], discounts: [.percentage(10), .amount(7)])
        addTransaction([b], discounts: [.amount(500)])                             // clamp 到全額
        addTransaction([a, b], discounts: [.amount(13)], occurredAt: Date().addingTimeInterval(-3600))  // 補記帳

        try context.save()
        return event.id
    }

    func testSalesOverviewEqualsProductAndCategoryRevenue() {
        let sales = SalesAnalyticsViewModel(dataSource: dataSource)
        let performance = ProductPerformanceViewModel(dataSource: dataSource)
        sales.loadData()
        performance.loadData()

        let overview = sales.salesOverview?.totalAmount
        let productSum = performance.topProducts.reduce(Decimal(0)) { MoneyHelper.add($0, $1.actualRevenue) }
        let categorySum = performance.categoryAnalysis.reduce(Decimal(0)) { MoneyHelper.add($0, $1.amount) }

        XCTAssertNotNil(overview)
        XCTAssertEqual(productSum, overview)
        XCTAssertEqual(categorySum, overview)
    }

    /// 商品績效的營收 = Σ SummaryItem.actualRevenue，原價 − 折扣逐項對得起來
    func testProductRevenueIsPlainSumOfAllocatedItems() {
        let performance = ProductPerformanceViewModel(dataSource: dataSource)
        performance.loadData()

        let items = dataSource.transactions.flatMap(\.items)
        for product in performance.topProducts {
            let mine = items.filter { $0.productId == product.productId }
            let revenue = mine.reduce(Decimal(0)) { MoneyHelper.add($0, $1.actualRevenue) }
            let discount = mine.reduce(Decimal(0)) { MoneyHelper.add($0, $1.allocatedDiscount) }

            XCTAssertEqual(product.actualRevenue, revenue, product.name)
            XCTAssertEqual(product.discount, discount, product.name)
            XCTAssertGreaterThanOrEqual(product.actualRevenue, 0, product.name)
        }
    }
}

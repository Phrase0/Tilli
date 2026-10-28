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
        addBundleTransaction(to: event, dessert: dessert)

        try context.save()
        return event.id
    }

    /// 第 5 批：套餐 + 組合 + 百分比 + 減額，奇數 TWD 金額。走正式結帳流程
    /// （CartPricing → summaryItems → CheckoutRecorder）產生交易。
    private func addBundleTransaction(to event: CDEventEntity, dessert: UUID) {
        let daifuku = ProductModel.mock(name: "大福", price: 37, categoryId: dessert)
        let matcha = ProductModel.mock(name: "抹茶", price: 53, categoryId: dessert)
        let strawberry = ProductModel.mock(name: "草莓", price: 29, categoryId: dessert)
        let set = BundleModel.fixedMock(name: "奇數套餐", price: 79, productIds: [daifuku.id, matcha.id])
        let combo = BundleModel.comboMock(name: "草莓兩個", price: 51, count: 2, productIds: [strawberry.id])
        let cart = Cart(
            productQuantities: [strawberry.id: 3, daifuku.id: 1],
            bundleLines: [set.id: BundleCartLine(
                quantity: 2, nameAtAdd: set.name, priceAtAdd: set.price, productIdsAtAdd: set.productIds
            )]
        )
        let pricing = CartPricing.price(
            cart: cart,
            products: Dictionary(uniqueKeysWithValues: [daifuku, matcha, strawberry].map { ($0.id, $0) }),
            bundles: [set.id: set, combo.id: combo],
            categories: [CategoryModel.mock(id: dessert, name: "甜點")],
            selectedDiscounts: [.percentage(15), .amount(7)]
        )
        let (items, deductions) = pricing.summaryItems(categoryName: { _ in "甜點" }, timestamp: Date())
        let record = CheckoutRecorder.makeRecord(
            event: .mock(id: event.id, title: event.title),
            items: items,
            bundleDeductions: deductions,
            appliedDiscounts: pricing.discounts,
            totalAmount: pricing.total,
            paymentMethod: .cash,
            occurredAt: nil,
            now: Date()
        )
        let transaction = record.transaction

        let entity = CDTransactionEntity(context: event.managedObjectContext!)
        entity.id = transaction.id
        entity.eventId = event.id
        entity.eventTitle = event.title
        entity.currency = "TWD"
        entity.totalAmount = NSDecimalNumber(decimal: transaction.totalAmount)
        entity.paymentMethod = PaymentMethod.cash.rawValue
        entity.timestamp = transaction.timestamp
        entity.items = transaction.items
        entity.appliedDiscounts = transaction.appliedDiscounts
        entity.event = event
    }

    /// 銷售分析總營收 == 商品績效實際營收加總 == 類別分析加總
    private func assertReportsAgree(file: StaticString = #filePath, line: UInt = #line) {
        let sales = SalesAnalyticsViewModel(dataSource: dataSource)
        let performance = ProductPerformanceViewModel(dataSource: dataSource)
        sales.loadData()
        performance.loadData()

        let overview = sales.salesOverview?.totalAmount
        let productSum = performance.topProducts.reduce(Decimal(0)) { MoneyHelper.add($0, $1.actualRevenue) }
        let categorySum = performance.categoryAnalysis.reduce(Decimal(0)) { MoneyHelper.add($0, $1.amount) }

        XCTAssertNotNil(overview, file: file, line: line)
        XCTAssertEqual(productSum, overview, file: file, line: line)
        XCTAssertEqual(categorySum, overview, file: file, line: line)
    }

    func testSalesOverviewEqualsProductAndCategoryRevenue() {
        assertReportsAgree()
    }

    /// 套餐／組合交易也在上面的等式裡，且本身 Σ actualRevenue == totalAmount
    func testBundleAndComboTransactionKeepsReportsEqual() throws {
        let transaction = try XCTUnwrap(
            dataSource.transactions.first { $0.items.contains { $0.bundleKind == .fixed } },
            "seed 應含套餐交易"
        )
        XCTAssertTrue(transaction.items.contains { $0.bundleKind == .chooseAny }, "應含組合")
        XCTAssertEqual(Set(transaction.appliedDiscounts.map(\.type)), [.percentage, .amount])
        XCTAssertEqual(
            transaction.items.reduce(Decimal(0)) { MoneyHelper.add($0, $1.actualRevenue) },
            transaction.totalAmount
        )

        assertReportsAgree()
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

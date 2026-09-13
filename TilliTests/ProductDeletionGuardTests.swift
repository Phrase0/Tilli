//
//  ProductDeletionGuardTests.swift
//  TilliTests
//
//  Created by Peiyun on 2026/9/13.
//
//  對應 FEATURE_PLAN_V1.md §3.2／§3.3（D3）與測試清單 D6。
//

import XCTest
import CoreData
@testable import Tilli

final class ProductDeletionGuardTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var repository: ProductRepository!
    private var context: NSManagedObjectContext { container.viewContext }

    override func setUp() {
        super.setUp()
        container = TestStore.makeInMemoryContainer()
        repository = ProductRepository(container: container)
    }

    override func tearDown() {
        repository = nil
        container = nil
        super.tearDown()
    }

    // MARK: - Fixtures（直接建 entity，避開 repository 的 Auth 依賴）

    @discardableResult
    private func makeEvent() -> CDEventEntity {
        let event = CDEventEntity(context: context)
        event.id = UUID()
        event.title = "測試場次"
        event.startDate = Date()
        event.createdAt = Date()
        event.currency = "TWD"
        event.dateType = EventDateType.single.rawValue
        return event
    }

    private func makeCategory(in event: CDEventEntity) -> CDCategoryEntity {
        let category = CDCategoryEntity(context: context)
        category.id = UUID()
        category.name = "測試類別"
        category.createdAt = Date()
        category.isDisabled = false
        category.sortOrder = 0
        category.event = event
        return category
    }

    private func makeProduct(in category: CDCategoryEntity, event: CDEventEntity) -> CDProductEntity {
        let product = CDProductEntity(context: context)
        product.id = UUID()
        product.eventId = event.id
        product.name = "測試商品"
        product.price = NSDecimalNumber(value: 100)
        product.stock = 10
        product.categoryId = category.id
        product.isDisabled = false
        product.sortOrder = 0
        product.createdAt = Date()
        product.category = category
        return product
    }

    private func makeTransaction(
        in event: CDEventEntity,
        selling product: CDProductEntity,
        category: CDCategoryEntity
    ) {
        let transaction = CDTransactionEntity(context: context)
        transaction.id = UUID()
        transaction.eventId = event.id
        transaction.eventTitle = event.title
        transaction.currency = "TWD"
        transaction.totalAmount = NSDecimalNumber(value: 100)
        transaction.paymentMethod = PaymentMethod.cash.rawValue
        transaction.timestamp = Date()
        transaction.items = [
            .mock(productId: product.id, categoryId: category.id, quantity: 1)
        ]
        transaction.event = event
    }

    // MARK: - ⭐ D6：守衛只拒絕，不偷偷做別的事

    func testDeletingProductWithTransactionsFailsAndDoesNotDisableIt() throws {
        let event = makeEvent()
        let category = makeCategory(in: event)
        let product = makeProduct(in: category, event: event)
        makeTransaction(in: event, selling: product, category: category)
        try context.save()

        let productId = product.id
        let result = repository.deleteProduct(productId)

        // 必須是誠實失敗
        guard case .failed = result else {
            return XCTFail("有交易的商品應回傳 .failed，實際為 \(result)")
        }

        // ⭐ 最關鍵的一條：改動前這裡會被靜默設成 isDisabled = true，
        //    呼叫端以為刪掉了、實際上資料還在而且狀態被改了
        XCTAssertFalse(product.isDisabled, "守衛不可以偷偷把商品改成停用")
        XCTAssertFalse(product.isDeleted, "商品不該被刪除")
        XCTAssertNotEqual(product.syncStatus, SyncStatus.pending.rawValue,
                          "純粹被拒絕的刪除不該產生同步負擔")
    }

    func testDeletingProductWithoutTransactionsSucceeds() throws {
        let event = makeEvent()
        let category = makeCategory(in: event)
        let product = makeProduct(in: category, event: event)
        try context.save()

        let productId = product.id
        let result = repository.deleteProduct(productId)

        guard case .deleted = result else {
            return XCTFail("沒有交易的商品應可刪除，實際為 \(result)")
        }

        let request: NSFetchRequest<CDProductEntity> = CDProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", productId as CVarArg)
        XCTAssertEqual(try context.fetch(request).count, 0)
    }

    func testDeletingUnknownProductFails() {
        let result = repository.deleteProduct(UUID())

        guard case .failed = result else {
            return XCTFail("找不到的商品應回傳 .failed，實際為 \(result)")
        }
    }

    // MARK: - 交易索引用的是快照

    func testOtherEventsTransactionsDoNotBlockDeletion() throws {
        // 另一個場次賣過「同一個 productId」不該擋住這個場次的刪除
        let eventA = makeEvent()
        let categoryA = makeCategory(in: eventA)
        let productA = makeProduct(in: categoryA, event: eventA)

        let eventB = makeEvent()
        let categoryB = makeCategory(in: eventB)
        let productB = makeProduct(in: categoryB, event: eventB)
        makeTransaction(in: eventB, selling: productB, category: categoryB)

        try context.save()

        let result = repository.deleteProduct(productA.id)

        guard case .deleted = result else {
            return XCTFail("別的場次的交易不該擋住刪除，實際為 \(result)")
        }
    }

    // MARK: - 連帶刪除庫存異動

    func testDeletingProductAlsoRemovesItsInventoryChanges() throws {
        let event = makeEvent()
        let category = makeCategory(in: event)
        let product = makeProduct(in: category, event: event)

        let change = CDInventoryChangeEntity(context: context)
        change.id = UUID()
        change.productId = product.id
        change.change = 10
        change.reason = InventoryChangeReason.purchase.rawValue
        change.timestamp = Date()
        change.event = event
        change.product = product
        try context.save()

        _ = repository.deleteProduct(product.id)

        let request: NSFetchRequest<CDInventoryChangeEntity> = CDInventoryChangeEntity.fetchRequest()
        XCTAssertEqual(try context.fetch(request).count, 0, "商品的庫存異動應一併消失，不留孤兒")
    }
}

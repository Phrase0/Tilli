//
//  AtomicLedgerWriteTests.swift
//  TilliTests
//
//  結帳、作廢、商品新增／編輯：庫存異動紀錄與庫存（及交易／作廢紀錄／商品）在同一次存檔完成（成功時只存檔 1 次）；
//  存檔失敗時一筆都不留、庫存不變。存檔失敗的做法：建好 Repository 後，在 context 塞一個缺必填欄位、
//  不屬於任何場次的類別（不能用場次：EventRepository 會讀出所有場次，缺 id 的場次轉 model 會當掉）。
//

import XCTest
import CoreData
@testable import Tilli

final class AtomicLedgerWriteTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext { container.viewContext }

    private let eventId = UUID()
    private let categoryId = UUID()
    private let productId = UUID()
    private let userId = "guest"

    override func setUp() {
        super.setUp()
        container = TestStore.makeInMemoryContainer()
        seed()
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    /// 一個場次、一個類別、一個庫存 10 的商品
    private func seed() {
        let event = CDEventEntity(context: context)
        event.id = eventId
        event.title = "測試場次"
        event.startDate = Date()
        event.createdAt = Date()
        event.currency = "TWD"
        event.dateType = EventDateType.single.rawValue

        let category = CDCategoryEntity(context: context)
        category.id = categoryId
        category.name = "甜點"
        category.createdAt = Date()
        category.isDisabled = false
        category.event = event

        let product = CDProductEntity(context: context)
        product.id = productId
        product.eventId = eventId
        product.categoryId = categoryId
        product.name = "大福"
        product.price = 100
        product.stock = 10
        product.category = category

        try! context.save()
    }

    /// 讓下一次 save 失敗：缺 id、name 等必填欄位的孤兒類別。要在建好 Repository 之後呼叫
    private func poisonContext() {
        _ = CDCategoryEntity(context: context)
    }

    /// 執行 `body` 期間 context 存檔的次數（「同一次存檔」= 1）
    private func saveCount<R>(_ body: () -> R) -> (result: R, saves: Int) {
        var saves = 0
        let token = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave, object: context, queue: nil
        ) { _ in saves += 1 }
        defer { NotificationCenter.default.removeObserver(token) }
        let result = body()
        return (result, saves)
    }

    private func count<T: NSManagedObject>(_ type: T.Type) -> Int {
        let request = NSFetchRequest<T>(entityName: String(describing: type))
        return (try? context.count(for: request)) ?? -1
    }

    private func stock() -> Int {
        context.refreshAllObjects()
        let request: NSFetchRequest<CDProductEntity> = CDProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", productId as CVarArg)
        return Int(try! context.fetch(request).first!.stock)
    }

    private func checkoutRecord(quantity: Int = 2) -> CheckoutRecorder.Record {
        CheckoutRecorder.makeRecord(
            event: .mock(id: eventId),
            items: [SummaryItemModel.mock(productId: productId, price: 100, quantity: quantity)],
            bundleDeductions: [],
            appliedDiscounts: [],
            totalAmount: Decimal(100 * quantity),
            paymentMethod: .cash,
            occurredAt: nil,
            now: Date()
        )
    }

    // MARK: - 結帳

    func testRecordCheckoutSavesTransactionChangesAndStockTogether() {
        let record = checkoutRecord()
        let repository = EventRepository(container: container)
        let (saved, saves) = saveCount { repository.recordCheckout(record, stockUpdates: [productId: 8], userId: userId) }

        XCTAssertTrue(saved)
        XCTAssertEqual(saves, 1, "交易、異動、庫存要在同一次存檔")
        XCTAssertEqual(count(CDTransactionEntity.self), 1)
        XCTAssertEqual(count(CDInventoryChangeEntity.self), 1)
        XCTAssertEqual(stock(), 8)
    }

    func testRecordCheckoutLeavesNothingWhenSaveFails() {
        let repository = EventRepository(container: container)
        poisonContext()
        let saved = repository.recordCheckout(checkoutRecord(), stockUpdates: [productId: 8], userId: userId)

        XCTAssertFalse(saved)
        XCTAssertEqual(count(CDTransactionEntity.self), 0)
        XCTAssertEqual(count(CDInventoryChangeEntity.self), 0)
        XCTAssertEqual(stock(), 10)
    }

    func testRecordCheckoutRejectsMissingEvent() {
        var record = checkoutRecord()
        record = CheckoutRecorder.Record(
            transaction: { var t = record.transaction; t.eventId = UUID(); return t }(),
            inventoryChanges: record.inventoryChanges
        )
        let saved = EventRepository(container: container)
            .recordCheckout(record, stockUpdates: [productId: 8], userId: userId)

        XCTAssertFalse(saved)
        XCTAssertEqual(count(CDTransactionEntity.self), 0)
        XCTAssertEqual(count(CDInventoryChangeEntity.self), 0)
        XCTAssertEqual(stock(), 10)
    }

    // MARK: - 作廢

    /// 先結帳一筆賣 2 個（庫存 10 → 8），回傳交易與它的銷售異動
    private func checkedOut() -> CheckoutRecorder.Record {
        let record = checkoutRecord()
        XCTAssertTrue(EventRepository(container: container)
            .recordCheckout(record, stockUpdates: [productId: 8], userId: userId))
        return record
    }

    private func voidRecord(for checkout: CheckoutRecorder.Record, restock: Bool) -> VoidRecorder.Record {
        let result = VoidRecorder.makeRecord(
            transaction: checkout.transaction,
            salesChanges: checkout.inventoryChanges,
            voidIndex: TransactionVoidIndex(voids: []),
            reason: .inputError,
            note: "",
            restock: restock,
            now: Date()
        )
        guard case .success(let record) = result else { fatalError("makeRecord 不應拒絕") }
        return record
    }

    func testRecordVoidSavesVoidRestockChangesAndStockTogether() {
        let checkout = checkedOut()
        let repository = EventRepository(container: container)
        let record = voidRecord(for: checkout, restock: true)
        let (saved, saves) = saveCount { repository.recordVoid(record, stockUpdates: [productId: 10], userId: userId) }

        XCTAssertTrue(saved)
        XCTAssertEqual(saves, 1, "作廢紀錄、回流異動、庫存要在同一次存檔")
        XCTAssertEqual(count(CDTransactionVoidEntity.self), 1)
        XCTAssertEqual(count(CDInventoryChangeEntity.self), 2)
        XCTAssertEqual(stock(), 10)
    }

    func testRecordVoidLeavesNothingWhenSaveFails() {
        let checkout = checkedOut()
        let repository = EventRepository(container: container)
        poisonContext()
        let saved = repository.recordVoid(voidRecord(for: checkout, restock: true), stockUpdates: [productId: 10], userId: userId)

        XCTAssertFalse(saved)
        XCTAssertEqual(count(CDTransactionVoidEntity.self), 0)
        XCTAssertEqual(count(CDInventoryChangeEntity.self), 1, "只剩結帳時的銷售異動")
        XCTAssertEqual(stock(), 8)
    }

    func testRecordVoidRejectsAlreadyVoidedTransaction() {
        let checkout = checkedOut()
        let repository = EventRepository(container: container)
        XCTAssertTrue(repository.recordVoid(voidRecord(for: checkout, restock: false), stockUpdates: [:], userId: userId))

        let saved = repository.recordVoid(voidRecord(for: checkout, restock: true), stockUpdates: [productId: 10], userId: userId)

        XCTAssertFalse(saved)
        XCTAssertEqual(count(CDTransactionVoidEntity.self), 1)
        XCTAssertEqual(count(CDInventoryChangeEntity.self), 1)
        XCTAssertEqual(stock(), 8)
    }

    // MARK: - 商品新增／編輯

    private func newProduct(stock: Int) -> ProductModel {
        .mock(eventId: eventId, name: "銅鑼燒", stock: stock, categoryId: categoryId)
    }

    private func purchase(of id: UUID, _ amount: Int) -> InventoryChangeModel {
        InventoryChangeModel(productId: id, change: amount, reason: .purchase, customReason: nil, timestamp: Date())
    }

    func testAddProductSavesProductAndInitialChangeTogether() {
        let product = newProduct(stock: 5)
        let repository = ProductRepository(container: container)
        let (saved, saves) = saveCount {
            repository.addProduct(to: categoryId, productModel: product, initialChange: purchase(of: product.id, 5), userId: userId)
        }

        XCTAssertTrue(saved)
        XCTAssertEqual(saves, 1, "商品與初始異動要在同一次存檔")
        XCTAssertEqual(count(CDProductEntity.self), 2)
        XCTAssertEqual(count(CDInventoryChangeEntity.self), 1)
    }

    func testAddProductLeavesNothingWhenSaveFails() {
        let repository = ProductRepository(container: container)
        poisonContext()
        let product = newProduct(stock: 5)
        let saved = repository.addProduct(
            to: categoryId, productModel: product, initialChange: purchase(of: product.id, 5), userId: userId
        )

        XCTAssertFalse(saved)
        XCTAssertEqual(count(CDProductEntity.self), 1)
        XCTAssertEqual(count(CDInventoryChangeEntity.self), 0)
    }

    func testUpdateProductSavesStockAndChangeTogether() {
        let edited = ProductModel.mock(id: productId, eventId: eventId, name: "大福", stock: 13, categoryId: categoryId)
        let repository = ProductRepository(container: container)
        let (result, saves) = saveCount {
            repository.updateProduct(productId, productModel: edited, stockChange: purchase(of: productId, 3), userId: userId)
        }

        XCTAssertEqual(result, .updated)
        XCTAssertEqual(saves, 1, "商品與庫存異動要在同一次存檔")
        XCTAssertEqual(count(CDInventoryChangeEntity.self), 1)
        XCTAssertEqual(stock(), 13)
    }

    func testUpdateProductLeavesNothingWhenSaveFails() {
        let repository = ProductRepository(container: container)
        poisonContext()
        let edited = ProductModel.mock(id: productId, eventId: eventId, name: "大福", stock: 13, categoryId: categoryId)
        let result = repository.updateProduct(
            productId, productModel: edited, stockChange: purchase(of: productId, 3), userId: userId
        )

        XCTAssertEqual(result, .failed(String.localized("productSaveFailed")))
        XCTAssertEqual(count(CDInventoryChangeEntity.self), 0)
        XCTAssertEqual(stock(), 10)
    }
}

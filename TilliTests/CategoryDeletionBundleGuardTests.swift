//
//  CategoryDeletionBundleGuardTests.swift
//  TilliTests
//
//  刪除類別會連帶刪除底下商品（Cascade），所以類別內有商品被套餐／組合引用時，
//  類別也不可刪除（設計 §4.3），且要告訴使用者是哪些套餐。
//

import XCTest
import CoreData
@testable import Tilli

final class CategoryDeletionBundleGuardTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var repository: EventRepository!
    private var context: NSManagedObjectContext { container.viewContext }

    override func setUp() {
        super.setUp()
        container = TestStore.makeInMemoryContainer()
        repository = EventRepository(container: container)
    }

    override func tearDown() {
        repository = nil
        container = nil
        super.tearDown()
    }

    // MARK: - Fixtures（直接建 entity，避開 repository 的 Auth 依賴）

    private func makeEvent(bundles: [BundleModel]) throws -> CDEventEntity {
        let event = CDEventEntity(context: context)
        event.id = UUID()
        event.title = "測試場次"
        event.startDate = Date()
        event.createdAt = Date()
        event.currency = "TWD"
        event.dateType = EventDateType.single.rawValue
        event.bundlesData = try JSONEncoder().encode(bundles)
        return event
    }

    private func makeCategory(name: String, in event: CDEventEntity) -> CDCategoryEntity {
        let category = CDCategoryEntity(context: context)
        category.id = UUID()
        category.name = name
        category.createdAt = Date()
        category.isDisabled = false
        category.sortOrder = 0
        category.event = event
        return category
    }

    @discardableResult
    private func makeProduct(id: UUID = UUID(), in category: CDCategoryEntity, event: CDEventEntity) -> CDProductEntity {
        let product = CDProductEntity(context: context)
        product.id = id
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

    private func count<T: NSManagedObject>(_ type: T.Type, id: UUID) throws -> Int {
        let request = NSFetchRequest<T>(entityName: String(describing: type))
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try context.count(for: request)
    }

    /// 「甜點」底下的大福被雙拼套餐引用；「飲料」底下的商品沒有被引用
    private func makeFixture() throws -> (event: CDEventEntity, referenced: CDCategoryEntity, free: CDCategoryEntity, productId: UUID) {
        let productId = UUID()
        let bundle = BundleModel.fixedMock(name: "雙拼套餐", price: 150, productIds: [productId, UUID()])
        let event = try makeEvent(bundles: [bundle])
        let dessert = makeCategory(name: "甜點", in: event)
        makeProduct(id: productId, in: dessert, event: event)
        let drink = makeCategory(name: "飲料", in: event)
        makeProduct(in: drink, event: event)
        try context.save()
        return (event, dessert, drink, productId)
    }

    // MARK: - Repository 守衛

    func testUpdateEventKeepsCategoryWhoseProductIsUsedByBundle() throws {
        let fixture = try makeFixture()
        // 刪除後 entity 的屬性就讀不到了，先把 id 記下來
        let referencedId = fixture.referenced.id
        let freeId = fixture.free.id
        var model = EventModel(entity: fixture.event)
        model.categories = []   // 使用者把兩個類別都刪了

        repository.updateEvent(model)

        XCTAssertEqual(try count(CDCategoryEntity.self, id: referencedId), 1, "被引用的類別應保留")
        XCTAssertEqual(try count(CDProductEntity.self, id: fixture.productId), 1, "被套餐引用的商品不可被連帶刪除")
        XCTAssertEqual(try count(CDCategoryEntity.self, id: freeId), 0, "未被引用的類別照常刪除")
    }

    // MARK: - 設定頁回饋

    func testDeleteActionOnCategoryUsedByBundleShowsBundleNamesAndDoesNotRemove() throws {
        let fixture = try makeFixture()
        let viewModel = AddEventViewModel(eventToEdit: EventModel(entity: fixture.event))
        viewModel.updateDataManagers(
            transactionDataManager: TransactionRepository(container: container),
            productRepository: ProductRepository(container: container)
        )
        let category = try XCTUnwrap(viewModel.categories.first { $0.id == fixture.referenced.id })

        viewModel.handleDeleteAction(for: category)

        XCTAssertTrue(viewModel.showAlert)
        XCTAssertNil(viewModel.categoryPendingDeletion, "是拒絕提醒，不是刪除確認")
        XCTAssertTrue(viewModel.alertMessage.contains("雙拼套餐"), "訊息應列出套餐名，實際為 \(viewModel.alertMessage)")
        XCTAssertTrue(viewModel.categories.contains { $0.id == category.id }, "類別不可被移除")
    }

    func testDeleteActionOnUnreferencedCategoryStillAsksForConfirmation() throws {
        let fixture = try makeFixture()
        let viewModel = AddEventViewModel(eventToEdit: EventModel(entity: fixture.event))
        viewModel.updateDataManagers(
            transactionDataManager: TransactionRepository(container: container),
            productRepository: ProductRepository(container: container)
        )
        let category = try XCTUnwrap(viewModel.categories.first { $0.id == fixture.free.id })

        viewModel.handleDeleteAction(for: category)

        XCTAssertEqual(viewModel.categoryPendingDeletion, category.id, "有商品 → 照舊跳刪除確認")
    }
}

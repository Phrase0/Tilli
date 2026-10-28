//
//  BundleGuardTests.swift
//  TilliTests
//
//  商品被套餐／組合引用時：禁止刪除、禁止改成會讓套餐比原價貴的價格。
//

import XCTest
import CoreData
@testable import Tilli

final class BundleGuardTests: XCTestCase {

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

    private func makeEvent(bundles: [BundleModel] = []) throws -> CDEventEntity {
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

    private func makeProduct(name: String = "測試商品", price: Int = 100,
                             in category: CDCategoryEntity, event: CDEventEntity) -> CDProductEntity {
        let product = CDProductEntity(context: context)
        product.id = UUID()
        product.eventId = event.id
        product.name = name
        product.price = NSDecimalNumber(value: price)
        product.stock = 10
        product.categoryId = category.id
        product.isDisabled = false
        product.sortOrder = 0
        product.createdAt = Date()
        product.category = category
        return product
    }

    // MARK: - 刪除守衛

    func testDeletingProductUsedByBundleIsRejectedAndListsBundleNames() throws {
        let productId = UUID()
        let bundle = BundleModel.fixedMock(name: "雙拼套餐", price: 150, productIds: [productId, UUID()])
        let event = try makeEvent(bundles: [bundle])
        let category = makeCategory(in: event)
        let product = makeProduct(in: category, event: event)
        product.id = productId
        try context.save()

        let result = repository.deleteProduct(productId)

        guard case .failed(let message) = result else {
            return XCTFail("被套餐引用的商品應回傳 .failed，實際為 \(result)")
        }
        XCTAssertTrue(message.contains("雙拼套餐"), "訊息應列出套餐名，實際為 \(message)")
        XCTAssertFalse(product.isDeleted)
        let request: NSFetchRequest<CDProductEntity> = CDProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", productId as CVarArg)
        XCTAssertEqual(try context.fetch(request).count, 1, "商品應仍存在")
    }

    func testDeletingUnreferencedProductWithoutTransactionsStillSucceeds() throws {
        let other = BundleModel.fixedMock(name: "別的套餐", productIds: [UUID(), UUID()])
        let event = try makeEvent(bundles: [other])
        let category = makeCategory(in: event)
        let product = makeProduct(in: category, event: event)
        try context.save()

        let result = repository.deleteProduct(product.id)

        guard case .deleted = result else {
            return XCTFail("未被引用且無交易的商品應可刪除，實際為 \(result)")
        }
    }

    // MARK: - 改價守衛

    /// 兩個 100 元商品組成 150 元固定套餐（上限 200）
    private func makeFixedBundleFixture() throws -> (CDProductEntity, CDProductEntity) {
        let a = UUID(), b = UUID()
        let bundle = BundleModel.fixedMock(name: "雙拼套餐", price: 150, productIds: [a, b])
        let event = try makeEvent(bundles: [bundle])
        let category = makeCategory(in: event)
        let productA = makeProduct(name: "A", price: 100, in: category, event: event)
        productA.id = a
        let productB = makeProduct(name: "B", price: 100, in: category, event: event)
        productB.id = b
        try context.save()
        return (productA, productB)
    }

    func testPriceChangeBreakingBundleIsRejectedAndNothingIsWritten() throws {
        let (productA, _) = try makeFixedBundleFixture()
        var edited = productA.toModel()
        edited.name = "改名了"
        edited.price = 20   // 20 + 100 = 120 < 150，套餐會比原價貴

        let result = repository.updateProduct(productA.id, productModel: edited)

        guard case .failed(let message) = result else {
            return XCTFail("違規改價應回傳 .failed，實際為 \(result)")
        }
        XCTAssertTrue(message.contains("雙拼套餐"))
        XCTAssertEqual(productA.price, NSDecimalNumber(value: 100), "價格不可被寫入")
        XCTAssertEqual(productA.name, "A", "名稱也不可被寫入")
    }

    func testPriceChangeWithinLimitUpdates() throws {
        let (productA, _) = try makeFixedBundleFixture()
        var edited = productA.toModel()
        edited.price = 60   // 60 + 100 = 160 >= 150

        let result = repository.updateProduct(productA.id, productModel: edited)

        XCTAssertEqual(result, .updated)
        XCTAssertEqual(productA.price, NSDecimalNumber(value: 60))
    }
}

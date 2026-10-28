//
//  BundleModelPersistenceTests.swift
//  TilliTests
//
//  對應 docs/superpowers/specs/2026-10-27-bundles-design.md §3、§6（第 5 批 5.1）。
//

import XCTest
import CoreData
@testable import Tilli

final class BundleModelPersistenceTests: XCTestCase {

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

    @discardableResult
    private func makeEvent() -> CDEventEntity {
        let event = CDEventEntity(context: context)
        event.id = UUID()
        event.title = "測試場次"
        event.startDate = Date()
        event.createdAt = Date()
        event.currency = "TWD"
        event.dateType = EventDateType.single.rawValue
        try? context.save()
        return event
    }

    // MARK: - Codable

    func testFixedAndChooseAnyBundlesRoundTripThroughJSON() throws {
        let bundles = [
            BundleModel.fixedMock(name: "套餐"),
            BundleModel.comboMock(name: "任選", count: 2)
        ]
        let data = try JSONEncoder().encode(bundles)
        let decoded = try JSONDecoder().decode([BundleModel].self, from: data)
        XCTAssertEqual(decoded, bundles)
        XCTAssertEqual(decoded[0].kind, .fixed)
        XCTAssertEqual(decoded[1].kind, .chooseAny)
        XCTAssertEqual(decoded[1].requiredCount, 2)
        XCTAssertEqual(decoded[0].requiredCount, decoded[0].productIds.count)
    }

    func testBundleDecodesWithDefaultsWhenOptionalKeysMissing() throws {
        let id = UUID()
        let pid = UUID()
        let json = """
        {"id":"\(id.uuidString)","name":"套餐","price":100,"mode":{"fixed":{}},"productIds":["\(pid.uuidString)"]}
        """
        let bundle = try JSONDecoder().decode(BundleModel.self, from: Data(json.utf8))
        XCTAssertFalse(bundle.isDisabled)
        XCTAssertNil(bundle.imageURL)
        XCTAssertEqual(bundle.createdAt, Date(timeIntervalSince1970: 0))
        XCTAssertEqual(bundle.productIds, [pid])
    }

    func testSummaryItemDecodesMissingBundleFieldsAsZeroAndNil() throws {
        let json = """
        {"id":"\(UUID().uuidString)","productId":"\(UUID().uuidString)","name":"A","price":50,
         "categoryId":"\(UUID().uuidString)","category":"C","quantity":2,"timestamp":0,
         "allocatedDiscount":5}
        """
        let item = try JSONDecoder().decode(SummaryItemModel.self, from: Data(json.utf8))
        XCTAssertEqual(item.bundleDiscount, 0)
        XCTAssertNil(item.bundleKind)
        XCTAssertEqual(item.allocatedDiscount, 5)
    }

    // MARK: - Persistence

    func testSaveBundlesPersistsAndEventModelReadsThemBack() {
        let event = makeEvent()
        let bundles = [BundleModel.fixedMock(), BundleModel.comboMock()]

        XCTAssertTrue(repository.saveBundles(bundles, forEventId: event.id))

        XCTAssertEqual(EventModel(entity: event).bundles, bundles)
        XCTAssertEqual(event.syncStatus, "pending")
    }

    func testSaveBundlesReturnsFalseForUnknownEvent() {
        XCTAssertFalse(repository.saveBundles([BundleModel.fixedMock()], forEventId: UUID()))
    }

    func testSaveBundlesReturnsFalseAndKeepsExistingBundlesWhenEncodingFails() {
        let event = makeEvent()
        let bundles = [BundleModel.fixedMock(name: "原本的套餐")]
        XCTAssertTrue(repository.saveBundles(bundles, forEventId: event.id))

        // NaN 日期無法編成 JSON → encode 失敗
        var broken = BundleModel.fixedMock(name: "壞掉的套餐")
        broken.createdAt = Date(timeIntervalSinceReferenceDate: .nan)

        XCTAssertFalse(repository.saveBundles([broken], forEventId: event.id))
        XCTAssertEqual(EventModel(entity: event).bundles, bundles, "編碼失敗不可清掉既有套餐")
    }

    func testUpdateEventDoesNotOverwriteBundles() {
        let event = makeEvent()
        let bundles = [BundleModel.fixedMock()]
        XCTAssertTrue(repository.saveBundles(bundles, forEventId: event.id))

        var stale = EventModel(entity: event)
        stale.bundles = []
        stale.title = "改名後"
        repository.updateEvent(stale)

        XCTAssertEqual(event.title, "改名後", "updateEvent 必須真的執行過，否則這個測試沒意義")
        XCTAssertEqual(EventModel(entity: event).bundles, bundles)
    }

    func testInventoryChangeBundleFieldsRoundTripThroughEntity() {
        let bundleId = UUID()
        let model = InventoryChangeModel(
            productId: UUID(), change: -1, reason: .salesOut, timestamp: Date(),
            bundleId: bundleId, bundleName: "午餐套餐"
        )
        let entity = CDInventoryChangeEntity(context: context)
        entity.update(from: model, context: context)

        let back = entity.toModel()
        XCTAssertEqual(back.bundleId, bundleId)
        XCTAssertEqual(back.bundleName, "午餐套餐")
    }
}

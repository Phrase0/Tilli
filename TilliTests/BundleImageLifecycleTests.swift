//
//  BundleImageLifecycleTests.swift
//  TilliTests
//
//  套餐照片（本機檔）的生命週期：存檔失敗要還原、刪除場次要一起刪。
//

import XCTest
import CoreData
@testable import Tilli

@MainActor
final class BundleImageLifecycleTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var bundleIds: [UUID] = []

    override func setUp() async throws {
        try await super.setUp()
        container = TestStore.makeInMemoryContainer()
    }

    override func tearDown() async throws {
        bundleIds.forEach { BundleImageStore.delete(for: $0) }
        bundleIds = []
        container = nil
        try await super.tearDown()
    }

    private func solidImage(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    private func trackedBundle(name: String = "下午茶套餐") -> BundleModel {
        let bundle = BundleModel.fixedMock(name: name, price: 50, productIds: [])
        bundleIds.append(bundle.id)
        return bundle
    }

    // MARK: - 編輯存檔失敗 → 照片還原

    func testEditSaveFailureRestoresPreviousPhoto() throws {
        let daifuku = ProductModel.mock(name: "大福", price: 40)
        let matcha = ProductModel.mock(name: "抹茶", price: 60)
        var bundle = trackedBundle()
        bundle.productIds = [daifuku.id, matcha.id]
        XCTAssertTrue(BundleImageStore.save(solidImage(.red), for: bundle.id))
        let original = try XCTUnwrap(BundleImageStore.data(for: bundle.id))

        // 場次不在資料庫 → saveBundles 失敗
        var event = EventModel.mock()
        event.bundles = [bundle]
        let viewModel = BundleFormViewModel(kind: .fixed, editing: bundle, event: event, products: [daifuku, matcha])
        viewModel.image = solidImage(.blue)

        XCTAssertFalse(viewModel.save(using: EventRepository(container: container)))
        XCTAssertTrue(viewModel.showSaveFailedAlert)
        XCTAssertEqual(BundleImageStore.data(for: bundle.id), original, "原本的照片要還原")
    }

    func testEditSaveFailureRestoresPhotoThatWasRemoved() throws {
        let daifuku = ProductModel.mock(name: "大福", price: 40)
        let matcha = ProductModel.mock(name: "抹茶", price: 60)
        var bundle = trackedBundle()
        bundle.productIds = [daifuku.id, matcha.id]
        XCTAssertTrue(BundleImageStore.save(solidImage(.red), for: bundle.id))
        let original = try XCTUnwrap(BundleImageStore.data(for: bundle.id))

        var event = EventModel.mock()
        event.bundles = [bundle]
        let viewModel = BundleFormViewModel(kind: .fixed, editing: bundle, event: event, products: [daifuku, matcha])
        viewModel.image = nil

        XCTAssertFalse(viewModel.save(using: EventRepository(container: container)))
        XCTAssertEqual(BundleImageStore.data(for: bundle.id), original, "移除照片後存檔失敗，照片要回來")
    }

    func testRestoreNilDeletesPhoto() {
        let bundle = trackedBundle()
        XCTAssertTrue(BundleImageStore.save(solidImage(.red), for: bundle.id))

        BundleImageStore.restore(nil, for: bundle.id)

        XCTAssertNil(BundleImageStore.data(for: bundle.id))
        XCTAssertNil(BundleImageStore.load(for: bundle.id))
    }

    // MARK: - 刪除場次 → 套餐照片一起刪

    func testDeletingEventDeletesItsBundlePhotos() throws {
        let withPhoto = trackedBundle(name: "有照片")
        let otherEventBundle = trackedBundle(name: "別的場次")
        XCTAssertTrue(BundleImageStore.save(solidImage(.red), for: withPhoto.id))
        XCTAssertTrue(BundleImageStore.save(solidImage(.green), for: otherEventBundle.id))

        let context = container.viewContext
        func makeEvent(bundles: [BundleModel]) throws -> UUID {
            let event = CDEventEntity(context: context)
            event.id = UUID()
            event.title = "場次"
            event.startDate = Date()
            event.createdAt = Date()
            event.currency = "TWD"
            event.dateType = EventDateType.single.rawValue
            event.bundlesData = try JSONEncoder().encode(bundles)
            return event.id
        }
        let eventId = try makeEvent(bundles: [withPhoto])
        _ = try makeEvent(bundles: [otherEventBundle])
        try context.save()

        EventRepository(container: container).deleteEvent(eventId)

        XCTAssertNil(BundleImageStore.data(for: withPhoto.id))
        XCTAssertNotNil(BundleImageStore.data(for: otherEventBundle.id), "別的場次的照片不能被刪")
    }
}

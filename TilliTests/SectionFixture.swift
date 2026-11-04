//
//  SectionFixture.swift
//  TilliTests
//
//  chip 列相關測試共用的場次資料：甜點（大福、抹茶、紅豆）、飲料（4 樣）、季節（1 樣），
//  套餐「下午茶套餐」（大福＋抹茶）、組合「任選兩個」。
//

import XCTest
import CoreData
@testable import Tilli

@MainActor
struct SectionFixture {
    let container: NSPersistentContainer
    let eventId: UUID
    var categoryIds: [String: UUID] = [:]
    var productIds: [String: UUID] = [:]
    let teaSetId = UUID()
    let comboId = UUID()

    init() throws {
        container = TestStore.makeInMemoryContainer()
        eventId = UUID()
        let context = container.viewContext

        let event = CDEventEntity(context: context)
        event.id = eventId
        event.title = "測試場次"
        event.startDate = Date()
        event.createdAt = Date()
        event.currency = "TWD"
        event.dateType = EventDateType.single.rawValue

        let layout: [(String, [String])] = [
            ("甜點", ["大福", "抹茶", "紅豆"]),
            ("飲料", ["紅茶", "綠茶", "奶茶", "咖啡"]),
            ("季節", ["草莓"]),
        ]
        for (order, (categoryName, products)) in layout.enumerated() {
            let category = CDCategoryEntity(context: context)
            category.id = UUID()
            category.name = categoryName
            category.createdAt = Date()
            category.isDisabled = false
            category.sortOrder = Int16(order)
            category.event = event
            categoryIds[categoryName] = category.id
            for (index, name) in products.enumerated() {
                let product = CDProductEntity(context: context)
                product.id = UUID()
                product.eventId = eventId
                product.name = name
                product.price = 50
                product.stock = 10
                product.categoryId = category.id
                product.isDisabled = false
                product.sortOrder = Int16(index)
                product.createdAt = Date(timeIntervalSince1970: TimeInterval(index))
                product.category = category
                productIds[name] = product.id
            }
        }

        let bundles: [BundleModel] = [
            .mock(id: teaSetId, name: "下午茶套餐", price: 90, mode: .fixed, productIds: [productIds["大福"]!, productIds["抹茶"]!]),
            .mock(id: comboId, name: "任選兩個", price: 80, mode: .chooseAny(count: 2), productIds: [productIds["紅茶"]!, productIds["綠茶"]!]),
        ]
        event.bundlesData = try JSONEncoder().encode(bundles)
        try context.save()
    }

    func makeDataSource() throws -> EventDataSource {
        let event = try XCTUnwrap(EventRepository(container: container).fetchEvent(by: eventId))
        let dataSource = EventDataSource(event: event)
        dataSource.attach(
            eventRepository: EventRepository(container: container),
            productRepository: ProductRepository(container: container),
            transactionRepository: TransactionRepository(container: container),
            inventoryChangeRepository: InventoryChangeRepository(container: container)
        )
        return dataSource
    }

    func setProductDisabled(_ name: String, _ disabled: Bool) throws {
        let request = CDProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", productIds[name]! as CVarArg)
        let entity = try XCTUnwrap(container.viewContext.fetch(request).first)
        entity.isDisabled = disabled
        try container.viewContext.save()
    }
}

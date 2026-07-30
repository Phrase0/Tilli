import Foundation
@testable import Tilli

extension EventModel {
    static func mock(
        id: UUID = UUID(),
        title: String = "測試場次",
        startDate: Date = Date(),
        endDate: Date? = nil,
        dateType: EventDateType = .single,
        categories: [CategoryModel] = [],
        createdAt: Date = Date(),
        currency: String = "TWD",
        discounts: [DiscountModel] = []
    ) -> EventModel {
        EventModel(
            id: id,
            title: title,
            startDate: startDate,
            endDate: endDate,
            dateType: dateType,
            categories: categories,
            createdAt: createdAt,
            currency: currency,
            discounts: discounts
        )
    }
}

extension ProductModel {
    static func mock(
        id: UUID = UUID(),
        eventId: UUID = UUID(),
        name: String = "測試商品",
        price: Decimal = 100,
        stock: Int = 10,
        categoryId: UUID = UUID(),
        categoryName: String = "預設分類",
        note: String? = nil,
        imageData: Data? = nil,
        isDisabled: Bool = false,
        imageURL: String? = nil,
        createdAt: Date = Date()
    ) -> ProductModel {
        ProductModel(
            id: id,
            eventId: eventId,
            name: name,
            price: price,
            stock: stock,
            categoryId: categoryId,
            categoryName: categoryName,
            note: note,
            imageData: imageData,
            isDisabled: isDisabled,
            imageURL: imageURL,
            createdAt: createdAt
        )
    }
}

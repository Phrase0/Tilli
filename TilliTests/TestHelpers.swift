//
//  TestHelpers.swift
//  TilliTests
//
//  Created by Peiyun on 2025/9/12.
//

import Foundation
import CoreData
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
            note: note,
            imageData: imageData,
            isDisabled: isDisabled,
            imageURL: imageURL,
            createdAt: createdAt
        )
    }
}

extension CategoryModel {
    static func mock(
        id: UUID = UUID(),
        name: String = "測試類別",
        products: [ProductModel] = [],
        isDisabled: Bool = false,
        sortOrder: Int = 0
    ) -> CategoryModel {
        CategoryModel(
            id: id,
            name: name,
            products: products,
            createdAt: Date(),
            isDisabled: isDisabled,
            sortOrder: sortOrder
        )
    }
}

extension SummaryItemModel {
    static func mock(
        id: UUID = UUID(),
        productId: UUID = UUID(),
        name: String = "測試商品",
        price: Decimal = 100,
        categoryId: UUID = UUID(),
        category: String = "測試類別",
        quantity: Int = 1,
        timestamp: Date = Date()
    ) -> SummaryItemModel {
        SummaryItemModel(
            id: id,
            productId: productId,
            name: name,
            price: price,
            categoryId: categoryId,
            category: category,
            quantity: quantity,
            timestamp: timestamp
        )
    }
}

extension TransactionModel {
    static func mock(
        id: UUID = UUID(),
        eventId: UUID = UUID(),
        eventTitle: String = "測試場次",
        currency: String = "TWD",
        items: [SummaryItemModel] = [],
        totalAmount: Decimal = 0,
        paymentMethod: PaymentMethod = .cash,
        timestamp: Date = Date(),
        occurredAt: Date? = nil,
        appliedDiscounts: [AppliedDiscount] = []
    ) -> TransactionModel {
        TransactionModel(
            id: id,
            eventId: eventId,
            eventTitle: eventTitle,
            currency: currency,
            items: items,
            totalAmount: totalAmount,
            paymentMethod: paymentMethod,
            timestamp: timestamp,
            occurredAt: occurredAt,
            appliedDiscounts: appliedDiscounts
        )
    }
}

extension DiscountModel {
    /// 百分比折扣：`value` 是折掉的百分比（10 = 打九折）
    static func percentage(_ value: Decimal, id: UUID = UUID()) -> DiscountModel {
        DiscountModel(id: id, type: .percentage, value: value)
    }

    /// 定額折扣：`value` 是折抵的金額
    static func amount(_ value: Decimal, id: UUID = UUID()) -> DiscountModel {
        DiscountModel(id: id, type: .amount, value: value)
    }
}

// MARK: - CoreData

enum TestStore {
    /// 每次呼叫都建立一個獨立的 in-memory container，測試之間不互相污染
    static func makeInMemoryContainer() -> NSPersistentContainer {
        PersistenceController(inMemory: true).container
    }
}

extension AppliedDiscount {
    static func mock(
        discountId: UUID = UUID(),
        type: DiscountType = .amount,
        value: Decimal = 10,
        amount: Decimal = 10
    ) -> AppliedDiscount {
        AppliedDiscount(discountId: discountId, type: type, value: value, amount: amount)
    }
}

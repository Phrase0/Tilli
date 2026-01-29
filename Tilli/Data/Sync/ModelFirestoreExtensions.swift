//
//  ModelFirestoreExtensions.swift
//  Tilli
//
//  Created for CoreData + Firebase Sync
//  為所有 Domain Model 提供 Firestore 轉換功能
//

import Foundation
import FirebaseFirestore

// MARK: - SessionModel + Firestore

extension SessionModel {
    /// 轉換為 Firestore Dictionary
    func toFirestoreData(userId: String) -> [String: Any] {
        var data: [String: Any] = [
            "id": id.uuidString,
            "userId": userId,
            "title": title,
            "startDate": Timestamp(date: startDate),
            "dateType": dateType.rawValue,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: Date()),
            "currency": currency
        ]

        if let endDate = endDate {
            data["endDate"] = Timestamp(date: endDate)
        }

        // discounts 轉為 JSON String
        if !discounts.isEmpty,
           let jsonData = try? JSONEncoder().encode(discounts),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            data["discountsData"] = jsonString
        }

        return data
    }

    /// 從 Firestore Document 建立
    init?(from document: [String: Any]) {
        guard let idString = document["id"] as? String,
              let id = UUID(uuidString: idString),
              let title = document["title"] as? String,
              let startDateTimestamp = document["startDate"] as? Timestamp,
              let dateTypeString = document["dateType"] as? String,
              let dateType = SessionDateType(rawValue: dateTypeString),
              let createdAtTimestamp = document["createdAt"] as? Timestamp,
              let currency = document["currency"] as? String
        else { return nil }

        self.id = id
        self.title = title
        self.startDate = startDateTimestamp.dateValue()
        self.endDate = (document["endDate"] as? Timestamp)?.dateValue()
        self.dateType = dateType
        self.createdAt = createdAtTimestamp.dateValue()
        self.currency = currency
        self.categories = [] // Categories 從獨立 collection 載入

        // discountsData JSON String → [DiscountModel]
        if let jsonString = document["discountsData"] as? String,
           let jsonData = jsonString.data(using: .utf8),
           let discounts = try? JSONDecoder().decode([DiscountModel].self, from: jsonData) {
            self.discounts = discounts
        } else {
            self.discounts = []
        }
    }
}

// MARK: - CategoryModel + Firestore

extension CategoryModel {
    /// 轉換為 Firestore Dictionary
    func toFirestoreData(userId: String, sessionId: UUID) -> [String: Any] {
        return [
            "id": id.uuidString,
            "userId": userId,
            "sessionId": sessionId.uuidString,
            "name": name,
            "sortOrder": sortOrder,
            "isDisabled": isDisabled,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: Date())
        ]
    }

    /// 從 Firestore Document 建立
    init?(from document: [String: Any]) {
        guard let idString = document["id"] as? String,
              let id = UUID(uuidString: idString),
              let name = document["name"] as? String,
              let createdAtTimestamp = document["createdAt"] as? Timestamp
        else { return nil }

        self.id = id
        self.name = name
        self.createdAt = createdAtTimestamp.dateValue()
        self.sortOrder = document["sortOrder"] as? Int ?? 0
        self.isDisabled = document["isDisabled"] as? Bool ?? false
        self.products = [] // Products 從獨立 collection 載入

        // sessionId
        if let sessionIdString = document["sessionId"] as? String {
            self.sessionId = UUID(uuidString: sessionIdString)
        }
    }
}

// MARK: - ProductModel + Firestore

extension ProductModel {
    /// 轉換為 Firestore Dictionary
    func toFirestoreData(userId: String) -> [String: Any] {
        var data: [String: Any] = [
            "id": id.uuidString,
            "userId": userId,
            "sessionId": sessionId.uuidString,
            "categoryId": categoryId.uuidString,
            "categoryName": categoryName,
            "name": name,
            "price": decimalToCents(price),  // Decimal → Integer（分）
            "stock": stock,
            "isDisabled": isDisabled,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: Date())
        ]

        if let note = note {
            data["note"] = note
        }

        if let imageURL = imageURL {
            data["imageURL"] = imageURL
        }

        // imageData 不上傳，改用 imageURL（需先上傳到 Storage 取得 URL）

        return data
    }

    /// 從 Firestore Document 建立
    init?(from document: [String: Any]) {
        guard let idString = document["id"] as? String,
              let id = UUID(uuidString: idString),
              let sessionIdString = document["sessionId"] as? String,
              let sessionId = UUID(uuidString: sessionIdString),
              let categoryIdString = document["categoryId"] as? String,
              let categoryId = UUID(uuidString: categoryIdString),
              let categoryName = document["categoryName"] as? String,
              let name = document["name"] as? String,
              let priceCents = document["price"] as? Int,
              let stock = document["stock"] as? Int
        else { return nil }

        self.id = id
        self.sessionId = sessionId
        self.categoryId = categoryId
        self.categoryName = categoryName
        self.name = name
        self.price = centsToDecimal(priceCents)  // Integer（分）→ Decimal
        self.stock = stock
        self.note = document["note"] as? String
        self.isDisabled = document["isDisabled"] as? Bool ?? false
        self.imageData = nil  // 圖片從 URL 下載後再填入
        self.imageURL = document["imageURL"] as? String

        // createdAt
        if let createdAtTimestamp = document["createdAt"] as? Timestamp {
            self.createdAt = createdAtTimestamp.dateValue()
        } else {
            self.createdAt = Date()
        }
    }
}

// MARK: - TransactionModel + Firestore

extension TransactionModel {
    /// 轉換為 Firestore Dictionary
    func toFirestoreData(userId: String) -> [String: Any] {
        var data: [String: Any] = [
            "id": id.uuidString,
            "userId": userId,
            "sessionId": sessionId.uuidString,
            "sessionTitle": sessionTitle,
            "currency": currency,
            "totalAmount": decimalToCents(totalAmount),  // Decimal → Integer（分）
            "paymentMethod": paymentMethod.rawValue,
            "timestamp": Timestamp(date: timestamp)
        ]

        if let occurredAt = occurredAt {
            data["occurredAt"] = Timestamp(date: occurredAt)
        }

        if let discountType = discountType {
            data["discountType"] = discountType.rawValue
        }

        if let discountValue = discountValue {
            data["discountValue"] = decimalToCents(discountValue)
        }

        // items 轉為 JSON String
        if let jsonData = try? JSONEncoder().encode(items),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            data["itemsData"] = jsonString
        }

        return data
    }

    /// 從 Firestore Document 建立
    init?(from document: [String: Any]) {
        guard let idString = document["id"] as? String,
              let id = UUID(uuidString: idString),
              let sessionIdString = document["sessionId"] as? String,
              let sessionId = UUID(uuidString: sessionIdString),
              let sessionTitle = document["sessionTitle"] as? String,
              let currency = document["currency"] as? String,
              let totalAmountCents = document["totalAmount"] as? Int,
              let paymentMethodString = document["paymentMethod"] as? String,
              let paymentMethod = PaymentMethod(rawValue: paymentMethodString),
              let timestampValue = document["timestamp"] as? Timestamp
        else { return nil }

        self.id = id
        self.sessionId = sessionId
        self.sessionTitle = sessionTitle
        self.currency = currency
        self.totalAmount = centsToDecimal(totalAmountCents)
        self.paymentMethod = paymentMethod
        self.timestamp = timestampValue.dateValue()
        self.occurredAt = (document["occurredAt"] as? Timestamp)?.dateValue()

        // discountType & discountValue
        if let discountTypeString = document["discountType"] as? String {
            self.discountType = DiscountType(rawValue: discountTypeString)
        } else {
            self.discountType = nil
        }

        if let discountValueCents = document["discountValue"] as? Int {
            self.discountValue = centsToDecimal(discountValueCents)
        } else {
            self.discountValue = nil
        }

        // itemsData JSON String → [SummaryItemModel]
        if let jsonString = document["itemsData"] as? String,
           let jsonData = jsonString.data(using: .utf8),
           let items = try? JSONDecoder().decode([SummaryItemModel].self, from: jsonData) {
            self.items = items
        } else {
            self.items = []
        }
    }
}

// MARK: - InventoryChangeModel + Firestore

extension InventoryChangeModel {
    /// 轉換為 Firestore Dictionary
    func toFirestoreData(userId: String, sessionId: UUID) -> [String: Any] {
        var data: [String: Any] = [
            "id": id.uuidString,
            "userId": userId,
            "sessionId": sessionId.uuidString,
            "productId": productId.uuidString,
            "change": change,
            "reason": reason.rawValue,
            "timestamp": Timestamp(date: timestamp)
        ]

        if let customReason = customReason {
            data["customReason"] = customReason
        }

        if let transactionId = transactionId {
            data["transactionId"] = transactionId.uuidString
        }

        return data
    }

    /// 從 Firestore Document 建立
    init?(from document: [String: Any]) {
        guard let idString = document["id"] as? String,
              let id = UUID(uuidString: idString),
              let productIdString = document["productId"] as? String,
              let productId = UUID(uuidString: productIdString),
              let change = document["change"] as? Int,
              let reasonString = document["reason"] as? String,
              let reason = InventoryChangeReason(rawValue: reasonString),
              let timestampValue = document["timestamp"] as? Timestamp
        else { return nil }

        self.id = id
        self.productId = productId
        self.change = change
        self.reason = reason
        self.customReason = document["customReason"] as? String
        self.timestamp = timestampValue.dateValue()

        if let transactionIdString = document["transactionId"] as? String {
            self.transactionId = UUID(uuidString: transactionIdString)
        } else {
            self.transactionId = nil
        }

        // sessionId
        if let sessionIdString = document["sessionId"] as? String {
            self.sessionId = UUID(uuidString: sessionIdString)
        }
    }
}

// MARK: - DiscountModel + Firestore

extension DiscountModel {
    /// 轉換為 Firestore Dictionary
    func toFirestoreData() -> [String: Any] {
        return [
            "id": id.uuidString,
            "type": type.rawValue,
            "value": decimalToCents(value)  // Decimal → Integer（分）
        ]
    }

    /// 從 Firestore Document 建立
    init?(from document: [String: Any]) {
        guard let idString = document["id"] as? String,
              let id = UUID(uuidString: idString),
              let typeString = document["type"] as? String,
              let type = DiscountType(rawValue: typeString),
              let valueCents = document["value"] as? Int
        else { return nil }

        self.id = id
        self.type = type
        self.value = centsToDecimal(valueCents)  // Integer（分）→ Decimal
    }
}

// MARK: - SummaryItemModel + Firestore

extension SummaryItemModel {
    /// 轉換為 Firestore Dictionary
    func toFirestoreData() -> [String: Any] {
        return [
            "id": id.uuidString,
            "productId": productId.uuidString,
            "name": name,
            "price": decimalToCents(price),  // Decimal → Integer（分）
            "categoryId": categoryId.uuidString,
            "category": category,
            "quantity": quantity,
            "timestamp": Timestamp(date: timestamp)
        ]
    }

    /// 從 Firestore Document 建立
    init?(from document: [String: Any]) {
        guard let idString = document["id"] as? String,
              let id = UUID(uuidString: idString),
              let productIdString = document["productId"] as? String,
              let productId = UUID(uuidString: productIdString),
              let name = document["name"] as? String,
              let priceCents = document["price"] as? Int,
              let categoryIdString = document["categoryId"] as? String,
              let categoryId = UUID(uuidString: categoryIdString),
              let category = document["category"] as? String,
              let quantity = document["quantity"] as? Int,
              let timestampValue = document["timestamp"] as? Timestamp
        else { return nil }

        self.id = id
        self.productId = productId
        self.name = name
        self.price = centsToDecimal(priceCents)  // Integer（分）→ Decimal
        self.categoryId = categoryId
        self.category = category
        self.quantity = quantity
        self.timestamp = timestampValue.dateValue()
    }
}

// MARK: - QRCodeModel + Firestore

extension QRCodeModel {
    /// 轉換為 Firestore Dictionary
    func toFirestoreData(userId: String) -> [String: Any] {
        var data: [String: Any] = [
            "id": id.uuidString,
            "userId": userId,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: Date())
        ]

        if let url = imageURL {
            data["imageURL"] = url
        }

        // imageData 不上傳（改用 imageURL 指向 Storage）
        return data
    }

    /// 從 Firestore Document 建立
    init?(from document: [String: Any]) {
        guard let idString = document["id"] as? String,
              let id = UUID(uuidString: idString),
              let createdAtTimestamp = document["createdAt"] as? Timestamp
        else { return nil }

        self.id = id
        self.createdAt = createdAtTimestamp.dateValue()
        self.imageURL = document["imageURL"] as? String
        self.imageData = nil  // 圖片從 URL 下載後再填入
    }
}

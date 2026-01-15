//
//  TestDataGenerator.swift
//  Tilli
//
//  測試用資料生成器 - 測試完成後可直接刪除此檔案
//  Created for testing RevenueTrendView
//

import Foundation

/// 測試資料生成器
/// 使用方式：在 App 啟動時呼叫 TestDataGenerator.generateTestData(sessionDataManager:)
class TestDataGenerator {
    
    private static let testSessionId =
        UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    private static let didGenerateKey = "didGenerateTestCafeSession"

    private static let testMulti30DaysSessionId =
        UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!

    private static let didGenerateMulti30DaysKey =
        "didGenerateTestMulti30DaysCafeSession"
    
    /// 生成測試資料：永久場次 + 類別 + 產品 + 跨多月交易 + 庫存異動
    /// 如果已存在測試場次則跳過
    static func generateTestData(
        sessionDataManager: SessionDataManager,
        inventoryChangeRepository: InventoryChangeRepository
    ) {
        
        // 已產生過就直接跳過
        if UserDefaults.standard.bool(forKey: didGenerateKey) {
            print("⏭️ 測試資料已產生（UserDefaults），跳過")
            return
        }
        
        // 檢查是否已有測試資料，有的話就跳過
        if sessionDataManager.sessions.contains(where: { $0.title == "測試咖啡廳（永久）" }) {
            print("⏭️ 測試資料已存在，跳過生成")
            return
        }
        let sessionId = testSessionId
        let category1Id = UUID()
        let category2Id = UUID()
        let category3Id = UUID()

        // 產品 IDs
        let product1Id = UUID()
        let product2Id = UUID()
        let product3Id = UUID()
        let product4Id = UUID()
        let product5Id = UUID()

        // 類別 1: 飲品
        let product1 = ProductModel(
            id: product1Id,
            sessionId: sessionId,
            name: "拿鐵咖啡",
            price: 120,
            stock: 100,
            categoryId: category1Id,
            categoryName: "飲品",
            note: nil,
            imageData: nil,
            isDisabled: false
        )

        let product2 = ProductModel(
            id: product2Id,
            sessionId: sessionId,
            name: "美式咖啡",
            price: 80,
            stock: 100,
            categoryId: category1Id,
            categoryName: "飲品",
            note: nil,
            imageData: nil,
            isDisabled: false
        )

        let category1 = CategoryModel(
            id: category1Id,
            name: "飲品",
            products: [product1, product2],
            createdAt: Date(),
            isDisabled: false,
            sortOrder: 0
        )

        // 類別 2: 甜點
        let product3 = ProductModel(
            id: product3Id,
            sessionId: sessionId,
            name: "提拉米蘇",
            price: 150,
            stock: 50,
            categoryId: category2Id,
            categoryName: "甜點",
            note: nil,
            imageData: nil,
            isDisabled: false
        )

        let product4 = ProductModel(
            id: product4Id,
            sessionId: sessionId,
            name: "巧克力蛋糕",
            price: 180,
            stock: 50,
            categoryId: category2Id,
            categoryName: "甜點",
            note: nil,
            imageData: nil,
            isDisabled: false
        )

        let category2 = CategoryModel(
            id: category2Id,
            name: "甜點",
            products: [product3, product4],
            createdAt: Date(),
            isDisabled: false,
            sortOrder: 1
        )

        // 類別 3: 輕食
        let product5 = ProductModel(
            id: product5Id,
            sessionId: sessionId,
            name: "三明治",
            price: 100,
            stock: 80,
            categoryId: category3Id,
            categoryName: "輕食",
            note: nil,
            imageData: nil,
            isDisabled: false
        )

        let category3 = CategoryModel(
            id: category3Id,
            name: "輕食",
            products: [product5],
            createdAt: Date(),
            isDisabled: false,
            sortOrder: 2
        )

        // 建立永久場次（從 3 個月前開始）
        let calendar = Calendar.current
        let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: Date())!
        let startDate = calendar.startOfDay(for: threeMonthsAgo)

        // TWD 折扣測試資料（8個：4個百分比 + 4個金額）
        let twdDiscounts: [DiscountModel] = [
            // 百分比折扣
            DiscountModel(type: .percentage, value: 5),
            DiscountModel(type: .percentage, value: 10),
            DiscountModel(type: .percentage, value: 15),
            DiscountModel(type: .percentage, value: 20),
            // 金額折扣（TWD 無小數）
            DiscountModel(type: .amount, value: 10),
            DiscountModel(type: .amount, value: 20),
            DiscountModel(type: .amount, value: 50),
            DiscountModel(type: .amount, value: 100)
        ]

        let session = SessionModel(
            id: sessionId,
            title: "測試咖啡廳（永久）",
            startDate: startDate,
            endDate: nil,  // 永久場次
            dateType: .permanent,
            categories: [category1, category2, category3],
            createdAt: Date(),
            currency: "TWD",
            discounts: twdDiscounts
        )

        // 新增場次
        sessionDataManager.addSession(session)

        // 產品資訊（ID, 名稱, 價格, 類別ID, 類別名稱, 初始庫存）
        let productsInfo: [(UUID, String, Decimal, UUID, String, Int)] = [
            (product1Id, "拿鐵咖啡", Decimal(120), category1Id, "飲品", 100),
            (product2Id, "美式咖啡", Decimal(80), category1Id, "飲品", 100),
            (product3Id, "提拉米蘇", Decimal(150), category2Id, "甜點", 50),
            (product4Id, "巧克力蛋糕", Decimal(180), category2Id, "甜點", 50),
            (product5Id, "三明治", Decimal(100), category3Id, "輕食", 80)
        ]

        // 生成初始庫存異動紀錄（進貨入庫）
        for productInfo in productsInfo {
            let initialChange = InventoryChangeModel(
                productId: productInfo.0,
                change: productInfo.5,
                reason: .purchase,
                customReason: nil,
                transactionId: nil,
                timestamp: startDate
            )
            inventoryChangeRepository.addChange(initialChange, sessionId: sessionId)
        }

        // 生成跨 3 個月的交易資料
        generateTransactions(
            sessionDataManager: sessionDataManager,
            inventoryChangeRepository: inventoryChangeRepository,
            sessionId: sessionId,
            sessionTitle: session.title,
            sessionCurrency: "TWD",
            startDate: startDate,
            products: productsInfo.map { ($0.0, $0.1, $0.2, $0.3, $0.4) },
            discounts: twdDiscounts
        )

        UserDefaults.standard.set(true, forKey: didGenerateKey)
        print("✅ 測試資料生成完成")
    }

    static func generate30DaysMultiCafeSession(
        sessionDataManager: SessionDataManager,
        inventoryChangeRepository: InventoryChangeRepository
    ) {
        if UserDefaults.standard.bool(forKey: didGenerateMulti30DaysKey) {
            return
        }

        let sessionId = testMulti30DaysSessionId

        let category1Id = UUID()
        let category2Id = UUID()
        let category3Id = UUID()

        let product1Id = UUID()
        let product2Id = UUID()
        let product3Id = UUID()
        let product4Id = UUID()
        let product5Id = UUID()

        // MARK: - 飲品（小數）
        let product1 = ProductModel(
            id: product1Id,
            sessionId: sessionId,
            name: "拿鐵咖啡",
            price: Decimal(string: "4.50")!,
            stock: 100,
            categoryId: category1Id,
            categoryName: "飲品",
            note: nil,
            imageData: nil,
            isDisabled: false
        )

        let product2 = ProductModel(
            id: product2Id,
            sessionId: sessionId,
            name: "美式咖啡",
            price: Decimal(string: "3.20")!,
            stock: 100,
            categoryId: category1Id,
            categoryName: "飲品",
            note: nil,
            imageData: nil,
            isDisabled: false
        )

        let category1 = CategoryModel(
            id: category1Id,
            name: "飲品",
            products: [product1, product2],
            createdAt: Date(),
            isDisabled: false,
            sortOrder: 0
        )

        // MARK: - 甜點（小數）
        let product3 = ProductModel(
            id: product3Id,
            sessionId: sessionId,
            name: "提拉米蘇",
            price: Decimal(string: "5.80")!,
            stock: 50,
            categoryId: category2Id,
            categoryName: "甜點",
            note: nil,
            imageData: nil,
            isDisabled: false
        )

        let product4 = ProductModel(
            id: product4Id,
            sessionId: sessionId,
            name: "巧克力蛋糕",
            price: Decimal(string: "6.40")!,
            stock: 50,
            categoryId: category2Id,
            categoryName: "甜點",
            note: nil,
            imageData: nil,
            isDisabled: false
        )

        let category2 = CategoryModel(
            id: category2Id,
            name: "甜點",
            products: [product3, product4],
            createdAt: Date(),
            isDisabled: false,
            sortOrder: 1
        )

        // MARK: - 輕食（小數）
        let product5 = ProductModel(
            id: product5Id,
            sessionId: sessionId,
            name: "三明治",
            price: Decimal(string: "4.75")!,
            stock: 80,
            categoryId: category3Id,
            categoryName: "輕食",
            note: nil,
            imageData: nil,
            isDisabled: false
        )

        let category3 = CategoryModel(
            id: category3Id,
            name: "輕食",
            products: [product5],
            createdAt: Date(),
            isDisabled: false,
            sortOrder: 2
        )

        // MARK: - 30 天多日場次
        let calendar = Calendar.current

        var dateComponents = DateComponents()
        dateComponents.year = 2025
        dateComponents.month = 12
        dateComponents.day = 1

        let startDate = calendar.startOfDay(
            for: calendar.date(from: dateComponents)!
        )
        let endDate = calendar.date(byAdding: .day, value: 29, to: startDate)!

        // EUR 折扣測試資料（8個：4個百分比 + 4個金額）
        let eurDiscounts: [DiscountModel] = [
            // 百分比折扣
            DiscountModel(type: .percentage, value: 5),
            DiscountModel(type: .percentage, value: 10),
            DiscountModel(type: .percentage, value: 15),
            DiscountModel(type: .percentage, value: 20),
            // 金額折扣（整數）
            DiscountModel(type: .amount, value: 1),
            DiscountModel(type: .amount, value: 2),
            DiscountModel(type: .amount, value: 5),
            DiscountModel(type: .amount, value: 10)
        ]

        let session = SessionModel(
            id: sessionId,
            title: "測試咖啡廳（30 天 / EUR）",
            startDate: startDate,
            endDate: endDate,
            dateType: .multi,
            categories: [category1, category2, category3],
            createdAt: Date(),
            currency: "EUR",
            discounts: eurDiscounts
        )

        sessionDataManager.addSession(session)

        // 產品資訊（ID, 名稱, 價格, 類別ID, 類別名稱, 初始庫存）
        let productsInfo: [(UUID, String, Decimal, UUID, String, Int)] = [
            (product1Id, "拿鐵咖啡", Decimal(string: "4.50")!, category1Id, "飲品", 100),
            (product2Id, "美式咖啡", Decimal(string: "3.20")!, category1Id, "飲品", 100),
            (product3Id, "提拉米蘇", Decimal(string: "5.80")!, category2Id, "甜點", 50),
            (product4Id, "巧克力蛋糕", Decimal(string: "6.40")!, category2Id, "甜點", 50),
            (product5Id, "三明治", Decimal(string: "4.75")!, category3Id, "輕食", 80)
        ]

        // 生成初始庫存異動紀錄（進貨入庫）
        for productInfo in productsInfo {
            let initialChange = InventoryChangeModel(
                productId: productInfo.0,
                change: productInfo.5,
                reason: .purchase,
                customReason: nil,
                transactionId: nil,
                timestamp: startDate
            )
            inventoryChangeRepository.addChange(initialChange, sessionId: sessionId)
        }

        // MARK: - 交易（沿用你原本的 generator）
        generateTransactions(
            sessionDataManager: sessionDataManager,
            inventoryChangeRepository: inventoryChangeRepository,
            sessionId: sessionId,
            sessionTitle: session.title,
            sessionCurrency: "EUR",
            startDate: startDate,
            products: productsInfo.map { ($0.0, $0.1, $0.2, $0.3, $0.4) },
            discounts: eurDiscounts
        )

        UserDefaults.standard.set(true, forKey: didGenerateMulti30DaysKey)
    }

    /// 生成跨多月的交易資料與庫存異動
    private static func generateTransactions(
        sessionDataManager: SessionDataManager,
        inventoryChangeRepository: InventoryChangeRepository,
        sessionId: UUID,
        sessionTitle: String,
        sessionCurrency: String,
        startDate: Date,
        products: [(UUID, String, Decimal, UUID, String)],
        discounts: [DiscountModel]
    ) {
        let calendar = Calendar.current
        let today = Date()

        // 從開始日期到今天，每天生成 1-5 筆交易
        var currentDate = startDate

        while currentDate <= today {
            // 每天隨機生成 8-10 筆交易
            let transactionCount = Int.random(in: 5...10)

            for _ in 0..<transactionCount {
                // 隨機選擇 1-3 個產品
                let itemCount = Int.random(in: 1...3)
                var items: [SummaryItemModel] = []
                var subtotal: Decimal = 0

                for _ in 0..<itemCount {
                    let product = products.randomElement()!
                    let quantity = Int.random(in: 1...3)

                    let item = SummaryItemModel(
                        id: UUID(),
                        productId: product.0,
                        name: product.1,
                        price: product.2,
                        categoryId: product.3,
                        category: product.4,
                        quantity: quantity,
                        timestamp: currentDate
                    )

                    items.append(item)
                    subtotal = MoneyHelper.add(subtotal, item.total)
                }

                // 約 30% 機率套用折扣
                var discountType: DiscountType? = nil
                var discountValue: Decimal? = nil
                var totalAmount = subtotal

                if !discounts.isEmpty && Int.random(in: 1...100) <= 30 {
                    let selectedDiscount = discounts.randomElement()!
                    discountType = selectedDiscount.type
                    discountValue = selectedDiscount.value

                    // 計算折扣後金額
                    switch selectedDiscount.type {
                    case .percentage:
                        let discountAmount = MoneyHelper.multiply(subtotal, selectedDiscount.value / 100)
                        totalAmount = MoneyHelper.subtract(subtotal, discountAmount)
                    case .amount:
                        totalAmount = max(MoneyHelper.subtract(subtotal, selectedDiscount.value), 0)
                    }
                }

                // 設定交易時間（當天的隨機時間，營業時間 9:00-21:00）
                let hour = Int.random(in: 9...20)
                let minute = Int.random(in: 0...59)
                let second = Int.random(in: 0...59)
                let transactionTime = calendar.date(
                    bySettingHour: hour,
                    minute: minute,
                    second: second,
                    of: currentDate
                ) ?? currentDate

                // 約 10% 機率為補記帳交易（occurredAt 設為 1-3 天前）
                var occurredAt: Date? = nil
                if Int.random(in: 1...100) <= 10 {
                    let daysAgo = Int.random(in: 1...3)
                    if let backdatedTime = calendar.date(byAdding: .day, value: -daysAgo, to: transactionTime),
                       backdatedTime >= startDate {
                        occurredAt = backdatedTime
                    }
                }

                let transaction = TransactionModel(
                    id: UUID(),
                    sessionId: sessionId,
                    sessionTitle: sessionTitle,
                    currency: sessionCurrency,
                    items: items,
                    totalAmount: totalAmount,
                    paymentMethod: Bool.random() ? .cash : .ePayment,
                    timestamp: transactionTime,
                    occurredAt: occurredAt,
                    discountType: discountType,
                    discountValue: discountValue
                )

                sessionDataManager.addTransaction(transaction)

                // 記錄庫存異動（銷售出庫）
                let changeTimestamp = occurredAt ?? transactionTime
                for item in items {
                    let inventoryChange = InventoryChangeModel(
                        productId: item.productId,
                        change: -item.quantity,
                        reason: .salesOut,
                        customReason: nil,
                        transactionId: transaction.id,
                        timestamp: changeTimestamp
                    )
                    inventoryChangeRepository.addChange(inventoryChange, sessionId: sessionId)
                }
            }

            // 下一天
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
    }

    /// 清除測試資料（根據場次名稱）
    static func clearTestData(sessionDataManager: SessionDataManager) {
        if let testSession = sessionDataManager.sessions.first(where: {
            $0.id == testSessionId
        }) {
            sessionDataManager.deleteSession(testSession.id)
        }
        UserDefaults.standard.removeObject(forKey: didGenerateKey)
        print("🗑️ 測試資料已清除")
    }

}

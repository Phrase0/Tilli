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

    /// 生成測試資料：永久場次 + 類別 + 產品 + 跨多月交易
    /// 如果已存在測試場次則跳過
    static func generateTestData(sessionDataManager: SessionDataManager) {
        
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
            isDisabled: false
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
            isDisabled: false
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
            isDisabled: false
        )

        // 建立永久場次（從 3 個月前開始）
        let calendar = Calendar.current
        let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: Date())!
        let startDate = calendar.startOfDay(for: threeMonthsAgo)

        let session = SessionModel(
            id: sessionId,
            title: "測試咖啡廳（永久）",
            startDate: startDate,
            endDate: nil,  // 永久場次
            dateType: .permanent,
            categories: [category1, category2, category3],
            createdAt: Date(),
            currency: "TWD"
        )

        // 新增場次
        sessionDataManager.addSession(session)

        // 生成跨 3 個月的交易資料
        generateTransactions(
            sessionDataManager: sessionDataManager,
            sessionId: sessionId,
            sessionTitle: session.title,
            startDate: startDate,
            products: [
                (product1Id, "拿鐵咖啡", Decimal(120), category1Id, "飲品"),
                (product2Id, "美式咖啡", Decimal(80), category1Id, "飲品"),
                (product3Id, "提拉米蘇", Decimal(150), category2Id, "甜點"),
                (product4Id, "巧克力蛋糕", Decimal(180), category2Id, "甜點"),
                (product5Id, "三明治", Decimal(100), category3Id, "輕食")
            ]
        )

        UserDefaults.standard.set(true, forKey: didGenerateKey)
        print("✅ 測試資料生成完成")
    }

    /// 生成跨多月的交易資料
    private static func generateTransactions(
        sessionDataManager: SessionDataManager,
        sessionId: UUID,
        sessionTitle: String,
        startDate: Date,
        products: [(UUID, String, Decimal, UUID, String)]
    ) {
        let calendar = Calendar.current
        let today = Date()

        // 從開始日期到今天，每天生成 1-5 筆交易
        var currentDate = startDate

        while currentDate <= today {
            // 每天隨機生成 8-20 筆交易
            let transactionCount = Int.random(in: 8...20)

            for i in 0..<transactionCount {
                // 隨機選擇 1-3 個產品
                let itemCount = Int.random(in: 1...3)
                var items: [SummaryItemModel] = []
                var totalAmount: Decimal = 0

                for _ in 0..<itemCount {
                    let product = products.randomElement()!
                    let quantity = Int.random(in: 1...3)
                    let discount = [0, 0, 0, 10, 20].randomElement()!  // 大部分無折扣

                    let item = SummaryItemModel(
                        id: UUID(),
                        productId: product.0,
                        name: product.1,
                        price: product.2,
                        categoryId: product.3,
                        category: product.4,
                        quantity: quantity,
                        discount: discount,
                        timestamp: currentDate
                    )

                    items.append(item)
                    totalAmount = MoneyHelper.add(totalAmount, item.total)
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

                let transaction = TransactionModel(
                    id: UUID(),
                    sessionId: sessionId,
                    sessionTitle: sessionTitle,
                    currency: "TWD",
                    items: items,
                    totalAmount: totalAmount,
                    paymentMethod: Bool.random() ? .cash : .ePayment,
                    timestamp: transactionTime
                )

                sessionDataManager.addTransaction(transaction)
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

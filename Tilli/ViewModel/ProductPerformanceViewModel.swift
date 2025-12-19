//
//  ProductPerformanceViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/15.
//

import SwiftUI
import Foundation

class ProductPerformanceViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var topProducts: [ProductPerformanceData] = []
    @Published var categoryAnalysis: [CategoryAnalysisData] = []
    @Published var salesInsights: SalesInsightsData = SalesInsightsData()
    @Published var isLoading = false
    @Published var showingExportAlert = false
    @Published var csvContent = ""
    
    // MARK: - Dependencies
    private var transactionDataManager: TransactionDataManager?
    private var sessionDataManager: SessionDataManager?
    @Binding var session: SessionModel
    
    // MARK: - Initialization
    init(session: Binding<SessionModel>) {
        self._session = session
    }
    
    // MARK: - DataManager 管理
    
    /// 更新 DataManager 引用
    func updateDataManagers(
        transactionDataManager: TransactionDataManager,
        sessionDataManager: SessionDataManager
    ) {
        self.transactionDataManager = transactionDataManager
        self.sessionDataManager = sessionDataManager
    }
    
    // MARK: - Public Methods

    /// 載入資料（支援時間範圍）
    func loadData(timeRange: ReportTimeRange? = nil) {
        guard transactionDataManager != nil else { return }

        isLoading = true

        Task {
            await MainActor.run {
                calculateTopProducts(timeRange: timeRange)
                calculateCategoryAnalysis(timeRange: timeRange)
                generateSalesInsights(timeRange: timeRange)
                isLoading = false
            }
        }
    }

    // MARK: - CSV Export Methods

    func generateTopProductsCSV() -> String {
        let currencyCode = session.currency
        var csvContent = "排名,商品名稱,類別,單價(\(currencyCode)),銷售數量,原價(\(currencyCode)),折扣金額(\(currencyCode)),實際營收(\(currencyCode)),貢獻率%\n"

        for product in topProducts {
            let rank = "\(product.rank)"
            let name = product.name.replacingOccurrences(of: ",", with: "，")
            let category = product.category.replacingOccurrences(of: ",", with: "，")
            let currency = Currency(rawValue: currencyCode) ?? .twd
            let unitPrice = MoneyHelper.toDisplayString(product.unitPrice, currency: currency)
            let salesCount = "\(product.salesCount)"
            let originalPrice = MoneyHelper.toDisplayString(product.originalPrice, currency: currency)
            let discount = "\(product.discount)"
            let actualRevenue = MoneyHelper.toDisplayString(product.actualRevenue, currency: currency)
            let contributionRate = "\(product.contributionRate)%"

            let row = "\(rank),\(name),\(category),\(unitPrice),\(salesCount),\(originalPrice),\(discount),\(actualRevenue),\(contributionRate)\n"
            csvContent += row
        }

        return csvContent
    }

    func generateCategoryAnalysisCSV() -> String {
        let currencyCode = session.currency
        var csvContent = "類別名稱,銷售金額(\(currencyCode)),佔比%\n"

        for category in categoryAnalysis {
            let name = category.name.replacingOccurrences(of: ",", with: "，")
            let currency = Currency(rawValue: currencyCode) ?? .twd
            let amount = MoneyHelper.toDisplayString(category.amount, currency: currency)
            let percentage = "\(category.percentage)%"

            let row = "\(name),\(amount),\(percentage)\n"
            csvContent += row
        }

        return csvContent
    }

    func createTopProductsCSVFileURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        // 過濾檔名中的非法字符（/ : 等）
        let safeTitle = session.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        let fileName = "熱門商品排行_\(safeTitle)_\(DateFormatter.csvFileDate.string(from: Date())).csv"
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            let csvContent = generateTopProductsCSV()
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Error creating Top Products CSV file: \(error)")
        }

        return fileURL
    }

    func createCategoryAnalysisCSVFileURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        // 過濾檔名中的非法字符（/ : 等）
        let safeTitle = session.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        let fileName = "類別銷售匯總_\(safeTitle)_\(DateFormatter.csvFileDate.string(from: Date())).csv"
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            let csvContent = generateCategoryAnalysisCSV()
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Error creating Category Analysis CSV file: \(error)")
        }

        return fileURL
    }

    func showExportSuccessAlert() {
        showingExportAlert = true
    }
}

// MARK: - Business Logic Calculations
private extension ProductPerformanceViewModel {
    
    /// 計算商品銷售排行榜（支援時間範圍）
    func calculateTopProducts(timeRange: ReportTimeRange? = nil) {
        guard let transactionDataManager = transactionDataManager else { return }

        // 根據時間範圍查詢交易
        let transactions: [TransactionModel]
        if let timeRange = timeRange {
            transactions = transactionDataManager.fetchTransactions(
                forSessionId: session.id,
                dateRange: timeRange.dateInterval
            )
        } else {
            transactions = transactionDataManager.fetchTransactions(forSessionId: session.id)
        }
        
        // 建立商品銷售統計字典
        var productStats: [UUID: ProductSalesStats] = [:]
        
        for transaction in transactions {
            for item in transaction.items {
                let productId = item.productId
                
                if productStats[productId] == nil {
                    productStats[productId] = ProductSalesStats(
                        productId: productId,
                        name: item.name,
                        category: item.category,
                        categoryId: item.categoryId
                    )
                }
                
                productStats[productId]?.addSale(
                    quantity: item.quantity,
                    unitPrice: item.price,
                    discount: item.discount,
                    actualTotal: item.total
                )
            }
        }
        
        // 計算總營收用於百分比計算
        let totalRevenue = productStats.values.reduce(0) { result, stats in
            MoneyHelper.add(result, stats.actualRevenue)
        }

        // 轉換為 ProductPerformanceData 並排序
        let performanceData = productStats.values.map { stats in
            // 分解複雜的貢獻率計算
            let contributionRate: Int
            if totalRevenue > 0 {
                let ratio = MoneyHelper.divide(stats.actualRevenue, totalRevenue)
                let percentage = MoneyHelper.multiply(ratio, Decimal(100))
                contributionRate = Int(MoneyHelper.toDouble(percentage))
            } else {
                contributionRate = 0
            }

            // 計算折扣金額
            let discountAmount = MoneyHelper.subtract(stats.originalRevenue, stats.actualRevenue)

            return ProductPerformanceData(
                productId: stats.productId,
                rank: 0, // 稍後設定
                name: stats.name,
                category: stats.category,
                salesCount: stats.totalQuantity,
                contributionRate: contributionRate,
                unitPrice: stats.unitPrice,
                originalPrice: stats.originalRevenue,
                discount: discountAmount,
                actualRevenue: stats.actualRevenue
            )
        }
        .sorted { $0.actualRevenue > $1.actualRevenue }
        .prefix(5)
        .enumerated()
        .map { index, data in
            var updatedData = data
            updatedData.rank = index + 1
            return updatedData
        }
        
        topProducts = Array(performanceData)
    }
    
    /// 計算分類銷售分析（支援時間範圍）
    func calculateCategoryAnalysis(timeRange: ReportTimeRange? = nil) {
        guard let transactionDataManager = transactionDataManager else { return }

        // 根據時間範圍查詢交易
        let transactions: [TransactionModel]
        if let timeRange = timeRange {
            transactions = transactionDataManager.fetchTransactions(
                forSessionId: session.id,
                dateRange: timeRange.dateInterval
            )
        } else {
            transactions = transactionDataManager.fetchTransactions(forSessionId: session.id)
        }
        
        // 建立分類銷售統計字典
        var categoryStats: [UUID: CategorySalesStats] = [:]
        
        for transaction in transactions {
            for item in transaction.items {
                let categoryId = item.categoryId
                
                if categoryStats[categoryId] == nil {
                    categoryStats[categoryId] = CategorySalesStats(
                        categoryId: categoryId,
                        name: item.category
                    )
                }
                
                categoryStats[categoryId]?.addSale(amount: item.total)
            }
        }
        
        // 計算總營收
        let totalRevenue = categoryStats.values.reduce(0) { MoneyHelper.add($0, $1.totalAmount) }
        
        // 轉換為 CategoryAnalysisData，先不設定顏色
        let analysisData = categoryStats.values.map { stats in
            // 分解複雜的百分比計算
            let percentage: Int
            if totalRevenue > 0 {
                let ratio = MoneyHelper.divide(stats.totalAmount, totalRevenue)
                let percentageDecimal = MoneyHelper.multiply(ratio, Decimal(100))
                percentage = Int(MoneyHelper.toDouble(percentageDecimal))
            } else {
                percentage = 0
            }

            return CategoryAnalysisData(
                name: stats.name,
                amount: stats.totalAmount,
                percentage: percentage,
                color: .gray  // 暫時設定為灰色
            )
        }
        .sorted { $0.amount > $1.amount }
        
        // 先設定 categoryAnalysis
        categoryAnalysis = analysisData
        
        // 然後重新設定正確的顏色
        categoryAnalysis = categoryAnalysis.enumerated().map { index, category in
            CategoryAnalysisData(
                name: category.name,
                amount: category.amount,
                percentage: category.percentage,
                color: getPredefinedColor(for: index)
            )
        }
    }
    
    /// 生成銷售洞察（支援時間範圍）
    func generateSalesInsights(timeRange: ReportTimeRange? = nil) {
        guard !topProducts.isEmpty, !categoryAnalysis.isEmpty else {
            salesInsights = SalesInsightsData()
            return
        }
        
        let bestProduct = topProducts.first!
        let bestCategory = categoryAnalysis.first!
        let lowestCategory = categoryAnalysis.last!
        
        let hotProductInsight = "熱銷商品"
        let hotProductDescription = "\(bestProduct.name)表現最佳，佔總銷售額 \(bestProduct.contributionRate)%"

        // 找出折扣最多的商品（使用相同的時間範圍）
        let highestDiscountProduct = findHighestDiscountProduct(timeRange: timeRange)
        let discountInsight = "折扣效果"
        let discountDescription = highestDiscountProduct.isEmpty ? 
            "\(bestCategory.name)類商品表現優異，銷售狀況良好" :
            "\(highestDiscountProduct.name)折扣最多，平均折扣達 \(highestDiscountProduct.averageDiscountRate)%"
        
        let suggestionInsight = "優化建議"
        let suggestionDescription = "可考慮增加\(lowestCategory.name)類商品的促銷活動"
        
        salesInsights = SalesInsightsData(
            hotProductTitle: hotProductInsight,
            hotProductDescription: hotProductDescription,
            discountTitle: discountInsight,
            discountDescription: discountDescription,
            suggestionTitle: suggestionInsight,
            suggestionDescription: suggestionDescription
        )
    }
    
    /// 找出折扣最多的商品
    private func findHighestDiscountProduct(timeRange: ReportTimeRange? = nil) -> (name: String, averageDiscountRate: Int, isEmpty: Bool) {
        guard let transactionDataManager = transactionDataManager else {
            return (name: "", averageDiscountRate: 0, isEmpty: true)
        }

        // 根據時間範圍查詢交易
        let transactions: [TransactionModel]
        if let timeRange = timeRange {
            transactions = transactionDataManager.fetchTransactions(
                forSessionId: session.id,
                dateRange: timeRange.dateInterval
            )
        } else {
            transactions = transactionDataManager.fetchTransactions(forSessionId: session.id)
        }

        // 建立商品折扣統計
        var productDiscountStats: [UUID: (name: String, totalDiscount: Decimal, totalQuantity: Int)] = [:]

        for transaction in transactions {
            for item in transaction.items {
                let productId = item.productId

                if productDiscountStats[productId] == nil {
                    productDiscountStats[productId] = (name: item.name, totalDiscount: 0, totalQuantity: 0)
                }

                // 計算該項目的折扣率
                let originalItemTotal = MoneyHelper.multiply(item.price, Decimal(item.quantity))
                let discountAmount = MoneyHelper.subtract(originalItemTotal, item.total)

                // 分解複雜的折扣率計算
                let discountRate: Decimal
                if originalItemTotal > 0 {
                    let discountRatio = MoneyHelper.divide(discountAmount, originalItemTotal)
                    discountRate = MoneyHelper.multiply(discountRatio, Decimal(100))
                } else {
                    discountRate = 0
                }

                // 避免重疊訪問，先讀取再更新
                if var stats = productDiscountStats[productId] {
                    stats.totalDiscount = MoneyHelper.add(stats.totalDiscount, discountRate)
                    stats.totalQuantity += 1
                    productDiscountStats[productId] = stats
                }
            }
        }

        // 找出平均折扣率最高的商品
        var maxDiscountProduct = ""
        var maxAverageDiscountRate = Decimal(0)

        for (_, stats) in productDiscountStats {
            let averageDiscountRate = stats.totalQuantity > 0 ?
                MoneyHelper.divide(stats.totalDiscount, Decimal(stats.totalQuantity)) : 0
            if averageDiscountRate > maxAverageDiscountRate {
                maxAverageDiscountRate = averageDiscountRate
                maxDiscountProduct = stats.name
            }
        }
        
        return (
            name: maxDiscountProduct,
            averageDiscountRate: Int(MoneyHelper.toDouble(maxAverageDiscountRate)), 
            isEmpty: maxDiscountProduct.isEmpty || maxAverageDiscountRate <= 0
        )
    }
    
    /// 根據索引獲取預設顏色
    private func getPredefinedColor(for index: Int) -> Color {
        let predefinedColors: [Color] = [
            .red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue, .indigo, .purple,
            .pink, .brown, Color(.systemRed), Color(.systemOrange), Color(.systemYellow), 
            Color(.systemGreen), Color(.systemMint), Color(.systemTeal), Color(.systemCyan),
            Color(.systemBlue), Color(.systemIndigo), Color(.systemPurple), Color(.systemPink),
            Color(.systemBrown), Color(.systemGray), Color(.systemGray2), Color(.systemGray3),
            Color(.systemGray4), Color(.systemGray5), Color(.systemGray6)
        ]
        
        if index < predefinedColors.count {
            return predefinedColors[index]
        } else {
            // 超出30個顏色時，使用deterministic方式生成顏色
            let hue = Double((index * 137) % 360) / 360.0  // 使用黃金角度確保顏色分散
            return Color(hue: hue, saturation: 0.7, brightness: 0.8)
        }
    }
}


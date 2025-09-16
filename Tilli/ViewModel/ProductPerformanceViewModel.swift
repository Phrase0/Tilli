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
    func loadData() {
        guard transactionDataManager != nil else { return }
        
        isLoading = true
        
        Task {
            await MainActor.run {
                calculateTopProducts()
                calculateCategoryAnalysis() 
                generateSalesInsights()
                isLoading = false
            }
        }
    }
    
    func refreshData() {
        loadData()
    }

    // MARK: - CSV Export Methods

    func generateTopProductsCSV() -> String {
        var csvContent = "排名,商品名稱,類別,單價,銷售數量,原價,折扣金額,實際營收,貢獻率%\n"

        for product in topProducts {
            let rank = "\(product.rank)"
            let name = product.name.replacingOccurrences(of: ",", with: "，")
            let category = product.category.replacingOccurrences(of: ",", with: "，")
            let unitPrice = "\(product.unitPrice)"
            let salesCount = "\(product.salesCount)"
            let originalPrice = "\(product.originalPrice)"
            let discount = "\(product.discount)"
            let actualRevenue = "\(product.actualRevenue)"
            let contributionRate = "\(product.contributionRate)%"

            let row = "\(rank),\(name),\(category),\(unitPrice),\(salesCount),\(originalPrice),\(discount),\(actualRevenue),\(contributionRate)\n"
            csvContent += row
        }

        return csvContent
    }

    func generateCategoryAnalysisCSV() -> String {
        var csvContent = "類別名稱,銷售金額,佔比%\n"

        for category in categoryAnalysis {
            let name = category.name.replacingOccurrences(of: ",", with: "，")
            let amount = "\(category.amount)"
            let percentage = "\(category.percentage)%"

            let row = "\(name),\(amount),\(percentage)\n"
            csvContent += row
        }

        return csvContent
    }

    func createTopProductsCSVFileURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "熱門商品排行_\(session.title)_\(DateFormatter.csvFileDate.string(from: Date())).csv"
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
        let fileName = "類別銷售匯總_\(session.title)_\(DateFormatter.csvFileDate.string(from: Date())).csv"
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
    
    /// 計算商品銷售排行榜
    func calculateTopProducts() {
        guard let transactionDataManager = transactionDataManager else { return }

        let transactions = transactionDataManager.fetchTransactions(forSessionId: session.id)
        
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
        let totalRevenue = productStats.values.reduce(0) { $0 + $1.actualRevenue }
        
        // 轉換為 ProductPerformanceData 並排序
        let performanceData = productStats.values.map { stats in
            let contributionRate = totalRevenue > 0 ? Int((stats.actualRevenue / totalRevenue) * 100) : 0
            
            return ProductPerformanceData(
                productId: stats.productId,
                rank: 0, // 稍後設定
                name: stats.name,
                category: stats.category,
                salesCount: stats.totalQuantity,
                contributionRate: contributionRate,
                unitPrice: Int(stats.unitPrice),
                originalPrice: Int(stats.originalRevenue),
                discount: Int(stats.originalRevenue - stats.actualRevenue),
                actualRevenue: Int(stats.actualRevenue)
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
    
    /// 計算分類銷售分析
    func calculateCategoryAnalysis() {
        guard let transactionDataManager = transactionDataManager else { return }

        let transactions = transactionDataManager.fetchTransactions(forSessionId: session.id)
        
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
        let totalRevenue = categoryStats.values.reduce(0) { $0 + $1.totalAmount }
        
        // 轉換為 CategoryAnalysisData，先不設定顏色
        let analysisData = categoryStats.values.map { stats in
            let percentage = totalRevenue > 0 ? Int((stats.totalAmount / totalRevenue) * 100) : 0
            
            return CategoryAnalysisData(
                name: stats.name,
                amount: Int(stats.totalAmount),
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
    
    /// 生成銷售洞察
    func generateSalesInsights() {
        guard !topProducts.isEmpty, !categoryAnalysis.isEmpty else {
            salesInsights = SalesInsightsData()
            return
        }
        
        let bestProduct = topProducts.first!
        let bestCategory = categoryAnalysis.first!
        let lowestCategory = categoryAnalysis.last!
        
        let hotProductInsight = "熱銷商品"
        let hotProductDescription = "\(bestProduct.name)表現最佳，佔總銷售額 \(bestProduct.contributionRate)%"
        
        // 找出折扣最多的商品
        let highestDiscountProduct = findHighestDiscountProduct()
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
    private func findHighestDiscountProduct() -> (name: String, averageDiscountRate: Int, isEmpty: Bool) {
        guard let transactionDataManager = transactionDataManager else {
            return (name: "", averageDiscountRate: 0, isEmpty: true)
        }

        let transactions = transactionDataManager.fetchTransactions(forSessionId: session.id)
        
        // 建立商品折扣統計
        var productDiscountStats: [UUID: (name: String, totalDiscount: Double, totalQuantity: Int)] = [:]
        
        for transaction in transactions {
            for item in transaction.items {
                let productId = item.productId
                
                if productDiscountStats[productId] == nil {
                    productDiscountStats[productId] = (name: item.name, totalDiscount: 0, totalQuantity: 0)
                }
                
                // 計算該項目的折扣率
                let originalItemTotal = item.price * Double(item.quantity)
                let discountAmount = originalItemTotal - item.total
                let discountRate = originalItemTotal > 0 ? (discountAmount / originalItemTotal) * 100 : 0
                
                productDiscountStats[productId]?.totalDiscount += discountRate
                productDiscountStats[productId]?.totalQuantity += 1
            }
        }
        
        // 找出平均折扣率最高的商品
        var maxDiscountProduct = ""
        var maxAverageDiscountRate = 0.0
        
        for (_, stats) in productDiscountStats {
            let averageDiscountRate = stats.totalQuantity > 0 ? stats.totalDiscount / Double(stats.totalQuantity) : 0
            if averageDiscountRate > maxAverageDiscountRate {
                maxAverageDiscountRate = averageDiscountRate
                maxDiscountProduct = stats.name
            }
        }
        
        return (
            name: maxDiscountProduct, 
            averageDiscountRate: Int(maxAverageDiscountRate), 
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


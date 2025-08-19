//
//  SessionDetailViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/8.
//

import SwiftUI

class SessionDetailViewModel: ObservableObject {
    
    @Binding var session: SessionModel
    @Published var categories: [CategoryModel] = []
    @Published var products: [ProductModel] = []
    @Published var quantities: [UUID: Int] = [:]
    @Published var selectedDiscounts: [UUID: Int] = [:]
    
    private var transactionDataManager: TransactionDataManager?
    
    init(session: Binding<SessionModel>) {
        self._session = session
    }
    
    // MARK: - 更新 DataManager 引用
    /// 更新 DataManager 引用
    func updateDataManagers(transactionDataManager: TransactionDataManager) {
         self.transactionDataManager = transactionDataManager
     }
    
    // MARK: - 交易檢查邏輯
    /// 檢查產品是否有交易紀錄
    func hasTransaction(for productId: UUID) -> Bool {
        guard let sessionId = session.id as UUID? else { return false }
        
        // 優先使用 TransactionDataManager 獲取最新的交易數據
        if let transactionManager = transactionDataManager {
            let transactions = transactionManager.fetchTransactions(forSessionId: sessionId)
            for transaction in transactions {
                for item in transaction.items {
                    if item.productId == productId {
                        return true
                    }
                }
            }
            return false
        }
        
        // 後備方案：使用初始的 session 數據
        for transaction in session.transactions {
            for item in transaction.items {
                if item.productId == productId {
                    return true
                }
            }
        }
        return false
    }

      
    func loadProducts(using productDataManager: ProductDataManager) {
        products = productDataManager.fetchProducts(forSessionId: session.id)
        categories = session.categories
    }
    
    func deleteProduct(_ product: ProductModel, using productDataManager: ProductDataManager) {
        productDataManager.deleteProduct(product)
        // 重新載入產品列表
        loadProducts(using: productDataManager)
        // 清除該產品的選擇狀態
        quantities.removeValue(forKey: product.id)
        selectedDiscounts.removeValue(forKey: product.id)
    }
    
    func increaseQuantity(for product: ProductModel) {
        let current = quantities[product.id, default: 0]
        if current < product.stock {
            quantities[product.id] = current + 1
        }
    }
    
    func decreaseQuantity(for product: ProductModel) {
        let current = quantities[product.id, default: 0]
        if current > 0 {
            quantities[product.id] = current - 1
        }
    }
    
    func toggleDiscount(for product: ProductModel, percent: Int) {
        if selectedDiscounts[product.id] == percent {
            selectedDiscounts[product.id] = nil
        } else {
            selectedDiscounts[product.id] = percent
        }
    }
    
    func isDiscountSelected(for product: ProductModel, percent: Int) -> Bool {
        selectedDiscounts[product.id] == percent
    }
    
    func quantity(for product: ProductModel) -> Int {
        quantities[product.id, default: 0]
    }
    
    func clearAllQuantities() {
        quantities.removeAll()
        selectedDiscounts.removeAll()
    }
    
    func totalAmount() -> Int {
        products.reduce(0) { result, product in
            let qty = quantities[product.id, default: 0]
            let discount = selectedDiscounts[product.id] ?? 0
            let discountedPrice = product.price * (1 - Double(discount) / 100)
            let roundedTotal = (discountedPrice * Double(qty)).rounded()
            return result + Int(roundedTotal)
        }
    }
    
    
    func selectedProductsWithQuantityAndDiscount() -> [SummaryItemModel] {
        products.compactMap { product in
            let qty = quantity(for: product)
            guard qty > 0 else { return nil }

            let discount = selectedDiscounts[product.id, default: 0]

            return SummaryItemModel(
                productId: product.id,
                name: product.name,
                price: product.price,
                categoryId: product.categoryId,
                category: product.categoryName,
                quantity: qty,
                discount: discount,
                timestamp: Date()
            )
        }
    }
}

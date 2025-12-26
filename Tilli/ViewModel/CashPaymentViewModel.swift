//
//  CashPaymentViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/30.
//

import Foundation
import SwiftUI

class CashPaymentViewModel: ObservableObject {

    let totalAmount: Decimal
    let session: SessionModel
    let summaryItems: [SummaryItemModel]
    let selectedDiscount: DiscountModel?

    @Published var receivedAmountText: String = ""
    @Published var errorMessage: String? = nil
    @Published var showDateWarning: Bool = false
    @Published var dateWarningMessage: String = ""
    
    var receivedAmount: Decimal {
        Decimal(string: receivedAmountText) ?? 0
    }

    /// 根據幣別四捨五入後的總額（用於驗證和找零計算）
    private var roundedTotalAmount: Decimal {
        let currency = Currency(rawValue: session.currency) ?? .twd
        let handler = NSDecimalNumberHandler(
            roundingMode: .plain,
            scale: Int16(currency.decimalPlaces),
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )
        return NSDecimalNumber(decimal: totalAmount)
            .rounding(accordingToBehavior: handler)
            .decimalValue
    }

    var change: Decimal {
        // 使用四捨五入後的總額計算找零
        MoneyHelper.subtract(receivedAmount, roundedTotalAmount)
    }

    var isAmountValid: Bool {
        // 使用四捨五入後的總額來驗證
        // 如果找零 >= 0，表示收到的金額足夠
        change >= 0
    }

    var currencyPlaceholder: String {
        let currency = Currency(rawValue: session.currency) ?? .twd
        return currency.symbol
    }

    /// 當前幣別
    var currentCurrency: Currency {
        return Currency(rawValue: session.currency) ?? .twd
    }

    /// 當前幣別是否支持小數點
    var supportsDecimal: Bool {
        return currentCurrency.decimalPlaces > 0
    }

    /// 當前幣別的小數位數
    var maxDecimalPlaces: Int {
        return currentCurrency.decimalPlaces
    }

    /// 驗證並格式化金額輸入
    func validateAndFormatAmount(_ input: String) -> String {
        // 移除非數字和小數點的字符
        let filtered = input.filter { $0.isNumber || $0 == "." }

        // 如果不支持小數點，移除所有小數點
        if !supportsDecimal {
            return filtered.filter { $0 != "." }
        }

        // 處理小數點
        let components = filtered.components(separatedBy: ".")

        // 如果沒有小數點或只有一個小數點
        if components.count <= 1 {
            return filtered
        }

        // 如果有多個小數點，只保留第一個
        if components.count > 2 {
            return components[0] + "." + components[1]
        }

        // 限制小數位數
        let integerPart = components[0]
        let decimalPart = components[1]

        if decimalPart.count > maxDecimalPlaces {
            let limitedDecimal = String(decimalPart.prefix(maxDecimalPlaces))
            return integerPart + "." + limitedDecimal
        }

        return filtered
    }

    init(totalAmount: Decimal, session: SessionModel, summaryItems: [SummaryItemModel], selectedDiscount: DiscountModel? = nil) {
        self.totalAmount = totalAmount
        self.session = session
        self.summaryItems = summaryItems
        self.selectedDiscount = selectedDiscount
    }

    /// 驗證交易日期是否在場次範圍內
    func validateTransactionDate() -> Bool {
        let validation = DateValidationHelper.validateTransactionDate(for: session)
        if !validation.isValid {
            dateWarningMessage = validation.errorMessage ?? "交易日期不在場次範圍內"
            showDateWarning = true
            return false
        }
        return true
    }

    func performCheckout(
        sessionDataManager: SessionDataManager,
        productRepository: ProductRepository
    ) -> SessionModel {

        // 批次更新產品庫存
        var stockUpdates: [UUID: Int] = [:]
        
        // 首先獲取所有相關產品
        let allProducts = productRepository.fetchProducts(forSessionId: session.id)
        let productDict = Dictionary(uniqueKeysWithValues: allProducts.map { ($0.id, $0) })
        
        // 準備批次更新數據
        for item in summaryItems {
            guard let currentProduct = productDict[item.productId] else {
                print("⚠️ 無法在 CoreData 中找到對應的 productId: \(item.productId)")
                continue
            }
            
            let newStock = max(currentProduct.stock - item.quantity, 0)
            stockUpdates[item.productId] = newStock
        }
        
        // 執行批次更新
        let success = productRepository.batchUpdateProductStock(stockUpdates)
        if !success {
            print("🔴 批次更新產品庫存失敗")
        }

        // 創建交易記錄
        let transaction = TransactionModel(
            sessionId: session.id,
            sessionTitle: session.title,
            currency: session.currency,
            items: summaryItems,
            totalAmount: totalAmount,
            paymentMethod: .cash,
            timestamp: Date(),
            discountType: selectedDiscount?.type,
            discountValue: selectedDiscount?.value
        )

        // 使用 SessionDataManager 添加交易記錄
        sessionDataManager.addTransaction(transaction)
        
        // 返回更新後的 session（通過 SessionDataManager 重新獲取）
        return sessionDataManager.fetchSession(by: session.id) ?? session
    }



}

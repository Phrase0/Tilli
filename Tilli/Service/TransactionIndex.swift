//
//  TransactionIndex.swift
//  Tilli
//
//  Created by Peiyun on 2026/9/12.
//
//  一次掃描全場次交易建立索引，回答「有沒有賣過」。
//

import Foundation

/// 「這個商品／類別曾經賣過東西嗎」的唯一答案來源。
///
/// 建立一次、掃一遍交易，之後所有查詢都是 `Set.contains` O(1)。
/// 每筆交易只 decode 一次（50 商品 × 500 交易也只要 500 次 decode）。
struct TransactionIndex {
    private let soldProductIds: Set<UUID>
    private let soldCategoryIds: Set<UUID>

    /// 該場次是否有任何交易（決定幣別能不能改等場次層級的判斷）
    let hasAnyTransaction: Bool

    /// 交易筆數
    let transactionCount: Int

    init(transactions: [TransactionModel]) {
        var products = Set<UUID>()
        var categories = Set<UUID>()
        for transaction in transactions {
            for item in transaction.items {
                products.insert(item.productId)
                categories.insert(item.categoryId)
            }
        }
        self.soldProductIds = products
        self.soldCategoryIds = categories
        self.hasAnyTransaction = !transactions.isEmpty
        self.transactionCount = transactions.count
    }

    /// 空索引（Repository 拿不到交易來源時的保守預設）
    static let empty = TransactionIndex(transactions: [])

    func hasTransaction(productId: UUID) -> Bool {
        soldProductIds.contains(productId)
    }

    /// ⭐ 一律用 `SummaryItem.categoryId` 快照判斷。
    ///
    /// 「這個類別曾經賣過東西嗎」問的是歷史事實：商品之後被搬到別的類別，
    /// 不改變「當時它在這個類別被賣掉」這件事，所以答案不隨商品搬移而改變。
    func hasTransaction(categoryId: UUID) -> Bool {
        soldCategoryIds.contains(categoryId)
    }
}

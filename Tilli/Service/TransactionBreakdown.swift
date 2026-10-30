//
//  TransactionBreakdown.swift
//  Tilli
//
//  交易明細頁的還原：把流水帳快照（SummaryItemModel 列）還原成與訂單摘要相同的版面。純計算，無狀態。
//
//  ⭐ 只讀交易快照，不讀場次設定 —— 套餐／組合被刪除或改價後，歷史明細照樣顯示當下的樣子。
//  ⭐ 恆等式（TransactionBreakdownTests 鎖住）：小計 − Σ 組合折抵 − Σ 整筆折扣 == 總計。
//

import Foundation

struct TransactionBreakdown: Equatable {

    enum Row: Equatable {
        /// 套餐一行：份數、套餐價小計（= Σ 成員原價 − Σ 成員 bundleDiscount）、成員名稱
        case bundle(bundleId: UUID, name: String, quantity: Int, lineTotal: Decimal, memberNames: [String])
        /// 單點商品（同一商品被組合拆成兩列時已合併）；有任何數量被組合涵蓋 → isInCombo
        case product(item: SummaryItemModel, isInCombo: Bool)
    }

    struct ComboLine: Equatable {
        let bundleId: UUID
        let name: String
        let amount: Decimal
        let groupCount: Int?        // 舊交易沒有組數快照時為 nil
    }

    let rows: [Row]
    let subtotal: Decimal           // 商品列原價 + 套餐列 lineTotal
    let comboLines: [ComboLine]
    let discounts: [AppliedDiscount]
    let total: Decimal              // = transaction.totalAmount

    /// 共 N 項：套餐算 1 項，同一商品的拆列算 1 項
    var itemCount: Int { rows.count }

    /// 共省 = 小計 − 總計（套餐差額已在小計外）
    var savings: Decimal { MoneyHelper.subtract(subtotal, total) }

    init(transaction: TransactionModel) {
        var bundleOrder: [UUID] = []
        var bundleMembers: [UUID: [SummaryItemModel]] = [:]

        var productOrder: [ProductKey] = []
        var productItems: [ProductKey: SummaryItemModel] = [:]
        var productInCombo: [ProductKey: Bool] = [:]

        var comboOrder: [UUID] = []
        var comboNames: [UUID: String] = [:]
        var comboAmounts: [UUID: Decimal] = [:]
        var comboGroupCounts: [UUID: Int] = [:]

        for item in transaction.items {
            // 套餐成員：依 bundleId 分組成一行
            if item.bundleKind == .fixed, let bundleId = item.bundleId {
                if bundleMembers[bundleId] == nil { bundleOrder.append(bundleId) }
                bundleMembers[bundleId, default: []].append(item)
                continue
            }

            // 組合涵蓋列：折抵依 bundleId 加總成優惠明細的一行
            let isComboRow = item.bundleKind == .chooseAny
            if isComboRow, let comboId = item.bundleId {
                if comboAmounts[comboId] == nil {
                    comboOrder.append(comboId)
                    comboNames[comboId] = item.bundleName ?? ""
                }
                comboAmounts[comboId] = MoneyHelper.add(comboAmounts[comboId] ?? 0, item.bundleDiscount)
                if let count = item.bundleGroupCount { comboGroupCounts[comboId] = count }
            }

            // 商品列：同一商品（同單價）的拆列合併
            let key = ProductKey(productId: item.productId, price: item.price)
            if var merged = productItems[key] {
                merged.quantity += item.quantity
                merged.allocatedDiscount = MoneyHelper.add(merged.allocatedDiscount, item.allocatedDiscount)
                merged.bundleDiscount = MoneyHelper.add(merged.bundleDiscount, item.bundleDiscount)
                productItems[key] = merged
            } else {
                productOrder.append(key)
                productItems[key] = item
            }
            productInCombo[key] = (productInCombo[key] ?? false) || isComboRow
        }

        let bundleRows: [Row] = bundleOrder.compactMap { bundleId in
            guard let members = bundleMembers[bundleId], let first = members.first else { return nil }
            let lineTotal = MoneyHelper.sum(members.map { MoneyHelper.subtract($0.total, $0.bundleDiscount) })
            return .bundle(
                bundleId: bundleId,
                name: first.bundleName ?? "",
                // 成員重複（如大福 ×2）時該列數量是份數的倍數，取最小者作為份數
                quantity: members.map(\.quantity).min() ?? 0,
                lineTotal: lineTotal,
                memberNames: members.map(\.name)
            )
        }
        let productRows: [Row] = productOrder.compactMap { key in
            guard let item = productItems[key] else { return nil }
            return .product(item: item, isInCombo: productInCombo[key] ?? false)
        }

        rows = bundleRows + productRows
        subtotal = MoneyHelper.sum(rows.map(\.lineTotal))
        comboLines = comboOrder.map { id in
            ComboLine(bundleId: id, name: comboNames[id] ?? "", amount: comboAmounts[id] ?? 0, groupCount: comboGroupCounts[id])
        }
        discounts = transaction.appliedDiscounts
        total = transaction.totalAmount
    }

    private struct ProductKey: Hashable {
        let productId: UUID
        let price: Decimal
    }
}

extension TransactionBreakdown.Row {
    /// 這一行在小計裡的金額：套餐為套餐價小計，商品為原價小計
    var lineTotal: Decimal {
        switch self {
        case let .bundle(_, _, _, lineTotal, _): return lineTotal
        case let .product(item, _): return item.total
        }
    }
}

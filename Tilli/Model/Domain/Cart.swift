//
//  Cart.swift
//  Tilli
//
//  購物車的值型別：單點商品、套餐行、已取消自動成組的組合。
//  見 docs/superpowers/specs/2026-10-27-bundles-design.md §5.6。
//

import Foundation

/// 購物車內的一個套餐行（一個套餐一行，份數累加）。
/// 名稱、價格、成員是「加入當下」的快照，用來在回到收銀頁時偵測套餐是否被改過。
struct BundleCartLine: Hashable {
    var quantity: Int
    let nameAtAdd: String
    let priceAtAdd: Decimal
    let productIdsAtAdd: [UUID]
}

struct Cart: Equatable {
    var productQuantities: [UUID: Int] = [:]
    var bundleLines: [UUID: BundleCartLine] = [:]     // key = bundle id；一個套餐一行
    var cancelledComboIds: Set<UUID> = []

    /// 此商品已被購物車佔用的數量 = 單點數量 + Σ 含此商品的套餐行份數
    func reservedQuantity(of productId: UUID) -> Int {
        let single = productQuantities[productId] ?? 0
        let viaBundles = bundleLines.values.reduce(0) { sum, line in
            let occurrences = line.productIdsAtAdd.filter { $0 == productId }.count
            return sum + occurrences * line.quantity
        }
        return single + viaBundles
    }

    var isEmpty: Bool {
        productQuantities.values.allSatisfy { $0 <= 0 } && bundleLines.values.allSatisfy { $0.quantity <= 0 }
    }
}

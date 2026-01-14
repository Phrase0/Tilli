//
//  InventoryChangeModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/23.
//
import SwiftUI

// MARK: - 庫存異動原因
enum InventoryChangeReason: String, Codable, CaseIterable {
    case salesOut       // 銷售出庫（正常售出商品）
    case returnIn       // 退貨入庫（客戶退貨回補庫存)
    case inventoryLoss  // 盤損/盤虧（盤點與帳面不符）
    case damaged        // 損壞報廢（破損、故障或受潮）
    case expired        // 過期銷毀（超過有效期限）
    case internalUse    // 內部領用（公司自用或樣品提供）
    case purchase       // 進貨入庫（廠商採購）
    case adjustment     // 其他調整


    var displayName: String {
        switch self {
        case .salesOut: return "銷售出庫"
        case .returnIn: return "退貨入庫"
        case .inventoryLoss: return "盤損調整"
        case .damaged: return "損壞報廢"
        case .expired: return "過期銷毀"
        case .internalUse: return "內部領用"
        case .purchase: return "進貨入庫"
        case .adjustment: return "其他調整"
        }
    }

    var tagColor: Color {
        switch self {
        case .salesOut: return .blue
        case .returnIn: return .green
        case .inventoryLoss: return .orange
        case .damaged: return .red
        case .expired: return .purple
        case .internalUse: return .gray
        case .purchase: return .teal
        case .adjustment: return .secondary
        }
    }

    /// 是否為增加庫存的操作
    var isIncrease: Bool {
        switch self {
        case .returnIn, .purchase: return true
        default: return false
        }
    }

    /// 是否為減少庫存的操作
    var isDecrease: Bool {
        switch self {
        case .salesOut, .inventoryLoss, .damaged, .expired, .internalUse: return true
        default: return false
        }
    }

    // MARK: - 靜態方法：根據庫存變化方向取得可用原因

    /// 增加庫存時可選的原因
    static var increaseReasons: [InventoryChangeReason] {
        [.purchase, .returnIn, .adjustment]
    }

    /// 減少庫存時可選的原因
    static var decreaseReasons: [InventoryChangeReason] {
        [.salesOut, .inventoryLoss, .damaged, .expired, .internalUse, .adjustment]
    }

    /// 根據庫存變化量取得可用原因（不包含 salesOut，因為那是自動記錄的）
    static func availableReasons(for stockDelta: Int) -> [InventoryChangeReason] {
        if stockDelta > 0 {
            // 增加庫存：進貨入庫、退貨入庫、其他調整
            return [.purchase, .returnIn, .adjustment]
        } else if stockDelta < 0 {
            // 減少庫存：盤損調整、損壞報廢、過期銷毀、內部領用、其他調整
            // 注意：不包含 salesOut，因為銷售出庫是結帳時自動記錄
            return [.inventoryLoss, .damaged, .expired, .internalUse, .adjustment]
        } else {
            return []
        }
    }
}

// MARK: - 庫存異動紀錄
struct InventoryChangeModel: Identifiable, Codable {
    var id = UUID()
    var productId: UUID
    var sessionId: UUID
    var change: Int                        // +10 進貨，-3 銷售
    var reason: InventoryChangeReason      // 異動原因
    var customReason: String?              // 「其他調整」時的自定義原因
    var transactionId: UUID?               // 關聯的交易 ID（僅銷售出庫時有值）
    var timestamp: Date

    /// 格式化的變化量文字（如 +10 或 -3）
    var changeText: String {
        if change >= 0 {
            return "+\(change)"
        } else {
            return "\(change)"
        }
    }

    /// 變化量顏色
    var changeColor: Color {
        if change > 0 {
            return .green
        } else if change < 0 {
            return .red
        } else {
            return .secondary
        }
    }

    /// 顯示用的原因名稱（若為「其他調整」且有自定義原因，則顯示自定義原因）
    var displayReasonName: String {
        if reason == .adjustment, let custom = customReason, !custom.isEmpty {
            return custom
        }
        return reason.displayName
    }
}

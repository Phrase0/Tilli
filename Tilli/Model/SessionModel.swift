
//
//  Untitled.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/23.
//
import SwiftUI

struct SessionModel: Identifiable, Codable {
    var id = UUID()
    var title: String                  // 場次名稱，例如「2025/08/01 花博市集」
    var date: Date                    // 場次日期，主要報表依據
    var status: SessionStatus        // 進行中 / 已結束
    var categories: [String]         // 類別選單，用於過濾商品或報表
    var createdAt: Date              // 場次建立時間
    var products: [ProductModel]     // 該場次所有商品
    var transactions: [TransactionModel] = []  // 場次中發生的交易紀錄（新增）
}


enum SessionStatus: String, Codable {
    case ongoing = "ongoing"
    case completed = "completed"

    var color: Color {
        switch self {
        case .ongoing:
            return Color.green.opacity(0.3)
        case .completed:
            return Color.gray.opacity(0.3)
        }
    }

    var textColor: Color {
        switch self {
        case .ongoing: return .green
        case .completed: return .gray
        }
    }
}

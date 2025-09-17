
//
//  Untitled.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/23.
//
import SwiftUI

struct SessionModel: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String                  // 場次名稱，例如「2025/08/01 花博市集」
    var date: Date                    // 場次日期，主要報表依據
    var categories: [CategoryModel]         // 類別選單，用於過濾商品或報表
    var createdAt: Date              // 場次建立時間
    var transactions: [TransactionModel] = []  // 場次中發生的交易記錄（新增）
    
    var status: SessionStatus {  // 進行中 / 已結束
        let today = Calendar.current.startOfDay(for: Date())
        let sessionDay = Calendar.current.startOfDay(for: date)

        if sessionDay == today {
            return .ongoing
        } else if sessionDay < today {
            return .completed
        } else {
            return .upcoming
        }
    }
}


enum SessionStatus: String, Codable {
    case ongoing
    case completed
    case upcoming

    var color: Color {
        switch self {
        case .ongoing: return Color.white
        case .completed: return Color.gray.opacity(0.2)
        case .upcoming: return Color.blue.opacity(0.2)
        }
    }

    var textColor: Color {
        switch self {
        case .ongoing: return .blue
        case .completed: return .gray
        case .upcoming: return .blue
        }
    }

    var localizedDescription: String {
        switch self {
        case .ongoing: return "進行中"
        case .completed: return "已完成"
        case .upcoming: return "即將到來"
        }
    }
}

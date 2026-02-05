
//
//  SessionModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/23.
//
import SwiftUI

struct SessionModel: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String                   // 場次名稱，例如「2025/08/01 花博市集」
    var startDate: Date                 // 場次開始日期（必填）
    var endDate: Date?                  // 場次結束日期（可選，nil 表示無限期）
    var dateType: SessionDateType       // 場次類型：單日/多日/無限期
    var categories: [CategoryModel]     // 類別選單，用於過濾商品或報表
    var createdAt: Date                 // 場次建立時間
    var currency: String = "TWD"        // 場次使用的幣別，預設為台幣
    var discounts: [DiscountModel] = [] // 場次可用的折扣選項

    // 計算屬性：顯示用的日期（= startDate）
    var displayDate: Date {
        return startDate
    }

    // 計算屬性：日期範圍字串
    var displayDateRange: String {
        switch dateType {
        case .single:
            return DateFormatter.standardDate.string(from: startDate)
        case .multi:
            guard let endDate = endDate else { return DateFormatter.standardDate.string(from: startDate) }
            return "\(DateFormatter.standardDate.string(from: startDate)) - \(DateFormatter.standardDate.string(from: endDate))"
        case .permanent:
            return "\(DateFormatter.standardDate.string(from: startDate)) 起"
        }
    }

    // 計算屬性：場次天數（僅多日場次有值）
    var dayCount: Int? {
        guard dateType == .multi, let end = endDate else { return nil }
        return Calendar.current.dateComponents([.day], from: startDate, to: end).day! + 1
    }

    // 計算屬性：場次是否在進行中
    var isActive: Bool {
        let today = Date()
        if let end = endDate {
            return today >= startDate && today <= end
        } else {
            return today >= startDate  // 無限期永遠 active（只要已開始）
        }
    }

    // 計算屬性：場次狀態
    var status: SessionStatus {
        let today = Calendar.current.startOfDay(for: Date())
        let start = Calendar.current.startOfDay(for: startDate)

        switch dateType {
        case .single, .multi:
            if let end = endDate {
                let endDay = Calendar.current.startOfDay(for: end)
                if today < start {
                    return .upcoming
                } else if today > endDay {
                    return .completed
                } else {
                    return .ongoing
                }
            } else {
                // single 類型理論上不應該沒有 endDate，但為了安全處理
                if today < start {
                    return .upcoming
                } else if today == start {
                    return .ongoing
                } else {
                    return .completed
                }
            }

        case .permanent:
            if today < start {
                return .upcoming
            } else {
                return .ongoing  // 永遠不會變成 completed
            }
        }
    }
}

enum SessionDateType: String, Codable, Hashable {
    case single      // 單日場次
    case multi       // 多日場次
    case permanent   // 無限期場次
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

// MARK: - CoreData 轉換
extension SessionModel {
    init(entity: CDSessionEntity) {
        self.id = entity.id
        self.title = entity.title
        self.startDate = entity.startDate
        self.endDate = entity.endDate
        self.dateType = SessionDateType(rawValue: entity.dateType) ?? .single
        self.createdAt = entity.createdAt
        self.currency = entity.currency

        // Categories 按 sortOrder 排序
        self.categories = (entity.categories as? Set<CDCategoryEntity>)?
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { CategoryModel(entity: $0) } ?? []

        // 解碼 discounts
        if let data = entity.discountsData,
           let decoded = try? JSONDecoder().decode([DiscountModel].self, from: data) {
            self.discounts = decoded
        } else {
            self.discounts = []
        }
    }
}

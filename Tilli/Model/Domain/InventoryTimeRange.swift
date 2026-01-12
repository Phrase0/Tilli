//
//  InventoryTimeRange.swift
//  Tilli
//
//  Created by Peiyun on 2025/1/12.
//

import Foundation

/// 庫存頁面時間範圍篩選
struct InventoryTimeRange: Equatable {
    var type: RangeType
    var customStart: Date
    var customEnd: Date
    let session: SessionModel

    enum RangeType: CaseIterable {
        case all            // 全部
        case today          // 今日
        case thisWeek       // 本週
        case thisMonth      // 本月
        case custom         // 自訂

        var displayName: String {
            switch self {
            case .all: return "全部"
            case .today: return "今日"
            case .thisWeek: return "本週"
            case .thisMonth: return "本月"
            case .custom: return "自訂"
            }
        }
    }

    /// 初始化
    init(session: SessionModel, type: RangeType = .all) {
        self.session = session
        self.type = type
        self.customStart = session.startDate
        self.customEnd = session.endDate ?? Date()
    }

    // MARK: - 計算屬性

    /// 實際的開始日期
    var actualStart: Date {
        let calendar = Calendar.current

        switch type {
        case .all:
            return calendar.startOfDay(for: session.startDate)

        case .today:
            return calendar.startOfDay(for: Date())

        case .thisWeek:
            // 取得本週一
            let today = calendar.startOfDay(for: Date())
            let weekday = calendar.component(.weekday, from: today)
            // weekday: 1=週日, 2=週一, ..., 7=週六
            let daysToSubtract = (weekday == 1) ? 6 : weekday - 2
            let weekStart = calendar.date(byAdding: .day, value: -daysToSubtract, to: today)!
            // 確保不早於場次開始日期
            let sessionStart = calendar.startOfDay(for: session.startDate)
            return max(weekStart, sessionStart)

        case .thisMonth:
            // 取得本月第一天
            let today = calendar.startOfDay(for: Date())
            let components = calendar.dateComponents([.year, .month], from: today)
            let monthStart = calendar.date(from: components)!
            // 確保不早於場次開始日期
            let sessionStart = calendar.startOfDay(for: session.startDate)
            return max(monthStart, sessionStart)

        case .custom:
            return calendar.startOfDay(for: customStart)
        }
    }

    /// 實際的結束日期
    var actualEnd: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        switch type {
        case .all:
            if let endDate = session.endDate {
                return calendar.startOfDay(for: endDate)
            } else {
                return today
            }

        case .today, .thisWeek, .thisMonth:
            return today

        case .custom:
            let customEndDay = calendar.startOfDay(for: customEnd)
            return min(customEndDay, today)
        }
    }

    /// 天數（包含起始和結束日）
    var dayCount: Int {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: actualStart, to: actualEnd).day ?? 0
        return days + 1
    }

    /// 日期區間（用於查詢）
    var dateInterval: DateInterval {
        let calendar = Calendar.current
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: actualEnd)!
        return DateInterval(start: actualStart, end: endOfDay)
    }

    /// 顯示用的日期範圍文字
    var displayText: String {
        switch type {
        case .all:
            if session.dateType == .permanent {
                return "\(DateFormatter.standardDate.string(from: actualStart)) 至今"
            } else {
                return "\(DateFormatter.standardDate.string(from: actualStart)) - \(DateFormatter.standardDate.string(from: actualEnd))"
            }

        case .today:
            return "今日"

        case .thisWeek:
            return "本週"

        case .thisMonth:
            return "本月"

        case .custom:
            return "\(DateFormatter.standardDate.string(from: actualStart)) - \(DateFormatter.standardDate.string(from: actualEnd))"
        }
    }
}

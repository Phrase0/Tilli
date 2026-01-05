//
//  ReportTimeRange.swift
//  Tilli
//
//  Created by Peiyun on 2025/11/18.
//

import Foundation

/// 報表時間範圍
struct ReportTimeRange: Equatable {
    var type: RangeType
    var customStart: Date
    var customEnd: Date
    let session: SessionModel

    enum RangeType {
        case all            // 全部（場次完整範圍）
        case today          // 今日
        case recent7        // 最近7天
        case recent30       // 最近30天
        case custom         // 自訂
    }

    /// 初始化時設定合理的預設值
    init(session: SessionModel, type: RangeType? = nil) {
        self.session = session

        // 根據場次類型設定預設 type
        if let type = type {
            self.type = type
        } else {
            // 無限期場次預設為最近30天，其他為全部
            self.type = session.dateType == .permanent ? .recent30 : .all
        }

        // 初始化自訂日期範圍
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

        case .recent7:
            let today = calendar.startOfDay(for: Date())
            let sevenDaysAgo = calendar.date(byAdding: .day, value: -6, to: today)!
            // 確保不早於場次開始日期
            let sessionStart = calendar.startOfDay(for: session.startDate)
            return max(sevenDaysAgo, sessionStart)

        case .recent30:
            let today = calendar.startOfDay(for: Date())
            let thirtyDaysAgo = calendar.date(byAdding: .day, value: -29, to: today)!
            // 確保不早於場次開始日期
            let sessionStart = calendar.startOfDay(for: session.startDate)
            return max(thirtyDaysAgo, sessionStart)

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
            // 單日/多日：使用場次結束日期
            // 無限期：使用今天
            if let endDate = session.endDate {
                return calendar.startOfDay(for: endDate)
            } else {
                return today
            }

        case .today:
            return today

        case .recent7:
            return today

        case .recent30:
            return today

        case .custom:
            let customEndDay = calendar.startOfDay(for: customEnd)

            // 無限期場次限制自訂範圍最多90天
            if session.dateType == .permanent {
                let maxEnd = calendar.date(byAdding: .day, value: 89, to: actualStart)!
                return min(customEndDay, maxEnd, today)
            }

            // 多日場次限制不超過場次結束日期
            if let sessionEnd = session.endDate {
                let sessionEndDay = calendar.startOfDay(for: sessionEnd)
                return min(customEndDay, sessionEndDay)
            }

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
        // actualEnd 設為當天結束時間（23:59:59）
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

        case .recent7:
            return "最近 7 天"

        case .recent30:
            return "最近 30 天"

        case .custom:
            return "\(DateFormatter.standardDate.string(from: actualStart)) - \(DateFormatter.standardDate.string(from: actualEnd))"
        }
    }

    /// CSV 報表用的日期範圍文字（格式：2025-12-22 或 2025-12-01 ~ 2025-12-30）
    var csvDateRangeText: String {
        let startStr = DateFormatter.isoDate.string(from: actualStart)
        let endStr = DateFormatter.isoDate.string(from: actualEnd)

        if dayCount == 1 {
            return startStr
        } else {
            return "\(startStr) ~ \(endStr)"
        }
    }

    // MARK: - 驗證

    /// 驗證自訂日期範圍是否合法
    func validateCustomRange() -> (isValid: Bool, errorMessage: String?) {
        guard type == .custom else {
            return (true, nil)
        }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: customStart)
        let end = calendar.startOfDay(for: customEnd)

        // 結束日期必須 >= 開始日期
        guard end >= start else {
            return (false, "結束日期必須晚於或等於開始日期")
        }

        // 無限期場次：自訂範圍最多90天
        if session.dateType == .permanent {
            let days = calendar.dateComponents([.day], from: start, to: end).day! + 1
            if days > 90 {
                return (false, "無限期場次的自訂範圍不可超過 90 天")
            }
        }

        return (true, nil)
    }
}

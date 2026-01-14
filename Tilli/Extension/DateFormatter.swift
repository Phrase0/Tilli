//
//  DateFormatter.swift
//  Tilli
//
//  Created by Peiyun on 2025/6/17.
//

import Foundation

extension DateFormatter {

    // MARK: - 基本日期格式

    /// 標準日期：yyyy/MM/dd（例：2026/01/04）
    static let standardDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    /// 短日期：MM/dd（例：01/04）- 用於圖表
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter
    }()

    /// ISO 日期：yyyy-MM-dd（例：2026-01-04）- 用於 CSV
    static let isoDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - 帶星期的日期格式

    /// 日期帶星期：yyyy/MM/dd（E）（例：2026/01/04（週日））
    static let dateWithWeekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "yyyy/MM/dd（E）"
        return formatter
    }()

    // MARK: - 日期時間格式

    /// 日期時間：yyyy/MM/dd HH:mm（例：2026/01/04 14:30）
    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter
    }()

    /// 檔案名稱時間戳：yyyyMMdd_HHmm（例：20260104_143012）- 用於匯出檔案命名
    static let fileTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()

    // MARK: - 中文格式

    /// 中文年月：yyyy年 M月（例：2026年 1月）- 用於日曆
    static let chineseYearMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "yyyy年 M月"
        return formatter
    }()
}

//
//  DateValidationHelper.swift
//  Tilli
//
//  Created by Peiyun on 2025/12/17.
//

import Foundation

struct DateValidationHelper {

    /// 驗證交易日期是否在場次範圍內
    /// - Parameters:
    ///   - session: 場次資料
    ///   - transactionDate: 交易日期（預設為當前時間）
    /// - Returns: (是否有效, 錯誤訊息)
    static func validateTransactionDate(
        for session: SessionModel,
        transactionDate: Date = Date()
    ) -> (isValid: Bool, errorMessage: String?) {

        let calendar = Calendar.current
        let transactionDay = calendar.startOfDay(for: transactionDate)
        let startDay = calendar.startOfDay(for: session.startDate)

        switch session.dateType {
        case .single:
            // 單日場次：只能在當天
            if transactionDay != startDay {
                return (false, "此為單日場次（\(session.displayDateRange)），只能在場次日期內新增交易。\n\n如需登記其他日期的交易，請編輯場次改為多日場次。")
            }

        case .multi:
            // 多日場次：必須在範圍內
            guard let end = session.endDate else {
                return (false, "多日場次數據異常")
            }
            let endDay = calendar.startOfDay(for: end)

            if transactionDay < startDay || transactionDay > endDay {
                return (false, "此為多日場次（\(session.displayDateRange)），只能在場次日期範圍內新增交易。\n\n如需登記其他日期的交易，請編輯場次調整日期範圍。")
            }

        case .permanent:
            // 無限期場次：只能在開始日期之後
            if transactionDay < startDay {
                return (false, "此為無限期場次（\(session.displayDateRange)），只能在場次開始日期之後新增交易。\n\n如需登記更早日期的交易，請編輯場次調整開始日期。")
            }
        }

        return (true, nil)
    }
}

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
    ///   - event: 場次資料
    ///   - transactionDate: 交易日期（預設為當前時間）
    /// - Returns: (是否有效, 錯誤訊息)
    static func validateTransactionDate(
        for event: EventModel,
        transactionDate: Date = Date()
    ) -> (isValid: Bool, errorMessage: String?) {

        let calendar = Calendar.current
        let transactionDay = calendar.startOfDay(for: transactionDate)
        let startDay = calendar.startOfDay(for: event.startDate)

        switch event.dateType {
        case .single:
            if transactionDay != startDay {
                // 此為單日場次（...），只能在場次日期內新增交易。
                return (false, String.localized("dateValidationSingleDay \(event.displayDateRange)"))
            }

        case .multi:
            guard let end = event.endDate else {
                // 多日場次數據異常
                return (false, String.localized("dateValidationMultiError"))
            }
            let endDay = calendar.startOfDay(for: end)

            if transactionDay < startDay || transactionDay > endDay {
                // 此為多日場次（...），只能在場次日期範圍內新增交易。
                return (false, String.localized("dateValidationMultiDay \(event.displayDateRange)"))
            }

        case .permanent:
            if transactionDay < startDay {
                // 此為無限期場次（...），只能在場次開始日期之後新增交易。
                return (false, String.localized("dateValidationPermanent \(event.displayDateRange)"))
            }
        }

        return (true, nil)
    }
}

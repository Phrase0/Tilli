//
//  DateFormatter.swift
//  Tilli
//
//  Created by Peiyun on 2025/6/17.
//

import Foundation

extension DateFormatter {
    static let sessionDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    static let csvFileDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        return formatter
    }()

    static let transactionDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter
    }()
}

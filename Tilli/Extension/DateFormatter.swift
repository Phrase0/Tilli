//
//  Untitled.swift
//  Tilli
//
//  Created by Peiyun on 2025/6/17.
//

import Foundation

extension DateFormatter {
    static let sessionDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
    
    static let csvFileDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        return formatter
    }()
}

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
        return formatter
    }()
}

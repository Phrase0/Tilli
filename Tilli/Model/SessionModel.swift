
//
//  Untitled.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/23.
//
import SwiftUI

struct SessionModel: Identifiable, Codable {
    var id = UUID()
    var title: String
    var date: Date
    var status: SessionStatus
//    var amount: Int
    var categories: [String]
    var createdAt: Date // 建立時間
    var products: [ProductModel]
}

enum SessionStatus: String, Codable {
    case ongoing = "ongoing"
    case completed = "completed"

    var color: Color {
        switch self {
        case .ongoing:
            return Color.green.opacity(0.3)
        case .completed:
            return Color.gray.opacity(0.3)
        }
    }

    var textColor: Color {
        switch self {
        case .ongoing:
            return .green
        case .completed:
            return .gray
        }
    }
}

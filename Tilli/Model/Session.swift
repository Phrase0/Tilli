
//
//  Untitled.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/23.
//
import SwiftUI

struct Session: Identifiable {
    let id = UUID()
    let title: String
    let date: String
    let amount: String
    let status: SessionStatus
}

enum SessionStatus: String {
    case ongoing = "on going"
    case completed = "completed"
    
    var color: Color {
        switch self {
        case .ongoing: return .blue
        case .completed: return .gray
        }
    }
}

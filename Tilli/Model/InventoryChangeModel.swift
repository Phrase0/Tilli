//
//  Untitled.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/23.
//
import SwiftUI

struct InventoryChangeModel: Identifiable, Codable {
    var id = UUID()
    var productId: UUID
    var sessionId: UUID
    var change: Int                   // +10 進貨，-3 銷售
    var reason: String                // 原因（進貨 / 盤點 / 調整）
    var timestamp: Date
}

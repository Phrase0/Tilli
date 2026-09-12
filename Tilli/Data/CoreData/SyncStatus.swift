//
//  SyncStatus.swift
//  Tilli
//
//  本機同步狀態標記。
//  （由原 CDPendingSyncOperation+CoreDataProperties.swift 抽出）
//
//  ⚠️ 這是【純本機】欄位，不上傳雲端。見 ARCHITECTURE.md §3.2。
//  同步層移除期間，所有寫入一律標 .pending；重建同步後才會有 .synced。
//

import Foundation

enum SyncStatus: String {
    case synced = "synced"      // 已確認寫入雲端
    case pending = "pending"    // 等待上傳
}

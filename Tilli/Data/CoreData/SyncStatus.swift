//
//  SyncStatus.swift
//  Tilli
//
//  Created by Peiyun on 2026/9/12.
//
//  本機同步狀態標記。
//
//  ⚠️ 這是【純本機】欄位，不上傳雲端。
//  同步層移除期間，所有寫入一律標 .pending；重建同步後才會有 .synced。
//

import Foundation

enum SyncStatus: String {
    case synced = "synced"      // 已確認寫入雲端
    case pending = "pending"    // 等待上傳
}

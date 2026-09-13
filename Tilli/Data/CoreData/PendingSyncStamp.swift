//
//  PendingSyncStamp.swift
//  Tilli
//
//  Created by Peiyun on 2026/9/12.
//
//  統一的「待同步」標記入口。取代全專案 25 處各自寫
//  `syncStatus = "pending"` + `updatedAt = Date()` 的樣板。
//  見 FEATURE_PLAN_V1.md §2.7（解 C1、C4）。
//

import CoreData

extension NSManagedObject {

    /// 標記為待同步：一律同時設定 `syncStatus` 與 `updatedAt`。
    ///
    /// `updatedAt` 是同步架構的 LWW 依據（`SYNC_ARCHITECTURE_V2.md` §6.2），
    /// 漏設會讓衝突判斷選錯版本 —— 所以兩者必須綁在一起，不可分開呼叫。
    ///
    /// 批次寫入時傳入同一個 `date`，讓同一批的 `updatedAt` 完全一致。
    func markPendingSync(at date: Date = Date()) {
        guard entity.attributesByName["syncStatus"] != nil else {
            assertionFailure("\(entity.name ?? "?") 沒有 syncStatus 欄位")
            return
        }
        setValue(SyncStatus.pending.rawValue, forKey: "syncStatus")

        // 流水帳（Transaction / InventoryChange）是 append-only：`updatedAt` 只在
        // 建立當下寫入，之後不會再被呼叫，所以這裡直接設定即可。
        if entity.attributesByName["updatedAt"] != nil {
            setValue(date, forKey: "updatedAt")
        }
    }
}

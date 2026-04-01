//
//  HybridSyncListener.swift
//  Tilli
//
//  Created by Peiyun on 2026/2/9.
//  Created for Hybrid Listener 即時監聽
//  只監聯 users/{userId}/private/syncState 文件（200-500 bytes）
//  偵測 version 變化後根據 pendingChanges 做增量下載或全量同步
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Hybrid Sync Listener
/// 監聽輕量的 syncState 文件，收到變更通知後精確下載需要的資料
@MainActor
class HybridSyncListener {
    static let shared = HybridSyncListener()

    private let db = Firestore.firestore()
    private let downloader = FirestoreDownloader.shared

    /// Firestore snapshot listener registration
    private var listener: ListenerRegistration?

    /// 本地版本號（快取在 UserDefaults）
    private var localVersion: Int {
        get { UserDefaults.standard.integer(forKey: "syncVersion") }
        set { UserDefaults.standard.set(newValue, forKey: "syncVersion") }
    }

    /// 防止重入處理
    private var isProcessing = false

    /// 是否正在監聽
    var isListening: Bool {
        return listener != nil
    }

    /// 所有 entity type 的 key（對應 syncState.pendingChanges 中的 key）
    private let allEntityKeys = ["sessions", "categories", "products", "transactions", "inventoryChanges", "qrCodes"]

    private init() {}

    // MARK: - Start / Stop Listening

    /// 開始監聽 syncState 文件
    func startListening(userId: String) {
        // 避免重複監聽
        stopListening()

        let syncStateRef = db.collection("users").document(userId)
            .collection("private").document("syncState")

        print("👂 [HybridSyncListener] startListening — userId: \(userId), localVersion: \(localVersion)")

        listener = syncStateRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }

            Task { @MainActor in
                self.handleSnapshotUpdate(snapshot: snapshot, error: error)
            }
        }
    }

    /// 停止監聽
    func stopListening() {
        if listener != nil {
            print("🛑 [HybridSyncListener] stopListening — localVersion: \(localVersion)")
        }
        listener?.remove()
        listener = nil
    }

    /// 重置本地版本號（登出或重新登入時呼叫）
    func resetLocalVersion() {
        print("🔁 [HybridSyncListener] resetLocalVersion: \(localVersion) → 0")
        localVersion = 0
    }

    // MARK: - Snapshot Handler

    /// 處理 syncState snapshot 更新
    private func handleSnapshotUpdate(snapshot: DocumentSnapshot?, error: Error?) {
        if let error = error {
            print("❌ [HybridSyncListener] 監聽錯誤 - \(error)")
            return
        }

        guard let snapshot = snapshot else {
            print("⚠️ [HybridSyncListener] snapshot 為 nil（文件不存在或連線中斷）")
            return
        }

        guard let data = snapshot.data() else {
            print("⚠️ [HybridSyncListener] snapshot.data() 為 nil — docExists: \(snapshot.exists), docID: \(snapshot.documentID)")
            return
        }

        let cloudVersion = data["version"] as? Int ?? 0
        let pendingChanges = data["pendingChanges"] as? [String: [String]] ?? [:]
        let pendingCount = pendingChanges.values.map(\.count).reduce(0, +)

        print("📡 [HybridSyncListener] snapshot 收到 — cloudVersion: \(cloudVersion), localVersion: \(localVersion), pendingIDs 總數: \(pendingCount), isProcessing: \(isProcessing)")

        // 版本號沒變，不處理
        guard cloudVersion > localVersion else {
            print("⏭️ [HybridSyncListener] 版本未變更，跳過 (local: \(localVersion), cloud: \(cloudVersion))")
            return
        }

        print("🔄 [HybridSyncListener] 版本變更 (local: \(localVersion) → cloud: \(cloudVersion))，pendingChanges: \(pendingChanges)")

        Task {
            await self.processChanges(pendingChanges: pendingChanges, cloudVersion: cloudVersion)
        }
    }

    // MARK: - Process Changes

    /// 處理 syncState 變更
    private func processChanges(pendingChanges: [String: [String]], cloudVersion: Int) async {
        // 防止重入
        guard !isProcessing else {
            print("⚠️ [HybridSyncListener] 處理中，跳過 cloudVersion: \(cloudVersion)（目前處理中，此更新被丟棄）")
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        // 判斷是否有任何具體的 ID
        let hasAnyIds = allEntityKeys.contains { key in
            guard let ids = pendingChanges[key], !ids.isEmpty else { return false }
            return true
        }

        if hasAnyIds {
            print("📥 [HybridSyncListener] 增量同步開始 — cloudVersion: \(cloudVersion), IDs: \(pendingChanges)")
            await performIncrementalSync(pendingChanges: pendingChanges)
        } else {
            // 所有 pendingChanges 都空但 version 變了
            // 可能是 pendingChanges overflow 被 trim，觸發全量同步
            print("📥 [HybridSyncListener] pendingChanges 為空，觸發全量同步 — cloudVersion: \(cloudVersion)")
            await SyncManager.shared.performFullSync()
        }

        // 更新本地版本號
        localVersion = cloudVersion

        // 通知 Repository 層重新從 CoreData 讀取，刷新 UI
        NotificationCenter.default.post(name: .syncDidComplete, object: nil)
        print("✅ [HybridSyncListener] 完成 — localVersion 更新為 \(cloudVersion)")
    }

    // MARK: - Incremental Sync

    /// 增量同步：按 parent-first 順序處理每個 entity type 的 ID
    private func performIncrementalSync(pendingChanges: [String: [String]]) async {
        let typeOrder: [(key: String, type: SyncEntityType)] = [
            ("sessions", .session),
            ("categories", .category),
            ("products", .product),
            ("transactions", .transaction),
            ("inventoryChanges", .inventoryChange),
            ("qrCodes", .qrCode)
        ]

        for (key, entityType) in typeOrder {
            guard let ids = pendingChanges[key], !ids.isEmpty else { continue }

            let uuids = ids.compactMap { UUID(uuidString: $0) }

            for id in uuids {
                do {
                    _ = try await downloader.syncFromServer(type: entityType, id: id)
                } catch {
                    print("  ❌ \(key)/\(id): 同步失敗 - \(error)")
                }
            }
        }
    }
}

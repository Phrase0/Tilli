# Pro 多裝置即時同步 — 問題清單與修改計畫

> 建立日期：2026-03-31  
> 分支：feature/SyncFirebaseData  
> 狀態：待修改

---

## 背景

Pro 會員支援多裝置同時登入並即時同步資料。  
同步架構：Device 做任何 CRUD → Firestore batch 寫入（entity + syncState）→ 其他裝置的 HybridSyncListener 收到 version 變化 → 增量或全量下載。

---

## Bug 清單

### Bug 0（已修 2026-03-31）：增量同步完成後未通知 UI 刷新

**檔案**：`Tilli/Data/Sync/HybridSyncListener.swift`（`processChanges` 結尾）

**問題**：`performIncrementalSync()` 下載資料到 CoreData 後，沒有發送 `.syncDidComplete` 通知。所有 Repository（Session/Transaction/QRCode 等）靠此通知重新 fetch CoreData 並更新 `@Published` 陣列。因此 UI 不刷新，直到使用者主動新增/修改資料才看到同步結果。

**修改**：在 `localVersion = cloudVersion` 後加一行：
```swift
NotificationCenter.default.post(name: .syncDidComplete, object: nil)
```

---

### Bug 1（高優先）：`isProcessing` 直接丟棄並發更新

**檔案**：`Tilli/Data/Sync/HybridSyncListener.swift:106`

**問題**：
```swift
guard !isProcessing else {
    print("⚠️ 處理中，跳過 cloudVersion: \(cloudVersion)")
    return  // ← 第二個 snapshot 更新被永久丟棄
}
```
Device A 快速做兩次修改（version 6 → 7），Device B 正在處理 version 6 時，version 7 的 snapshot 觸發但被 `return` 丟棄。  
若 Device A 之後沒有第 3 次修改，version 7 的資料永遠不會同步到 Device B，直到 app 重啟或背景/前景切換。

**修改方式**：
```swift
private var pendingVersion: Int?
private var pendingChangesCache: [String: [String]] = [:]

guard !isProcessing else {
    // 不丟棄，保留最新版本等處理完後補做
    if cloudVersion > (pendingVersion ?? 0) {
        pendingVersion = cloudVersion
        pendingChangesCache = pendingChanges
    }
    return
}

isProcessing = true
defer {
    isProcessing = false
    // 補處理被跳過的版本
    if let next = pendingVersion, next > localVersion {
        let nextChanges = pendingChangesCache
        pendingVersion = nil
        pendingChangesCache = [:]
        Task { await self.processChanges(pendingChanges: nextChanges, cloudVersion: next) }
    }
}
```

---

### Bug 2（中優先）：`fullUploadAllData` 標記 synced 不區分成功/失敗

**檔案**：`Tilli/Data/Sync/SyncManager.swift:908-926`

**問題**：
```swift
for session in sessions {
    do {
        try await uploader.uploadSessionWithChildren(session.toModel())
    } catch {
        print("❌ 失敗")
        // ← catch 後繼續，但之後仍被標記為 synced
    }
}
// 無論成功或失敗，全部標 synced ← BUG
for entity in allEntities {
    entity.setValue("synced", forKey: "syncStatus")
}
```
上傳失敗的實體被標為 `synced`，永遠不會重試，Device B 看不到這筆資料。

**修改方式**：
- 每個 entity 上傳成功後才個別標記 `synced`
- 上傳失敗的維持 `pending`，`processPendingQueue` 可以重試

```swift
for session in sessions {
    do {
        try await uploader.uploadSessionWithChildren(session.toModel())
        session.setValue("synced", forKey: "syncStatus")  // 只在成功時標記
    } catch {
        print("❌ fullUpload Session 失敗: \(session.id) - \(error)")
        // 維持 pending，等待 processPendingQueue 重試
    }
}
```
Categories、Products、Transactions、InventoryChanges 也同樣處理。

---

### Bug 3（低優先）：`localVersion` 沒有 userId 區隔

**檔案**：`Tilli/Data/Sync/HybridSyncListener.swift:28`

**問題**：
```swift
get { UserDefaults.standard.integer(forKey: "syncVersion") }
```
Key 固定為 `"syncVersion"`，不分帳號。  
同一台裝置 A 帳號登出再登入 B 帳號時，`resetLocalVersion()` 已重設為 0（此次問題較小），但若未來有其他登入流程調整，可能造成版本比對錯誤。

**修改方式**：
```swift
// startListening 時記錄 userId
private var currentUserId: String = ""

func startListening(userId: String) {
    currentUserId = userId
    stopListening()
    ...
}

private var localVersion: Int {
    get { UserDefaults.standard.integer(forKey: "syncVersion_\(currentUserId)") }
    set { UserDefaults.standard.set(newValue, forKey: "syncVersion_\(currentUserId)") }
}

func resetLocalVersion() {
    UserDefaults.standard.removeObject(forKey: "syncVersion_\(currentUserId)")
}
```

---

## Account Switching 問題（A 登出 → B 登入）

**結論：架構正確，但有一個浪費**

### 流程確認
```
A 登出：
  SyncManager.resetSync()        → stopListening + resetLocalVersion(0)
  SyncManager.clearAllLocalData() → 刪除所有 CoreData + CDPendingSyncOperation
  Auth.signOut()
  setupLocalGuest()

B 登入：
  handleSignInSuccess()
    setMembership(B.membership)
    initializeSync()
      initializeSyncState()       → 如果 B 的 syncState 存在不做事
      startListening(B.uid)       → 新 listener 建立，Firebase 立即觸發一次 snapshot
    if cloudHasData → performFullSync()   ← 第一次 fullSync
  
  listener 初始 snapshot 觸發：
    cloudVersion > localVersion(0)
    pendingChanges 為空 → 又觸發 performFullSync()  ← 第二次 fullSync（重複）
```

**問題**：B 登入時會呼叫兩次 `performFullSync()`，浪費但資料正確。  

**修改建議**：`initializeSync()` 完成後的 `handleSignInSuccess` 已在下載，若 listener 的初始 snapshot 發現 `isDownloading == true` 應跳過，避免重複。  
或在 `initializeSync()` 中，將當前 cloudVersion 寫入 `localVersion`，讓 listener 的初始 snapshot 不觸發重複 sync。

---

## Debug Log 追蹤指引

Debug log 已加入 `HybridSyncListener.swift`，在 Xcode console 搜尋 `[HybridSyncListener]`：

| Log 關鍵字 | 意義 |
|-----------|------|
| `startListening` | listener 開始，顯示 userId 與當前 localVersion |
| `snapshot 收到` | Firebase 有資料到達，顯示 cloudVersion / localVersion / pendingCount |
| `版本未變更，跳過` | cloudVersion <= localVersion，listener 正確跳過 |
| `版本變更` | 有新資料要處理，顯示完整 pendingChanges |
| `處理中，跳過` | ⚠️ Bug 1 發生，cloudVersion X 被丟棄 |
| `增量同步開始` | 進行 incremental sync，顯示哪些 ID |
| `pendingChanges 為空，觸發全量同步` | 觸發 fullSync（overflow 或初次連線） |
| `localVersion 更新為` | 成功完成一輪同步 |
| `stopListening` | listener 停止 |
| `resetLocalVersion` | version 重設（登出時） |

### 測試步驟
1. Device A、B 都登入同一 Pro 帳號
2. 兩台都開著 app，觀察 Device B 的 log 是否出現 `startListening`
3. Device A 新增一筆 Session
4. 觀察 Device B 的 log：
   - 應出現 `snapshot 收到 — cloudVersion: N+1`
   - 應出現 `版本變更` 然後 `增量同步開始`
   - 若出現 `版本未變更，跳過` → 確認 localVersion 是否有問題
   - 若沒有任何 `[HybridSyncListener]` log → listener 未啟動，檢查 `shouldListen` 條件

---

## 修改優先順序

1. **先跑 Debug log 確認問題點**
2. **Bug 1**：修 isProcessing（影響所有即時同步場景）
3. **Bug 2**：修 fullUploadAllData 錯誤處理（影響首次登入有本地資料的情境）
4. **Account Switching 重複 fullSync**：避免浪費
5. **Bug 3**：localVersion 加 userId（防禦性修改）

# Pro 多裝置即時同步 — 問題清單與修改計畫

> 建立日期：2026-03-31
> 最後更新：2026-04-01
> 分支：feature/SyncFirebaseData

---

## 架構說明

Device 做任何 CRUD
  → Firestore batch 寫入（entity + syncState，原子操作）
  → 其他裝置的 HybridSyncListener 收到 version 變化
  → 增量同步（有 ID）或全量同步（pendingChanges 空）
  → 發送 `.syncDidComplete` 通知 → Repository 重新 fetch → UI 刷新

**Pro 會員**：即時多裝置同步（Listener 啟動）
**Free 會員**：單裝置，裝置衝突偵測，無 Listener

---

## 情境分析：所有帳號登入/登出/切換狀況

### 帳號登入/登出/切換

| # | 情境 | 狀態 | 說明 |
|---|------|------|------|
| 1 | Guest → 首次登入（本地無資料） | ✅ | — |
| 2 | Guest → 首次登入（本地有資料） | ⚠️ | 見 Bug 2；上傳失敗仍標 synced |
| 3 | App 重啟（已登入） | ✅ | handleAuthStateChanged 重新 initializeSync |
| 4 | Free 第二台裝置登入 | ✅ | checkDeviceId + 衝突 alert |
| 5 | A 帳號登出 → B 帳號登入（同裝置） | ⚠️ | 見 Bug 4；雙重 fullSync 浪費但資料正確 |
| 6 | Google / Apple 同 email（不同 provider） | ✅ by design | 各 provider 獨立帳號，不做合併 |
| 7 | Apple 撤銷後重新登入 | ✅ | userIdentifier 穩定，Firebase UID 不變 |
| 8 | Apple 同帳號兩台，Firebase 建兩個 UID | ⚠️ | 待診斷；見 Apple UID 問題章節 |
| 9 | 刪除帳號（操作裝置） | ✅ | Cloud Function 清理 + 本地清除 |
| 10 | 刪除帳號，另一台裝置在線 | ❌ | 見 Bug 5；listener 拿到 permission denied 但無通知 |
| 11 | 刪除帳號，另一台裝置在背景 | ❌ | 見 Bug 5；回前景任何操作應跳通知 |
| 12 | 刪除帳號，另一台裝置離線 | ❌ | 見 Bug 5；上線後 upload 失敗應跳通知 |
| 13 | Firebase Auth token 失效（非主動登出） | ⚠️ | 見 Bug 5D；靜默降為 Guest，無解釋 |

### 會員等級變更

| # | 情境 | 狀態 | 說明 |
|---|------|------|------|
| 14 | Free → Pro 升級（本機） | ✅ | ProfileView 呼叫 setMembership + startListening |
| 15 | Pro → Free 降級（本機） | ✅ | ProfileView 呼叫 stopListening |
| 16 | 升級 Pro，另一台裝置 listener 未啟動 | ❌ | 見 Bug 6；membership 變更不跨裝置推送 |
| 17 | 降級 Free，另一台裝置 listener 未停止 | ⚠️ | 見 Bug 6；listener 繼續跑但無資料問題 |
| 18 | Pro 到期自動降級，兩台 listener 未停 | ⚠️ | 見 Bug 6；只在 App 啟動時檢查到期 |

### 多裝置日常同步（Pro）

| # | 情境 | 狀態 | 說明 |
|---|------|------|------|
| 19 | 手機1 新增/修改/刪除 → 手機2 即時同步 | ✅ | Bug 0 修後正常 |
| 20 | 手機1 快速連續操作，手機2 正在同步中 | ⚠️ | 見 Bug 1；第二次更新被丟棄 |
| 21 | 兩台同時修改同一筆資料（衝突） | ⚠️ | 見 Bug 7；LWW 以 updatedAt 決定，本機時鐘可能不準 |
| 22 | 兩台都離線各自修改同一筆 → 先後上線 | ⚠️ | 見 Bug 7；LWW 結果依上線順序 + updatedAt |
| 23 | 手機1 離線操作 → 上線後同步到手機2 | ✅ | CDPendingSyncOperation + NetworkMonitor |
| 24 | 手機2 在背景，手機1 修改 → 手機2 回前景 | ✅ | scenePhase startListening + 初始 snapshot |
| 25 | 離線大量操作（>50 筆）→ 手機2 全量同步 | ✅ | pendingChanges overflow 觸發 fullSync |

### 資料合併（首次登入含本地資料）

| # | 情境 | 狀態 | 說明 |
|---|------|------|------|
| 26 | A 未登入有本地資料，B 已登入，A 登入 | ⚠️ | A 上傳後 B 同步；Bug 2 未修前失敗仍標 synced |
| 27 | A、B 各自有本地資料，同帳號先後登入 | ⚠️ | 兩份都上傳合併；Bug 2 修好前部分失敗 |
| 28 | A 有本地資料，雲端也有資料（老用戶換機） | ✅ | fullUploadAllData + performFullSync LWW 合併 |
| 29 | A 登出再登入（資料不重複） | ✅ | clearAllLocalData 後重新下載，不重複 |
| 30 | A 登入時網路不穩，上傳失敗 | ❌ | 見 Bug 2；失敗資料被標 synced，永遠不重試 |
| 31 | A 登入上傳，同時 B 也在操作（race） | ⚠️ | Bug 1 修好後可覆蓋此問題 |

### 離線 / 網路 / App 生命週期

| # | 情境 | 狀態 | 說明 |
|---|------|------|------|
| 32 | 離線操作後重新連線 | ✅ | CDPendingSyncOperation queue + NetworkMonitor |
| 33 | App 背景/前景切換 | ✅ | TilliApp.onChange(scenePhase) 重啟 listener |

---

## Bug 清單

### Bug 0 ✅ 已修（2026-03-31）：增量同步完成後未通知 UI 刷新

**檔案**：`Tilli/Data/Sync/HybridSyncListener.swift`（`processChanges` 結尾）

**問題**：`performIncrementalSync()` 下載資料到 CoreData 後，沒有發送 `.syncDidComplete` 通知。所有 Repository 靠此通知重新 fetch CoreData 並更新 `@Published` 陣列。UI 不刷新，直到使用者主動新增/修改資料才看到同步結果。

**修改**：在 `localVersion = cloudVersion` 後加：
```swift
NotificationCenter.default.post(name: .syncDidComplete, object: nil)
```

---

### Bug 1（待修，高優先）：`isProcessing` 直接丟棄並發更新

**檔案**：`Tilli/Data/Sync/HybridSyncListener.swift:125`

**問題**：Device A 快速做兩次修改（version 6 → 7），Device B 正在處理 version 6 時，version 7 的 snapshot 觸發但被 `return` 丟棄。若 Device A 之後沒有第 3 次修改，version 7 的資料永遠不同步到 Device B，直到 app 重啟或背景/前景切換。

**修改**：保留最新被跳過的版本，處理完當前後補做：
```swift
private var pendingVersion: Int?
private var pendingChangesCache: [String: [String]] = [:]

guard !isProcessing else {
    if cloudVersion > (pendingVersion ?? 0) {
        pendingVersion = cloudVersion
        pendingChangesCache = pendingChanges
    }
    return
}

isProcessing = true
defer {
    isProcessing = false
    if let next = pendingVersion, next > localVersion {
        let nextChanges = pendingChangesCache
        pendingVersion = nil
        pendingChangesCache = [:]
        Task { await self.processChanges(pendingChanges: nextChanges, cloudVersion: next) }
    }
}
```

---

### Bug 2（待修，中優先）：`fullUploadAllData` 標記 synced 不區分成功/失敗

**檔案**：`Tilli/Data/Sync/SyncManager.swift:908-926`

**觸發時機**：Guest 有本地資料 → 首次登入時，`handleSignInSuccess` 呼叫 `fullUploadAllData()`

**問題**：每個 entity 上傳若拋錯，catch 後繼續執行，但最後統一將所有 entity 標為 `"synced"`。上傳失敗的資料永遠不重試，Device B 看不到這筆資料。

**修改**：個別標記，只有成功才標 synced，失敗維持 pending 等 `processPendingQueue` 重試：
```swift
for session in sessions {
    do {
        try await uploader.uploadSessionWithChildren(session.toModel())
        session.setValue("synced", forKey: "syncStatus")  // 成功才標
    } catch {
        print("❌ fullUpload Session 失敗: \(session.id) - \(error)")
        // 維持 pending，等 processPendingQueue 重試
    }
}
// Categories、Products、Transactions、InventoryChanges 同樣處理
// 移除最後的統一 setValue("synced") 迴圈
```

---

### Bug 3（待修，低優先）：`localVersion` 無 userId 區隔

**檔案**：`Tilli/Data/Sync/HybridSyncListener.swift:28`

**問題**：`UserDefaults` key 固定為 `"syncVersion"`，不分帳號。帳號切換時 `resetLocalVersion()` 雖然設為 0，但若未來登入流程調整，可能造成版本比對錯誤（localVersion 為舊帳號的值）。

**修改**：
```swift
private var currentUserId: String = ""

func startListening(userId: String) {
    currentUserId = userId
    stopListening()
    // ...
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

### Bug 4（待修，低優先）：帳號切換時雙重 fullSync

**觸發時機**：A 帳號登出 → B 帳號登入（同裝置）

**問題**：
```
handleSignInSuccess:
  cloudHasData = true → performFullSync()        ← 第 1 次

listener 初始 snapshot 觸發（cloudVersion N > localVersion 0）：
  pendingChanges 為空 → performFullSync()         ← 第 2 次（完全重複）
```
浪費流量與時間，但資料正確。

**修改**：`initializeSync()` 結束前，將當下的 cloudVersion 寫入 `localVersion`，讓 listener 初始 snapshot 的版本比對不觸發重複 sync。需要在 `initializeSyncState()` 讀取現有 syncState 的 version 並寫入。

---

### Bug 5 ❌ 未實作：帳號在其他裝置被刪除，無通知機制

**觸發時機**：情境 10、11、12、13

**問題**：帳號刪除後，另一台裝置：
- Listener 收到 `permission denied` error → 目前只 print log，使用者看到 app 正常但資料不再同步
- 任何 CRUD 操作 → Firestore 返回 `permission denied` → 標 retryCount，最多重試 3 次後標 error，無通知
- Firebase Auth token 失效 → `setupAuthStateListener` 收到 nil → `setupLocalGuest()` 靜默切換，無解釋

**最佳解**：統一 Notification 觸發點 + Alert 顯示

**步驟 1**：新增 Notification name
```swift
// SyncManager.swift
extension Notification.Name {
    static let accountInvalidatedOnOtherDevice = Notification.Name("accountInvalidatedOnOtherDevice")
}
```

**步驟 2**：`HybridSyncListener` error handler 偵測 permission denied
```swift
// handleSnapshotUpdate
if let error = error {
    let nsError = error as NSError
    if nsError.domain == "FIRFirestoreErrorDomain",
       nsError.code == 7 || nsError.code == 16 {
        // permission denied (7) 或 unauthenticated (16)
        NotificationCenter.default.post(name: .accountInvalidatedOnOtherDevice, object: nil)
    }
    print("❌ [HybridSyncListener] 監聽錯誤 - \(error)")
    return
}
```

**步驟 3**：`SyncManager.processPendingQueue` 偵測同樣 error
```swift
} catch {
    let nsError = error as NSError
    if nsError.domain == "FIRFirestoreErrorDomain",
       nsError.code == 7 || nsError.code == 16 {
        NotificationCenter.default.post(name: .accountInvalidatedOnOtherDevice, object: nil)
        return  // 停止處理佇列
    }
    op.retryCount += 1
    // ...
}
```

**步驟 4**：`AuthenticationManager` 區分主動/被動登出
```swift
private var isSigningOut = false  // 新增 flag

func signOut() {
    isSigningOut = true
    // ... 現有登出邏輯
}

// setupAuthStateListener 收到 nil 時
} else {
    if !isSigningOut {
        // 被動失效 → 顯示提示，非靜默切換
        NotificationCenter.default.post(name: .accountInvalidatedOnOtherDevice, object: nil)
    }
    isSigningOut = false
    setupLocalGuest()
}
```

**步驟 5**：`TilliApp` 監聽並顯示 Alert
```swift
.onReceive(NotificationCenter.default.publisher(for: .accountInvalidatedOnOtherDevice)) { _ in
    showAccountInvalidatedAlert = true
}
.alert("帳號已失效", isPresented: $showAccountInvalidatedAlert) {
    Button("確認") {
        authenticationManager.signOut()
    }
} message: {
    Text("此帳號已在其他裝置被刪除或登入狀態已失效，將自動登出並清除本地資料。")
}
```

---

### Bug 6 ❌ 未實作：會員等級變更不跨裝置同步

**觸發時機**：情境 16、17、18

**問題**：
- 手機1 升級 Pro → 手機2 的 `currentMembership` 仍是 `.free` → listener 不啟動
- 手機1 降級 Free → 手機2 listener 繼續跑（浪費，但無資料問題）
- Pro 到期 → 只有 App 啟動時的 `handleAuthStateChanged` 會檢查，跑中不會停

**最佳解**：App 回前景時重新讀取 Firestore userProfile，更新 membership 並決定 listener 狀態。不需要額外 listener，簡單可靠。

```swift
// AuthenticationManager.swift - 新增方法
func refreshMembershipIfNeeded() async {
    guard let uid = currentUser?.uid else { return }
    guard let profile = try? await userRepository.getUser(uid: uid) else { return }

    var updated = profile
    if updated.isProExpired {
        updated.membership = .free
    }

    guard updated.membership != currentUser?.membership else { return }

    currentUser?.membership = updated.membership
    SyncManager.shared.setMembership(updated.membership)

    if updated.membership == .pro {
        SyncManager.shared.startListening()
    } else {
        SyncManager.shared.stopListening()
    }
}

// TilliApp.swift - 在 scenePhase .active 的 handler 加入
Task {
    await authenticationManager.refreshMembershipIfNeeded()
}
```

---

### Bug 7 ⚠️ LWW 衝突時 `updatedAt` 使用本機時間，可能選錯版本

**觸發時機**：情境 21、22（兩台同時或先後修改同一筆資料）

**問題**：上傳時若 `updatedAt` 用本機時間（`Date()`），兩台裝置時鐘若有差異（最多 1-2 分鐘），LWW 可能選到「舊」裝置的版本。

**最佳解**：確認 `FirestoreUploader` 的 update 方法是否已用 `FieldValue.serverTimestamp()`。若否，改用 server timestamp 讓 Firebase server 統一定時：
```swift
// FirestoreUploader - updateSession / updateCategory / updateProduct
batch.updateData([
    // ...
    "updatedAt": FieldValue.serverTimestamp(),  // 改為 server timestamp
], forDocument: ref)
```
注意：`uploadSession`（新增）可保留本機時間，只有 `update` 方法需要確認。

---

### Bug 8 ❌ 未修：`fetchSessionEntity` 靜默失敗，初始庫存整筆遺失（本地 + 雲端）

**檔案**：`Tilli/Data/Repositories/InventoryChangeRepository.swift`

**觸發時機**：新增商品並輸入初始庫存數量時，`AddNewProductViewModel.save()` 呼叫 `addChange(_:sessionId:)`

**問題根源**：`addChange` 一開始就 fetch session entity，若找不到就 `return`，整筆庫存不寫 CoreData，也不上傳 Firestore：

```swift
// InventoryChangeRepository.swift (addChange)
guard let sessionEntity = fetchSessionEntity(by: sessionId) else {
    print("Session not found for id: \(sessionId)")
    return  // ← 靜默失敗：CoreData 不寫、Firestore 不上傳
}
```

而 `fetchSessionEntity` 內部用 `try?`，fetch 拋錯也被吞掉：

```swift
private func fetchSessionEntity(by sessionId: UUID) -> CDSessionEntity? {
    // ...
    return try? context.fetch(request).first  // ← 任何錯誤都變 nil，無 log
}
```

**觸發條件**：`save()` 裡商品 (CDProductEntity) 在 CoreData commit 前，session entity 尚未存在，或 fetch 時 context 處於尚未存到 persistent store 的中間狀態，導致 fetch 到 nil。

**影響**：
- 新增商品的初始庫存（`reason: .purchase`）不寫入 CoreData → 本地庫存統計錯誤
- 同樣一筆資料不上傳 Firestore → 另一台裝置也看不到

**最佳解**：將 `fetchSessionEntity` 的靜默失敗改為可觀測失敗，並確保 CoreData context 在 fetch 前已 save：

```swift
// 修改 1：fetchSessionEntity 改用 try 並往上拋錯
private func fetchSessionEntity(by sessionId: UUID) throws -> CDSessionEntity? {
    let request: NSFetchRequest<CDSessionEntity> = CDSessionEntity.fetchRequest()
    request.predicate = NSPredicate(format: "id == %@", sessionId as CVarArg)
    return try context.fetch(request).first
}

// 修改 2：addChange 改用 do-catch 並 log 真實錯誤
func addChange(_ change: InventoryChangeModel, sessionId: UUID) {
    do {
        guard let sessionEntity = try fetchSessionEntity(by: sessionId) else {
            print("❌ [InventoryChangeRepo] session \(sessionId) 不存在，庫存未寫入")
            return
        }
        // ... 其餘不變
    } catch {
        print("❌ [InventoryChangeRepo] fetchSessionEntity 失敗: \(error)")
    }
}
```

---

### Bug 9 ❌ 未修：`fullUploadAllData` 靜默跳過 sessionId 為 nil 的庫存記錄

**檔案**：`Tilli/Data/Sync/SyncManager.swift`（`fullUploadAllData` 內的 InventoryChange 上傳段）

**觸發時機**：Guest 有本地庫存資料 → 首次登入時呼叫 `fullUploadAllData()`

**問題**：
```swift
// SyncManager.swift ~L868
if let sessionId = model.sessionId {
    try await uploader.uploadInventoryChange(model, sessionId: sessionId)
}
// else：整個 if 被跳過，沒有任何 log，資料不上傳
```

若有任何 `InventoryChangeModel` 的 `sessionId == nil`（例如 Bug 8 遺留下的異常資料，或未來其他路徑建立的 model），這筆庫存就永遠不會同步到 Firestore，另一台裝置看不到。

**最佳解**：改為明確的 guard + error log，確保問題可追蹤：

```swift
guard let sessionId = model.sessionId else {
    print("⚠️ [SyncManager] fullUpload InventoryChange 跳過：\(model.id)，sessionId 為 nil")
    continue
}
try await uploader.uploadInventoryChange(model, sessionId: sessionId)
```

---

### Bug 10 ⚠️ 低風險：`entity.update(from:)` 暫時將 sessionId 設為 nil

**檔案**：`Tilli/Data/CoreData/Entities/CDInventoryChangeEntity+CoreDataProperties.swift:42`
與 `Tilli/Data/Repositories/InventoryChangeRepository.swift`（`addChange` 約 L30-34）

**問題**：`update(from:)` 將 model 所有欄位寫入 entity，包括 `sessionId`。但 `AddNewProductViewModel` 建立的初始庫存 model 沒有 sessionId：

```swift
// AddNewProductViewModel.swift ~L432
let change = InventoryChangeModel(
    productId: product.id,
    change: initialStock,
    reason: .purchase,
    customReason: nil,
    timestamp: Date()
    // sessionId NOT set → nil
)
inventoryChangeRepository.addChange(change, sessionId: session.id)
```

在 `addChange` 內部：
```swift
entity.update(from: change, context: context)  // entity.sessionId = nil ← 暫時錯誤
// ...
entity.sessionId = sessionId                   // 覆蓋回正確值
saveContext()
```

**影響**：在單執行緒 MainActor 環境下，這兩行中間沒有 context save，最終結果正確。但若未來加入並發或 background context，這個短暫的 nil 狀態可能觸發 CoreData validation error。

**最佳解**：`update(from:)` 應排除 sessionId 欄位，或新增獨立的 `updateFields(from:)` 方法不處理關聯欄位：

```swift
// CDInventoryChangeEntity+CoreDataProperties.swift
func update(from model: InventoryChangeModel, context: NSManagedObjectContext) {
    self.id = model.id
    self.productId = model.productId
    self.change = Int64(model.change)
    self.reason = model.reason.rawValue
    self.customReason = model.customReason
    self.timestamp = model.timestamp
    self.updatedAt = model.updatedAt
    self.syncStatus = model.syncStatus
    // sessionId 不在這裡設定，由 caller 負責
}
```

---

## Debug 工具計畫

### 目標

在 Settings 隱藏頁面加入同步狀態檢視，用 `#if DEBUG` 包裹，上 App Store 自動不編譯，未來清除只需刪一個檔案 + 一個 call site。

### 顯示內容

| 資訊 | 來源 |
|------|------|
| Listener 是否啟動 | `HybridSyncListener.shared.isListening` |
| 本地版本號 | UserDefaults `syncVersion` |
| 最後同步時間 | `SyncManager.shared.lastSyncDate` |
| 當前 membership | `SyncManager.shared.currentMembership`（需改為 public） |
| Session / Category / Product pending / synced / error 筆數 | CoreData fetch by syncStatus |
| CDPendingSyncOperation 待上傳筆數 | CoreData fetch |
| 當前 Firebase UID | `Auth.auth().currentUser?.uid` |

### 實作方式

```swift
// Tilli/Debug/SyncDebugView.swift（新建）
#if DEBUG
struct SyncDebugView: View { ... }
#endif

// Settings 某層 NavigationLink（隱藏入口）
#if DEBUG
NavigationLink("🔧 Sync Debug") { SyncDebugView() }
#endif
```

---

---

## Apple Sign In 同帳號兩台建立兩個 Firebase UID

> 狀態：待診斷確認

### 現象

同一個 Apple ID 在兩台裝置登入，Firebase 建立了兩個不同的 UID，導致資料完全隔開無法同步。

### Swift 程式碼確認：無誤

```swift
// AuthenticationManager.swift:173-206
let nonce = randomNonceString()
currentNonce = nonce
request.requestedScopes = [.fullName, .email]
request.nonce = sha256(nonce)

let firebaseCredential = OAuthProvider.appleCredential(
    withIDToken: idTokenString,
    rawNonce: nonce,
    fullName: credential.fullName
)
Auth.auth().signIn(with: firebaseCredential)
```

標準實作，無問題。

### Apple 的 identity 機制

Apple Sign In 的 `identityToken`（JWT）中包含 `sub` claim（= `userIdentifier`）：
- 同一個 Apple ID + 同一個 App → 永遠固定，不受裝置影響
- Firebase 用 `sub` 對應 Firebase UID

理論上同一 Apple 帳號應永遠產生同一 Firebase UID。

### 可能原因（依可能性排序）

**原因 1（最可能）：Firebase Console Apple Sign In 設定不完整**

Console → Authentication → Sign-in method → Apple 需要設定：
- Team ID
- Key ID + p8 private key（server-side token 驗證用）
- Bundle ID

若設定錯誤，Firebase 無法驗證 `sub` claim，改用 email 識別使用者。不同裝置若 email 不一致（Apple 只在第一次授權傳 email）就會建兩個帳號。

**原因 2：Firebase Email Enumeration Protection 副作用**

Console → Authentication → Settings → Email Enumeration Protection
Firebase 2023 年新增功能，啟用時在某些 edge case 下即使 `sub` 相同也可能建新帳號（已知 Firebase bug）。

**原因 3：Apple email 傳遞行為**

Apple 只在第一次授權傳 email 和 fullName：
- Device 1 首次登入 → 傳 email
- Device 2 登入 → 不傳 email，只傳 `userIdentifier`

Firebase 設定有問題時會嘗試用 email 識別，但 email 為空 → 建新帳號。

### 診斷步驟

在 `handleAppleSignIn` 的 `signIn` 成功後加 log：

```swift
print("🍎 Apple userIdentifier: \(credential.user)")
print("🔥 Firebase UID: \(result.user.uid)")
print("📧 Firebase email: \(result.user.email ?? "nil")")
```

| Device 1 `credential.user` | Device 2 `credential.user` | Firebase UID | 結論 |
|-----------------------------|------------------------------|--------------|------|
| 相同 | 相同 | 不同 | Firebase Console 設定問題 |
| 相同 | 相同 | 相同 | 問題已解決或另有原因 |
| 不同 | — | — | 測試時使用了不同 Apple ID |

### 修復方向

確認診斷結果後：
- 若 Firebase 設定問題 → 補齊 Console 設定（Team ID / Key ID / p8）
- 若 Email Enumeration Protection → 嘗試關閉後測試，或改用 Account Linking 合併已分裂的帳號
- 已分裂的帳號（一個帳號兩筆資料）→ 需要 one-time migration script 合併

---

## 修改優先順序

| 優先 | Bug | 影響情境 | 嚴重度 |
|------|-----|---------|--------|
| 1 | **Apple UID 診斷**：加 log 確認根因 | 8 | 🔴 多裝置根本無法同步 |
| 2 | **Bug 5**：帳號刪除無通知 | 10-13 | 🔴 手機2 繼續使用已不存在帳號 |
| 3 | **Bug 8**：fetchSessionEntity 靜默失敗，初始庫存整筆遺失 | 新增商品 | 🔴 初始庫存不寫本地也不同步雲端 |
| 4 | **Bug 1**：isProcessing 丟棄更新 | 20、31 | 🟠 快速操作資料遺失 |
| 5 | **Bug 6**：會員等級不跨裝置同步 | 16-18 | 🟠 Pro 功能可能在手機2 不啟動 |
| 6 | **Bug 2**：fullUpload 失敗仍標 synced | 26、27、30 | 🟠 首次登入有本地資料時遺失 |
| 7 | **Bug 9**：fullUploadAllData 跳過 sessionId nil 的庫存 | 26、27 | 🟠 首次登入時庫存不上傳 |
| 8 | **Debug View 實作** | — | 🟡 診斷工具 |
| 9 | **Bug 7**：LWW server timestamp | 21、22 | 🟡 衝突時偶爾選錯版本 |
| 10 | **Bug 4**：帳號切換雙重 fullSync | 5 | 🟢 浪費流量，資料正確 |
| 11 | **Bug 10**：update(from:) 暫時將 sessionId 設 nil | 新增商品 | 🟢 防禦性修改，現行單執行緒無實際問題 |
| 12 | **Bug 3**：localVersion 無 userId 區隔 | — | 🟢 防禦性修改 |

---

## Debug Log 追蹤指引

Xcode console 搜尋 `[HybridSyncListener]`：

| Log | 意義 |
|-----|------|
| `startListening — userId: xxx, localVersion: N` | listener 啟動，確認 userId 與版本 |
| `snapshot 收到 — cloudVersion: N, localVersion: M` | Firebase 推送到達 |
| `版本未變更，跳過` | 正常，已是最新版本 |
| `版本變更 ... pendingChanges: {...}` | 有新資料，確認 ID 正確 |
| `處理中，跳過 cloudVersion: N` | ⚠️ Bug 1 觸發，N 被丟棄 |
| `增量同步開始` | 進行 incremental sync |
| `pendingChanges 為空，觸發全量同步` | fullSync（overflow 或初次連線） |
| `localVersion 更新為 N` | 同步完成 |
| `stopListening` | listener 停止（登出或降級） |
| `resetLocalVersion: N → 0` | 版本重設（登出時） |

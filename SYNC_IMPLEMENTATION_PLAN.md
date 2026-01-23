# CoreData + Firebase 同步實作規劃

## 目錄
1. [設計決策](#設計決策)
2. [架構總覽](#架構總覽)
3. [Firestore Schema 設計](#firestore-schema-設計)
4. [CoreData Schema 更新](#coredata-schema-更新)
5. [同步機制設計](#同步機制設計)
6. [登入流程與資料處理](#登入流程與資料處理)
7. [實作排序與任務清單](#實作排序與任務清單)
8. [錯誤處理](#錯誤處理)
9. [測試計畫](#測試計畫)

---

## 設計決策

| 項目 | 決策 | 說明 |
|------|------|------|
| 合併選項 | 不做 | 保持簡單，用戶選擇「使用雲端」或「使用本地」 |
| 圖片同步 | 同步 | 上傳至 Firebase Storage，需壓縮圖片 |
| 刪除策略 | Hard Delete | 真刪除 + Firestore onSnapshot 監聽 |
| 同步頻率 | 即時同步 | 每次操作即時同步 + 離線時排隊 |
| 登出處理 | 清除資料 | 登出後清除本地資料，回到匿名狀態 |

---

## 架構總覽

```
┌─────────────────────────────────────────────────────────────────┐
│                         App Layer                                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │
│  │ SessionRepo  │  │ ProductRepo  │  │TransactionRepo│  ...     │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘           │
│         │                 │                 │                    │
│         └────────────────┼─────────────────┘                    │
│                          ▼                                       │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                     SyncManager                              ││
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  ││
│  │  │UploadQueue  │  │DownloadMgr │  │ ConflictResolver    │  ││
│  │  └─────────────┘  └─────────────┘  └─────────────────────┘  ││
│  └─────────────────────────────────────────────────────────────┘│
│                          │                                       │
│         ┌────────────────┼────────────────┐                     │
│         ▼                ▼                ▼                     │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐             │
│  │   CoreData   │ │  Firestore   │ │Firebase      │             │
│  │   (Local)    │ │  (Remote)    │ │Storage       │             │
│  └──────────────┘ └──────────────┘ └──────────────┘             │
└─────────────────────────────────────────────────────────────────┘
```

### 核心元件

| 元件 | 職責 |
|------|------|
| **SyncManager** | 統一管理同步邏輯，協調上傳/下載/衝突處理 |
| **UploadQueue** | 管理待上傳的操作，支援離線排隊 |
| **DownloadManager** | 處理從 Firestore 下載資料 |
| **ConflictResolver** | 處理登入時的資料衝突 |
| **ImageSyncService** | 處理圖片的壓縮、上傳、下載 |

---

## Firestore Schema 設計

### Collection 結構

```
firestore/
├── users/{userId}                    # 用戶資料（已存在）
│   ├── uid: string
│   ├── email: string
│   ├── name: string
│   ├── photoURL: string?
│   ├── provider: string
│   ├── accountStatus: string
│   ├── membership: string
│   ├── expiryDate: timestamp?
│   ├── createdAt: timestamp
│   └── currentDeviceId: string?
│
├── sessions/{sessionId}              # 場次
│   ├── id: string (UUID)
│   ├── userId: string                # 所屬用戶
│   ├── title: string
│   ├── startDate: timestamp
│   ├── endDate: timestamp?
│   ├── dateType: string
│   ├── currency: string
│   ├── discountsData: string (JSON)
│   ├── createdAt: timestamp
│   └── updatedAt: timestamp
│
├── categories/{categoryId}           # 類別
│   ├── id: string (UUID)
│   ├── userId: string
│   ├── sessionId: string
│   ├── name: string
│   ├── sortOrder: number
│   ├── isDisabled: boolean
│   ├── createdAt: timestamp
│   └── updatedAt: timestamp
│
├── products/{productId}              # 產品
│   ├── id: string (UUID)
│   ├── userId: string
│   ├── sessionId: string
│   ├── categoryId: string
│   ├── categoryName: string
│   ├── name: string
│   ├── price: number
│   ├── stock: number
│   ├── note: string?
│   ├── imageURL: string?             # Firebase Storage URL
│   ├── isDisabled: boolean
│   ├── createdAt: timestamp
│   └── updatedAt: timestamp
│
├── transactions/{transactionId}      # 交易記錄
│   ├── id: string (UUID)
│   ├── userId: string
│   ├── sessionId: string
│   ├── sessionTitle: string
│   ├── itemsData: string (JSON)
│   ├── totalAmount: number
│   ├── currency: string
│   ├── paymentMethod: string
│   ├── discountType: string?
│   ├── discountValue: number?
│   ├── occurredAt: timestamp?
│   ├── timestamp: timestamp
│   └── createdAt: timestamp          # 交易記錄不更新，只有 createdAt
│
├── inventoryChanges/{changeId}       # 庫存異動
│   ├── id: string (UUID)
│   ├── userId: string
│   ├── sessionId: string
│   ├── productId: string
│   ├── change: number
│   ├── reason: string
│   ├── customReason: string?
│   ├── transactionId: string?
│   ├── timestamp: timestamp
│   └── createdAt: timestamp
│
└── qrCodes/{qrCodeId}                # QR Code
    ├── id: string (UUID)
    ├── userId: string
    ├── imageURL: string              # Firebase Storage URL
    ├── createdAt: timestamp
    └── updatedAt: timestamp
```

### Firestore 安全規則

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // 用戶資料：只能讀寫自己的
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }

    // 場次：只能讀寫自己的
    match /sessions/{sessionId} {
      allow read, write: if request.auth != null
        && resource.data.userId == request.auth.uid;
      allow create: if request.auth != null
        && request.resource.data.userId == request.auth.uid;
    }

    // 類別：只能讀寫自己的
    match /categories/{categoryId} {
      allow read, write: if request.auth != null
        && resource.data.userId == request.auth.uid;
      allow create: if request.auth != null
        && request.resource.data.userId == request.auth.uid;
    }

    // 產品：只能讀寫自己的
    match /products/{productId} {
      allow read, write: if request.auth != null
        && resource.data.userId == request.auth.uid;
      allow create: if request.auth != null
        && request.resource.data.userId == request.auth.uid;
    }

    // 交易記錄：只能讀取和創建自己的（不允許更新和刪除）
    match /transactions/{transactionId} {
      allow read: if request.auth != null
        && resource.data.userId == request.auth.uid;
      allow create: if request.auth != null
        && request.resource.data.userId == request.auth.uid;
      // 交易記錄不允許更新和刪除
    }

    // 庫存異動：只能讀取和創建自己的
    match /inventoryChanges/{changeId} {
      allow read: if request.auth != null
        && resource.data.userId == request.auth.uid;
      allow create: if request.auth != null
        && request.resource.data.userId == request.auth.uid;
    }

    // QR Code：只能讀寫自己的
    match /qrCodes/{qrCodeId} {
      allow read, write: if request.auth != null
        && resource.data.userId == request.auth.uid;
      allow create: if request.auth != null
        && request.resource.data.userId == request.auth.uid;
    }
  }
}
```

### Firebase Storage 結構

```
storage/
├── users/{userId}/
│   ├── profile/
│   │   └── avatar.jpg                # 用戶頭像（已存在）
│   ├── products/
│   │   └── {productId}.jpg           # 產品圖片
│   └── qrcodes/
│       └── {qrCodeId}.jpg            # QR Code 圖片
```

---

## CoreData Schema 更新

### 需要新增的欄位

#### CDSessionEntity
```swift
// 新增欄位
attribute userId: String              // 所屬用戶 ID
attribute updatedAt: Date             // 最後更新時間
attribute syncStatus: String          // "synced" | "pending" | "error"
```

#### CDCategoryEntity
```swift
// 新增欄位
attribute userId: String
attribute updatedAt: Date
attribute syncStatus: String
```

#### CDProductEntity
```swift
// 新增欄位
attribute userId: String
attribute updatedAt: Date
attribute syncStatus: String
attribute imageURL: String?           // Firebase Storage URL（上傳後填入）
```

#### CDTransactionEntity
```swift
// 新增欄位
attribute userId: String
attribute syncStatus: String          // 交易記錄沒有 updatedAt（不可修改）
```

#### CDInventoryChangeEntity
```swift
// 新增欄位
attribute userId: String
attribute syncStatus: String
```

#### CDQRCodeEntity
```swift
// 新增欄位
attribute userId: String
attribute updatedAt: Date
attribute syncStatus: String
attribute imageURL: String?
```

### 新增 Entity：CDPendingSyncOperation

用於離線時記錄待同步的操作。

```swift
entity CDPendingSyncOperation {
    attribute id: UUID
    attribute entityType: String      // "session" | "category" | "product" | ...
    attribute entityId: UUID
    attribute operationType: String   // "create" | "update" | "delete"
    attribute payload: Binary?        // JSON encoded data
    attribute createdAt: Date
    attribute retryCount: Int16
    attribute lastError: String?
}
```

---

## 同步機制設計

### 同步狀態定義

```swift
enum SyncStatus: String {
    case synced = "synced"      // 已同步
    case pending = "pending"    // 等待同步
    case error = "error"        // 同步失敗
}
```

### 即時同步流程

```
┌─────────────────────────────────────────────────────────────────┐
│                      用戶操作（新增/修改/刪除）                    │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                     1. 寫入 CoreData                             │
│                     設定 syncStatus = "pending"                  │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                     2. 檢查網路狀態                               │
└─────────────────────────────────────────────────────────────────┘
                      │                    │
                 有網路                   無網路
                      │                    │
                      ▼                    ▼
┌──────────────────────────┐    ┌──────────────────────────┐
│ 3a. 立即上傳到 Firestore  │    │ 3b. 加入 PendingSyncQueue │
│     成功後設定            │    │     等待網路恢復          │
│     syncStatus = "synced" │    │                          │
└──────────────────────────┘    └──────────────────────────┘
```

### 離線排隊機制

```swift
class SyncQueue {
    /// 新增待同步操作
    func enqueue(operation: SyncOperation)

    /// 網路恢復時，處理所有排隊的操作
    func processQueue() async

    /// 重試失敗的操作（最多 3 次）
    func retryFailed() async
}
```

### Firestore 監聽（接收其他裝置的變更）

```swift
class FirestoreListener {
    private var listeners: [ListenerRegistration] = []

    /// 開始監聽用戶的所有資料
    func startListening(userId: String) {
        // 監聽 Sessions
        let sessionListener = db.collection("sessions")
            .whereField("userId", isEqualTo: userId)
            .addSnapshotListener { snapshot, error in
                // 處理變更
            }
        listeners.append(sessionListener)

        // 監聽 Categories, Products, Transactions...
    }

    /// 停止監聽（登出時呼叫）
    func stopListening() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }
}
```

### 圖片同步服務

```swift
class ImageSyncService {
    /// 壓縮並上傳圖片
    func uploadImage(_ image: UIImage, path: String) async throws -> String {
        // 1. 壓縮圖片（目標 < 500KB）
        let compressed = compressImage(image, maxSizeKB: 500)

        // 2. 上傳到 Firebase Storage
        let ref = Storage.storage().reference().child(path)
        _ = try await ref.putDataAsync(compressed)

        // 3. 取得下載 URL
        let url = try await ref.downloadURL()
        return url.absoluteString
    }

    /// 下載圖片
    func downloadImage(url: String) async throws -> UIImage? {
        // 使用 Kingfisher 下載並快取
    }

    /// 壓縮圖片
    private func compressImage(_ image: UIImage, maxSizeKB: Int) -> Data {
        var compression: CGFloat = 0.8
        var data = image.jpegData(compressionQuality: compression)!

        while data.count > maxSizeKB * 1024 && compression > 0.1 {
            compression -= 0.1
            data = image.jpegData(compressionQuality: compression)!
        }

        return data
    }
}
```

---

## 登入流程與資料處理

### 流程圖

```
┌─────────────────────────────────────────────────────────────────┐
│                         用戶點擊登入                              │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Google/Apple 登入                           │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                   檢查是否有匿名時的本地資料                       │
│                   (userId == anonymousUID)                       │
└─────────────────────────────────────────────────────────────────┘
                      │                    │
                 有本地資料              無本地資料
                      │                    │
                      ▼                    ▼
┌──────────────────────────┐    ┌──────────────────────────┐
│  檢查雲端是否有該帳號資料  │    │  檢查雲端是否有該帳號資料  │
└──────────────────────────┘    └──────────────────────────┘
          │           │                  │           │
      有雲端資料   無雲端資料          有雲端資料   無雲端資料
          │           │                  │           │
          ▼           ▼                  ▼           ▼
    ┌─────────┐  ┌─────────┐      ┌─────────┐  ┌─────────┐
    │ 情況 D  │  │ 情況 C  │      │ 情況 B  │  │ 情況 A  │
    │ 衝突!   │  │ 上傳    │      │ 下載    │  │ 完成    │
    └─────────┘  └─────────┘      └─────────┘  └─────────┘
```

### 情況 A：無本地資料 + 無雲端資料（全新帳號）

```swift
// 直接完成登入，開始使用
// 後續操作會即時同步到雲端
```

### 情況 B：無本地資料 + 有雲端資料（舊帳號登入）

```swift
// 1. 顯示 Loading 畫面
// 2. 從 Firestore 下載所有資料
// 3. 下載圖片（使用 Kingfisher 快取）
// 4. 寫入 CoreData
// 5. 完成，進入主畫面
```

### 情況 C：有本地資料 + 無雲端資料（新帳號，Link 匿名資料）

```swift
// 1. 更新本地資料的 userId（從 anonymousUID 改為新 UID）
// 2. 上傳所有資料到 Firestore
// 3. 上傳圖片到 Firebase Storage
// 4. 刪除匿名帳號的 Firestore 資料（如果有）
// 5. 完成
```

### 情況 D：有本地資料 + 有雲端資料（衝突！）

```swift
// 1. 顯示衝突處理 UI
// 2. 用戶選擇：
//    - 選項 1：使用雲端資料 → 清除本地，下載雲端
//    - 選項 2：使用本地資料 → 清除雲端，上傳本地
//    - 選項 3：取消登入 → 回到匿名狀態
```

### 衝突處理 UI 設計

```swift
struct DataConflictView: View {
    let localDataSummary: DataSummary   // 本地資料摘要
    let cloudDataSummary: DataSummary   // 雲端資料摘要
    let onChoice: (ConflictChoice) -> Void

    var body: some View {
        VStack(spacing: 24) {
            // 標題
            Text("偵測到資料衝突")
                .font(.title2)
                .fontWeight(.bold)

            // 說明
            Text("您的本地裝置和雲端帳號都有資料，請選擇要保留哪一份")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // 資料對比
            HStack(spacing: 16) {
                // 本地資料卡片
                DataSummaryCard(
                    title: "本地資料",
                    summary: localDataSummary,
                    icon: "iphone"
                )

                // 雲端資料卡片
                DataSummaryCard(
                    title: "雲端資料",
                    summary: cloudDataSummary,
                    icon: "cloud"
                )
            }

            // 選項按鈕
            VStack(spacing: 12) {
                Button("使用雲端資料") {
                    onChoice(.useCloud)
                }
                .buttonStyle(.borderedProminent)

                Button("使用本地資料") {
                    onChoice(.useLocal)
                }
                .buttonStyle(.bordered)

                Button("取消登入") {
                    onChoice(.cancel)
                }
                .foregroundColor(.secondary)
            }

            // 警告
            Text("注意：未被選擇的資料將會永久刪除")
                .font(.caption)
                .foregroundColor(.orange)
        }
    }
}

struct DataSummary {
    let sessionCount: Int
    let productCount: Int
    let transactionCount: Int
    let lastUpdated: Date?
}

enum ConflictChoice {
    case useCloud
    case useLocal
    case cancel
}
```

### 登出流程

```swift
func signOut() {
    // 1. 停止 Firestore 監聽
    firestoreListener.stopListening()

    // 2. 清除所有本地資料
    clearAllLocalData()

    // 3. Firebase Auth 登出
    try? Auth.auth().signOut()

    // 4. 重新匿名登入
    await signInAnonymously()
}

private func clearAllLocalData() {
    // 刪除 CoreData 中所有資料
    let entities = ["CDSessionEntity", "CDCategoryEntity", "CDProductEntity",
                    "CDTransactionEntity", "CDInventoryChangeEntity",
                    "CDQRCodeEntity", "CDPendingSyncOperation"]

    for entityName in entities {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        try? context.execute(deleteRequest)
    }

    try? context.save()
}
```

---

## 實作排序與任務清單

### Phase 1：基礎建設（預估 2-3 天）

- [ ] **1.1 CoreData Schema Migration**
  - [ ] 新增 `userId`, `updatedAt`, `syncStatus` 欄位到所有 Entity
  - [ ] 新增 `imageURL` 欄位到 Product 和 QRCode
  - [ ] 新增 `CDPendingSyncOperation` Entity
  - [ ] 建立 Migration 腳本

- [ ] **1.2 Firestore Schema 建立**
  - [ ] 在 Firebase Console 建立 Collections
  - [ ] 設定 Security Rules
  - [ ] 設定 Storage Rules

- [ ] **1.3 建立基礎服務類別**
  - [ ] `SyncManager` - 同步管理器
  - [ ] `SyncStatus` enum
  - [ ] `NetworkMonitor` - 網路狀態監控

### Phase 2：上傳同步（預估 3-4 天）

- [ ] **2.1 資料上傳服務**
  - [ ] `FirestoreUploader` - 上傳資料到 Firestore
  - [ ] Session 上傳
  - [ ] Category 上傳
  - [ ] Product 上傳
  - [ ] Transaction 上傳
  - [ ] InventoryChange 上傳
  - [ ] QRCode 上傳

- [ ] **2.2 圖片上傳服務**
  - [ ] `ImageSyncService` - 圖片壓縮與上傳
  - [ ] 產品圖片上傳
  - [ ] QR Code 圖片上傳

- [ ] **2.3 離線排隊機制**
  - [ ] `SyncQueue` - 操作排隊
  - [ ] `CDPendingSyncOperation` CRUD
  - [ ] 網路恢復時自動處理排隊

- [ ] **2.4 整合到現有 Repository**
  - [ ] `SessionRepository` 整合同步
  - [ ] `ProductRepository` 整合同步
  - [ ] `TransactionRepository` 整合同步
  - [ ] `InventoryChangeRepository` 整合同步
  - [ ] `QRCodeRepository` 整合同步

### Phase 3：下載同步（預估 2-3 天）

- [ ] **3.1 資料下載服務**
  - [ ] `FirestoreDownloader` - 從 Firestore 下載資料
  - [ ] Session 下載並寫入 CoreData
  - [ ] Category 下載
  - [ ] Product 下載
  - [ ] Transaction 下載
  - [ ] InventoryChange 下載
  - [ ] QRCode 下載

- [ ] **3.2 圖片下載服務**
  - [ ] 使用 Kingfisher 下載並快取
  - [ ] 下載後更新 CoreData 的 imageData

- [ ] **3.3 完整同步功能**
  - [ ] `fullSync()` - 完整同步所有資料
  - [ ] 進度回報 UI

### Phase 4：登入流程整合（預估 3-4 天）

- [ ] **4.1 登入狀態檢測**
  - [ ] 檢測本地是否有匿名資料
  - [ ] 檢測雲端是否有帳號資料
  - [ ] 判斷屬於哪種情況（A/B/C/D）

- [ ] **4.2 情況 C 處理（Link 匿名資料）**
  - [ ] 更新本地資料的 userId
  - [ ] 上傳所有資料到雲端

- [ ] **4.3 情況 D 處理（衝突）**
  - [ ] `DataConflictView` UI
  - [ ] `DataSummary` 計算
  - [ ] 選項 1：使用雲端資料
  - [ ] 選項 2：使用本地資料
  - [ ] 選項 3：取消登入

- [ ] **4.4 登出處理**
  - [ ] 停止 Firestore 監聽
  - [ ] 清除本地資料
  - [ ] 重新匿名登入

- [ ] **4.5 整合到 AuthenticationManager**
  - [ ] 修改 `signInWithGoogle()`
  - [ ] 修改 `signOut()`
  - [ ] 新增 `handleDataConflict()`

### Phase 5：即時監聽（預估 2-3 天）

- [ ] **5.1 Firestore 監聽服務**
  - [ ] `FirestoreListener` - 監聽變更
  - [ ] Session 變更監聯
  - [ ] Category 變更監聽
  - [ ] Product 變更監聽
  - [ ] Transaction 變更監聽
  - [ ] InventoryChange 變更監聽
  - [ ] QRCode 變更監聽

- [ ] **5.2 變更處理**
  - [ ] 新增：寫入 CoreData
  - [ ] 修改：更新 CoreData
  - [ ] 刪除：從 CoreData 刪除

- [ ] **5.3 整合到 App 生命週期**
  - [ ] 登入時開始監聽
  - [ ] 登出時停止監聽
  - [ ] App 進入前台時檢查

### Phase 6：測試與優化（預估 2-3 天）

- [ ] **6.1 單元測試**
  - [ ] SyncManager 測試
  - [ ] Upload 測試
  - [ ] Download 測試
  - [ ] Conflict 測試

- [ ] **6.2 整合測試**
  - [ ] 登入流程測試
  - [ ] 多裝置同步測試
  - [ ] 離線/上線測試

- [ ] **6.3 效能優化**
  - [ ] 批次上傳優化
  - [ ] 圖片快取優化
  - [ ] 減少不必要的同步

---

## 錯誤處理

### 同步錯誤類型

```swift
enum SyncError: Error {
    case networkUnavailable          // 無網路
    case authenticationRequired      // 需要登入
    case permissionDenied            // 權限不足
    case quotaExceeded               // 配額超限
    case documentNotFound            // 文件不存在
    case dataCorrupted               // 資料損壞
    case imageUploadFailed           // 圖片上傳失敗
    case unknown(Error)              // 其他錯誤
}
```

### 錯誤處理策略

| 錯誤類型 | 處理策略 |
|----------|----------|
| 無網路 | 加入排隊，等待網路恢復 |
| 需要登入 | 提示用戶重新登入 |
| 權限不足 | 記錄錯誤，提示用戶 |
| 配額超限 | 暫停同步，提示用戶 |
| 文件不存在 | 從本地刪除（可能已在其他裝置刪除） |
| 資料損壞 | 記錄錯誤，跳過該筆資料 |
| 圖片上傳失敗 | 重試 3 次，失敗後標記錯誤 |

### 重試機制

```swift
func syncWithRetry(operation: () async throws -> Void, maxRetries: Int = 3) async throws {
    var lastError: Error?

    for attempt in 1...maxRetries {
        do {
            try await operation()
            return // 成功
        } catch {
            lastError = error

            // 指數退避
            let delay = pow(2.0, Double(attempt)) // 2, 4, 8 秒
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    throw lastError ?? SyncError.unknown(NSError())
}
```

---

## 測試計畫

### 測試場景清單

#### 登入流程測試

| 場景 | 預期結果 |
|------|----------|
| 無本地資料 + 無雲端資料 | 直接完成登入 |
| 無本地資料 + 有雲端資料 | 下載雲端資料 |
| 有本地資料 + 無雲端資料 | 上傳本地資料 |
| 有本地資料 + 有雲端資料 | 顯示衝突處理 UI |
| 衝突選擇「使用雲端」 | 清除本地，下載雲端 |
| 衝突選擇「使用本地」 | 清除雲端，上傳本地 |
| 衝突選擇「取消」 | 回到匿名狀態 |

#### 同步功能測試

| 場景 | 預期結果 |
|------|----------|
| 新增 Session | 即時同步到雲端 |
| 修改 Session | 即時同步到雲端 |
| 刪除 Session | 雲端同步刪除 |
| 離線新增 | 上線後自動同步 |
| 離線修改 | 上線後自動同步 |
| 其他裝置新增 | 本地即時更新 |
| 其他裝置刪除 | 本地即時刪除 |

#### 登出測試

| 場景 | 預期結果 |
|------|----------|
| 正常登出 | 清除所有本地資料 |
| 登出後重新登入同帳號 | 重新下載雲端資料 |
| 登出後登入不同帳號 | 下載新帳號的資料 |

#### 錯誤處理測試

| 場景 | 預期結果 |
|------|----------|
| 同步中斷網 | 操作加入排隊 |
| 上傳失敗重試 | 最多重試 3 次 |
| 圖片上傳失敗 | 標記錯誤，可重試 |

---

## 預估時程

| Phase | 內容 | 預估時間 |
|-------|------|----------|
| Phase 1 | 基礎建設 | 2-3 天 |
| Phase 2 | 上傳同步 | 3-4 天 |
| Phase 3 | 下載同步 | 2-3 天 |
| Phase 4 | 登入流程整合 | 3-4 天 |
| Phase 5 | 即時監聽 | 2-3 天 |
| Phase 6 | 測試與優化 | 2-3 天 |
| **總計** | | **14-20 天** |

---

## 附錄：檔案結構建議

```
Tilli/
├── Data/
│   ├── CoreData/
│   │   └── Tilli.xcdatamodeld        # 更新 Schema
│   ├── Repositories/
│   │   ├── SessionRepository.swift    # 整合同步
│   │   ├── ProductRepository.swift    # 整合同步
│   │   └── ...
│   └── Sync/                          # 新增資料夾
│       ├── SyncManager.swift          # 同步管理器
│       ├── SyncStatus.swift           # 同步狀態
│       ├── SyncQueue.swift            # 離線排隊
│       ├── FirestoreUploader.swift    # 上傳服務
│       ├── FirestoreDownloader.swift  # 下載服務
│       ├── FirestoreListener.swift    # 監聽服務
│       ├── ImageSyncService.swift     # 圖片同步
│       ├── ConflictResolver.swift     # 衝突處理
│       └── NetworkMonitor.swift       # 網路監控
├── View/
│   └── Sync/                          # 新增資料夾
│       ├── DataConflictView.swift     # 衝突處理 UI
│       ├── SyncProgressView.swift     # 同步進度 UI
│       └── DataSummaryCard.swift      # 資料摘要卡片
```

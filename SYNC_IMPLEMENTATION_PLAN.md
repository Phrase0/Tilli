# CoreData + Firebase 同步實作規劃

## 目錄
1. [設計決策](#設計決策)
2. [架構總覽](#架構總覽)
3. [循序圖與流程圖](#循序圖與流程圖)
4. [Firestore Schema 設計](#firestore-schema-設計)
5. [Firestore 索引設定](#firestore-索引設定)
6. [Model 共用策略](#model-共用策略)
7. [CoreData Schema 更新](#coredata-schema-更新)
8. [CDPendingSyncOperation 詳解](#cdpendingsyncoperation-詳解)
9. [圖片處理策略](#圖片處理策略)
10. [同步機制設計](#同步機制設計)
11. [**Hybrid Listener 費用優化**](#hybrid-listener-費用優化)
12. [衝突處理與刪除策略](#衝突處理與刪除策略)
13. [登入流程與資料處理](#登入流程與資料處理)
14. [網路監控](#網路監控)
15. [實作排序與任務清單](#實作排序與任務清單)
16. [錯誤處理](#錯誤處理)
17. [測試計畫](#測試計畫)

---

## 設計決策

| 項目 | 決策 | 說明 |
|------|------|------|
| 合併選項 | 不做 | 保持簡單，用戶選擇「使用雲端」或「使用本地」 |
| 圖片同步 | 同步 | 上傳至 Firebase Storage，需壓縮圖片 |
| 刪除策略 | Hard Delete + Cascade | 真刪除，Session 刪除時連帶刪除 Categories/Products/InventoryChanges，但保留 Transactions |
| 同步頻率 | 即時同步 | 每次操作即時同步 + 離線時排隊 |
| 登出處理 | 清除資料 | 登出後清除本地資料，回到匿名狀態 |
| 資料遷移 | 不需要 | App 尚未上架，無需遷移腳本 |
| sessionId 欄位 | 冗餘欄位 | Category/InventoryChange 加 sessionId 屬性（Firestore 無 relationship）|
| Binary 資料 | 維持 Binary | discountsData/itemsData 維持 Binary，同步時轉換為 JSON String |
| Transaction createdAt | 不需要 | 使用現有的 timestamp 欄位即可 |
| 圖片存儲 | Hybrid | 本地存 imageData + 雲端存 imageURL，優先讀本地 |
| Decimal 存儲 | Integer（分） | 金額乘 100 存為整數，避免浮點精度問題（100.50 → 10050）|
| Model 共用 | Domain Model + Extension | 不重建 Firebase Model，用 Extension 做轉換 |
| 圖片下載回寫 | 啟用 | Kingfisher 下載成功後回寫到 CoreData imageData |
| 運行時衝突 | Last-Write-Wins | 用 updatedAt 比較，較新的覆蓋較舊的 |
| 同步順序 | Batch + Parent-First | 使用 Firestore Batch Write，Parent 先同步，失敗時加入佇列重試 |
| 匿名 userId | Firebase Auth UID | 使用 Auth.auth().currentUser?.uid，所有資料都要存 userId |
| 孤立圖片 | 同步刪除 | 刪除 Product/QRCode 時一併刪除 Storage 圖片 |
| 網路監控 | Alamofire | 使用 NetworkReachabilityManager |
| 錯誤 UI | 顯示 + 重試 | syncStatus = error 時顯示錯誤圖示和重試按鈕 |
| **Listener 策略** | **Hybrid Listener** | **只監聽 syncState 文件（200-500 bytes），不監聽完整資料，節省約 73% 費用** |
| **資料讀取** | **本地優先** | **平時只讀 CoreData，Listener 收到通知後才下載變更的資料** |

---

## 架構總覽

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              App Layer (Views)                                │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌──────────────────────────┐   │
│  │SessionView │ │ProductView │ │  QRView    │ │   SyncableImageView     │   │
│  └─────┬──────┘ └─────┬──────┘ └─────┬──────┘ └────────────┬─────────────┘   │
│        │              │              │                      │                 │
├────────┼──────────────┼──────────────┼──────────────────────┼─────────────────┤
│        ▼              ▼              ▼                      │                 │
│  ┌─────────────┐┌─────────────┐┌─────────────┐             │                 │
│  │SessionRepo  ││ProductRepo  ││ QRCodeRepo  │             │                 │
│  │             ││             ││             │             │                 │
│  │InventoryChg ││             ││             │             │                 │
│  │ Repo        ││             ││             │             │                 │
│  └──────┬──────┘└──────┬──────┘└──────┬──────┘             │                 │
│         │              │              │                     │                 │
│    ┌────▼──────────────▼──────────────▼─────┐              │                 │
│    │           CoreData (Local)              │              │                 │
│    │  CDSession / CDCategory / CDProduct     │              │                 │
│    │  CDTransaction / CDInventoryChange      │              │                 │
│    │  CDQRCode / CDPendingSyncOperation      │              │                 │
│    └────────────────────┬───────────────────┘              │                 │
│                         │                                   │                 │
├─────────────────────────┼───────────────────────────────────┼─────────────────┤
│                    Sync Layer                                │                 │
│    ┌────────────────────▼───────────────────────────────────┼────────┐        │
│    │                 SyncManager (@MainActor)                │        │        │
│    │  ┌──────────────┐ ┌──────────────┐ ┌────────────────┐ │        │        │
│    │  │PendingQueue  │ │HybridSync    │ │  SyncStatus    │ │        │        │
│    │  │(offline ops) │ │Listener      │ │  Management    │ │        │        │
│    │  └──────┬───────┘ └──────┬───────┘ └────────────────┘ │        │        │
│    │         │                │                              │        │        │
│    │  ┌──────▼───────┐ ┌──────▼───────┐                     │        │        │
│    │  │Firestore     │ │Firestore     │                     │        │        │
│    │  │Uploader      │ │Downloader    │     ┌───────────────▼──┐     │        │
│    │  │  upload()    │ │  syncFrom()  │     │ImageSyncService  │     │        │
│    │  │  update()    │ │  fullSync()  │     │  upload/download │     │        │
│    │  │  delete()    │ │  LWW resolve │     └────────┬─────────┘     │        │
│    │  └──────┬───────┘ └──────┬───────┘              │               │        │
│    └─────────┼────────────────┼──────────────────────┼───────────────┘        │
│              │                │                      │                        │
├──────────────┼────────────────┼──────────────────────┼────────────────────────┤
│              ▼                ▼                      ▼                        │
│    ┌──────────────────────────────────┐  ┌──────────────────────┐             │
│    │      Firebase Firestore          │  │  Firebase Storage     │             │
│    │  sessions / categories / products│  │  users/{uid}/products │             │
│    │  transactions / inventoryChanges │  │  users/{uid}/qrcodes  │             │
│    │  qrCodes / syncState             │  │  profile_photos/      │             │
│    └──────────────────────────────────┘  └──────────────────────┘             │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 核心元件

| 元件 | 職責 |
|------|------|
| **SyncManager** | 統一管理同步邏輯，協調上傳/下載/離線排隊，@MainActor singleton |
| **FirestoreUploader** | 上傳/更新/刪除資料到 Firestore，管理 syncState 版本號 |
| **FirestoreDownloader** | 從 Firestore 下載資料，LWW 衝突解決，寫入 CoreData |
| **HybridSyncListener** | 輕量監聽 syncState 文件，觸發增量/全量下載 |
| **ImageSyncService** | 圖片壓縮（QR: 512px PNG / Product: 200px JPEG）、上傳、下載 |
| **SyncableImageView** | SwiftUI 元件，本地優先顯示 + Kingfisher 雲端下載 + 回寫 CoreData |
| **CDPendingSyncOperation** | CoreData Entity，儲存離線操作佇列（最多重試 3 次） |

---

## 循序圖與流程圖

### 1. 本地操作 + 線上同步（以新增 Product 為例）

```
┌──────┐     ┌──────────────┐     ┌────────────┐     ┌───────────────┐     ┌──────────┐
│ View │     │ProductRepo   │     │  CoreData   │     │ SyncManager   │     │Firestore │
└──┬───┘     └──────┬───────┘     └─────┬──────┘     └──────┬────────┘     └────┬─────┘
   │  addProduct()  │                    │                    │                   │
   │───────────────>│                    │                    │                   │
   │                │  save(entity)      │                    │                   │
   │                │  syncStatus=pending│                    │                   │
   │                │  updatedAt=Date()  │                    │                   │
   │                │───────────────────>│                    │                   │
   │                │                    │  saved             │                   │
   │                │<───────────────────│                    │                   │
   │                │                    │                    │                   │
   │                │  syncProduct(.create)                   │                   │
   │                │────────────────────────────────────────>│                   │
   │                │                    │                    │                   │
   │                │                    │                    │ [isOnline?]       │
   │                │                    │                    │───┐               │
   │                │                    │                    │   │ Yes           │
   │                │                    │                    │<──┘               │
   │                │                    │                    │                   │
   │                │                    │                    │ uploader.upload() │
   │                │                    │                    │──────────────────>│
   │                │                    │                    │                   │
   │                │                    │                    │ + updateSyncState │
   │                │                    │                    │  (version+1,      │
   │                │                    │                    │   pendingChanges)  │
   │                │                    │                    │──────────────────>│
   │                │                    │                    │                   │
   │                │                    │                    │  success          │
   │                │                    │                    │<──────────────────│
   │                │                    │                    │                   │
   │                │                    │  syncStatus=synced │                   │
   │                │                    │<───────────────────│                   │
   │                │                    │                    │                   │
```

### 2. 本地操作 + 離線排隊

```
┌──────┐     ┌──────────────┐     ┌────────────┐     ┌───────────────┐     ┌──────────────┐
│ View │     │  Repository  │     │  CoreData   │     │ SyncManager   │     │PendingQueue  │
└──┬───┘     └──────┬───────┘     └─────┬──────┘     └──────┬────────┘     └──────┬───────┘
   │  操作(CRUD)     │                    │                    │                    │
   │───────────────>│                    │                    │                    │
   │                │  save(entity)      │                    │                    │
   │                │  syncStatus=pending│                    │                    │
   │                │───────────────────>│                    │                    │
   │                │                    │                    │                    │
   │                │  sync(model, op)   │                    │                    │
   │                │────────────────────────────────────────>│                    │
   │                │                    │                    │                    │
   │                │                    │                    │ [isOnline?]        │
   │                │                    │                    │───┐                │
   │                │                    │                    │   │ No             │
   │                │                    │                    │<──┘                │
   │                │                    │                    │                    │
   │                │                    │                    │ enqueue(operation) │
   │                │                    │                    │───────────────────>│
   │                │                    │                    │                    │
   │                │                    │                    │  saved to CoreData │
   │                │                    │                    │<───────────────────│
   │                │                    │                    │                    │
   │                │                    │      ... 網路恢復 ...                    │
   │                │                    │                    │                    │
   │                │                    │                    │ processPendingQueue│
   │                │                    │                    │───────────────────>│
   │                │                    │                    │                    │
   │                │                    │                    │  forEach operation │
   │                │                    │                    │  → upload/update/  │
   │                │                    │                    │    delete Firestore│
   │                │                    │                    │                    │
   │                │                    │  syncStatus=synced │                    │
   │                │                    │<───────────────────│                    │
```

### 3. 遠端變更 → 本地同步（HybridSyncListener）

```
┌──────────┐     ┌──────────────────┐     ┌──────────────────┐     ┌────────────┐
│Firestore │     │HybridSyncListener│     │FirestoreDownloader│     │  CoreData   │
└────┬─────┘     └────────┬─────────┘     └────────┬─────────┘     └─────┬──────┘
     │                     │                         │                     │
     │ syncState changed   │                         │                     │
     │ (version+1)         │                         │                     │
     │────────────────────>│                         │                     │
     │                     │                         │                     │
     │                     │ [cloudVersion >          │                     │
     │                     │  localVersion?]          │                     │
     │                     │───┐                     │                     │
     │                     │   │ Yes                  │                     │
     │                     │<──┘                     │                     │
     │                     │                         │                     │
     │                     │ [pendingChanges          │                     │
     │                     │  has IDs?]               │                     │
     │                     │───┐                     │                     │
     │                     │   │ Yes → 增量下載       │                     │
     │                     │<──┘                     │                     │
     │                     │                         │                     │
     │                     │ syncIncrementalChanges() │                     │
     │                     │────────────────────────>│                     │
     │                     │                         │                     │
     │                     │                         │ fetch by ID         │
     │                     │                         │────────────────────>│
     │                     │                         │ (Firestore)         │
     │                     │                         │                     │
     │                     │                         │ LWW 比較 updatedAt   │
     │                     │                         │ → 更新 CoreData      │
     │                     │                         │────────────────────>│
     │                     │                         │                     │
     │                     │ [pendingChanges 為空     │                     │
     │                     │  但 version 變了?]      │                     │
     │                     │───┐                     │                     │
     │                     │   │ Yes → 全量下載       │                     │
     │                     │<──┘                     │                     │
     │                     │                         │                     │
     │                     │ fullSync()              │                     │
     │                     │────────────────────────>│                     │
     │                     │                         │                     │
     │                     │ 更新 localVersion        │                     │
     │                     │ (UserDefaults)           │                     │
```

### 4. 圖片同步（SyncableImageView）

```
┌───────────────────┐     ┌──────────────────┐     ┌────────────┐     ┌──────────────┐
│SyncableImageView  │     │   Kingfisher     │     │  CoreData   │     │Firebase      │
│(SwiftUI)          │     │                  │     │             │     │Storage       │
└────────┬──────────┘     └────────┬─────────┘     └─────┬──────┘     └──────┬───────┘
         │                         │                      │                   │
         │ [有本地 imageData?]      │                      │                   │
         │───┐                     │                      │                   │
         │   │ Yes                 │                      │                   │
         │<──┘                     │                      │                   │
         │ 直接顯示本地圖片          │                      │                   │
         │ (零流量)                 │                      │                   │
         │                         │                      │                   │
         │ [無本地, 有 imageURL?]   │                      │                   │
         │───┐                     │                      │                   │
         │   │ Yes                 │                      │                   │
         │<──┘                     │                      │                   │
         │                         │                      │                   │
         │  KFImage(url)           │                      │                   │
         │────────────────────────>│                      │                   │
         │                         │  download image      │                   │
         │                         │─────────────────────────────────────────>│
         │                         │                      │                   │
         │                         │  image data          │                   │
         │                         │<─────────────────────────────────────────│
         │  顯示圖片               │                      │                   │
         │<────────────────────────│                      │                   │
         │                         │                      │                   │
         │  onSuccess: 回寫 CoreData                      │                   │
         │  (imageData = downloaded)                      │                   │
         │───────────────────────────────────────────────>│                   │
         │  (不改 syncStatus,                             │                   │
         │   這只是本地快取)                               │                   │
         │                         │                      │                   │
         │ [無本地, 無 imageURL]    │                      │                   │
         │───┐                     │                      │                   │
         │   │                     │                      │                   │
         │<──┘                     │                      │                   │
         │ 顯示 placeholder        │                      │                   │
```

### 5. 整體架構流程圖

```
┌─────────────────────────────────────────────────────────────────┐
│                          App 啟動                                │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│              AuthenticationManager.signInAnonymously()           │
│              → 取得 userId (anonymous UID)                       │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│              SyncManager.initializeSync()                        │
│              → initializeSyncState (Firestore)                   │
│              → startListening (HybridSyncListener)               │
│              → startNetworkMonitoring                             │
└────────────────────────────┬────────────────────────────────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
    ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐
    │ 用戶本地操作  │  │ 遠端變更通知  │  │ 網路狀態變更     │
    │ (Repository) │  │(Listener)   │  │(NetworkMonitor) │
    └──────┬──────┘  └──────┬──────┘  └────────┬────────┘
           │                │                   │
           ▼                ▼                   ▼
    ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐
    │ 寫入CoreData │  │ Downloader  │  │ 恢復連線:        │
    │ + 觸發Sync   │  │ + LWW解衝突 │  │ processPending  │
    │ (上傳/離線Q) │  │ → CoreData  │  │ Queue           │
    └─────────────┘  └─────────────┘  └─────────────────┘
```

---

## Firestore Schema 設計

### Collection 結構

> 標註說明：✅ 現有 | 🆕 新增 | 🔄 轉換格式 | 📝 備註

```
firestore/
├── users/{userId}                    # 用戶資料（已存在，不在此次同步範圍）
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
│   ├── id: string (UUID)             ✅ 現有
│   ├── userId: string                🆕 新增
│   ├── title: string                 ✅ 現有
│   ├── startDate: timestamp          ✅ 現有
│   ├── endDate: timestamp?           ✅ 現有
│   ├── dateType: string              ✅ 現有
│   ├── currency: string              ✅ 現有
│   ├── discountsData: string (JSON)  🔄 CoreData Binary → Firestore JSON String
│   ├── createdAt: timestamp          ✅ 現有
│   └── updatedAt: timestamp          🆕 新增
│   # 📝 categories 不存在於 Firestore（獨立 collection，用 sessionId 關聯）
│   # 📝 discounts 在 CoreData 是 [DiscountModel]，存為 discountsData Binary
│
├── categories/{categoryId}           # 類別
│   ├── id: string (UUID)             ✅ 現有
│   ├── userId: string                🆕 新增
│   ├── sessionId: string             🆕 新增（CoreData 用 relationship，Firestore 用 ID）
│   ├── name: string                  ✅ 現有
│   ├── sortOrder: number             ✅ 現有
│   ├── isDisabled: boolean           ✅ 現有
│   ├── createdAt: timestamp          ✅ 現有
│   └── updatedAt: timestamp          🆕 新增
│   # 📝 products 不存在於 Firestore（獨立 collection，用 categoryId 關聯）
│
├── products/{productId}              # 產品
│   ├── id: string (UUID)             ✅ 現有
│   ├── userId: string                🆕 新增
│   ├── sessionId: string             ✅ 現有
│   ├── categoryId: string            ✅ 現有
│   ├── categoryName: string          ✅ 現有
│   ├── name: string                  ✅ 現有
│   ├── price: number                 ✅ 現有
│   ├── stock: number                 ✅ 現有
│   ├── note: string?                 ✅ 現有
│   ├── imageURL: string?             🆕 新增（Firebase Storage URL）
│   ├── isDisabled: boolean           ✅ 現有
│   ├── createdAt: timestamp          🆕 新增
│   └── updatedAt: timestamp          🆕 新增
│   # 📝 imageData 不上傳（Binary 太大），改用 imageURL 指向 Storage
│
├── transactions/{transactionId}      # 交易記錄（不可修改）
│   ├── id: string (UUID)             ✅ 現有
│   ├── userId: string                🆕 新增
│   ├── sessionId: string             ✅ 現有
│   ├── sessionTitle: string          ✅ 現有
│   ├── itemsData: string (JSON)      🔄 CoreData Binary → Firestore JSON String
│   ├── totalAmount: number           ✅ 現有
│   ├── currency: string              ✅ 現有
│   ├── paymentMethod: string         ✅ 現有
│   ├── discountType: string?         ✅ 現有
│   ├── discountValue: number?        ✅ 現有
│   ├── occurredAt: timestamp?        ✅ 現有（補記帳的實際發生時間）
│   └── timestamp: timestamp          ✅ 現有（記錄建立時間）
│   # 📝 items 在 CoreData 是 [SummaryItemModel]，存為 itemsData Binary
│   # 📝 業務規則：Transaction 為 create-only（不可更新、不可刪除）
│   # 📝 Firestore Rules 允許 delete 是因為 Cascade Delete（刪 Session 時連帶刪除）
│
├── inventoryChanges/{changeId}       # 庫存異動
│   ├── id: string (UUID)             ✅ 現有
│   ├── userId: string                🆕 新增
│   ├── sessionId: string             🆕 新增（CoreData 用 relationship，Firestore 用 ID）
│   ├── productId: string             ✅ 現有
│   ├── change: number                ✅ 現有
│   ├── reason: string                ✅ 現有
│   ├── customReason: string?         ✅ 現有
│   ├── transactionId: string?        ✅ 現有
│   └── timestamp: timestamp          ✅ 現有
│   # 📝 不需要 createdAt（timestamp 即為建立時間）
│   # 📝 業務規則：InventoryChange 為 create + delete（已建立的記錄不可更新）
│
└── qrCodes/{qrCodeId}                # QR Code
    ├── id: string (UUID)             ✅ 現有
    ├── userId: string                🆕 新增
    ├── imageURL: string              🆕 新增（Firebase Storage URL）
    ├── createdAt: timestamp          ✅ 現有
    └── updatedAt: timestamp          🆕 新增
    # 📝 imageData 不上傳，改用 imageURL 指向 Storage
```

### CoreData vs Firestore 結構差異說明

| Model 屬性 | CoreData 存儲 | Firestore 存儲 | 說明 |
|-----------|--------------|----------------|------|
| Session.categories | relationship | 獨立 collection | Firestore 無 relationship，用 sessionId 關聯 |
| Session.discounts | `discountsData: Binary` | `discountsData: JSON String` | 同步時轉換格式 |
| Category.products | relationship | 獨立 collection | Firestore 無 relationship，用 categoryId 關聯 |
| Category.session | relationship | `sessionId: String` | 新增冗餘欄位 |
| Transaction.items | `itemsData: Binary` | `itemsData: JSON String` | 同步時轉換格式 |
| Product.imageData | Binary | 不上傳 | 改用 imageURL 指向 Storage |
| InventoryChange.session | relationship | `sessionId: String` | 新增冗餘欄位 |
| QRCode.imageData | Binary | 不上傳 | 改用 imageURL 指向 Storage |
| **Decimal 金額** | `Decimal` | `Integer（分）` | 乘 100 存整數，避免浮點精度問題 |

### Decimal 金額轉換策略

Firestore 沒有原生 Decimal 類型，為避免浮點精度問題，金額**乘 100 存為整數（分）**：

| 欄位 | CoreData | Firestore | 轉換 |
|------|----------|-----------|------|
| Product.price | `Decimal` (100.50) | `Integer` (10050) | × 100 |
| Transaction.totalAmount | `Decimal` (250.00) | `Integer` (25000) | × 100 |
| Transaction.discountValue | `Decimal?` (10.00) | `Integer?` (1000) | × 100 |
| SummaryItem.price | `Decimal` (50.00) | `Integer` (5000) | × 100 |
| Discount.value | `Decimal` (5.00) | `Integer` (500) | × 100 |

```swift
// 上傳到 Firestore：Decimal → Integer（分）
func decimalToCents(_ value: Decimal) -> Int {
    return NSDecimalNumber(decimal: value * 100).intValue
}

// 從 Firestore 下載：Integer（分）→ Decimal
func centsToDecimal(_ cents: Int) -> Decimal {
    return Decimal(cents) / 100
}

// 使用範例
let firestorePrice = decimalToCents(product.price)     // 100.50 → 10050
let localPrice = centsToDecimal(firestoreData["price"]) // 10050 → 100.50
```

### Firestore 安全規則

使用 Helper Functions 簡化規則，所有 Entity Collection 使用統一的權限模式：

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // ===== Helper Functions =====
    // 驗證是否為已登入的資料擁有者
    function isOwner() {
      return request.auth != null && resource.data.userId == request.auth.uid;
    }
    // 驗證寫入的資料是否屬於當前用戶
    function isOwnerWrite() {
      return request.auth != null && request.resource.data.userId == request.auth.uid;
    }
    // get 規則：文件可能已被刪除（resource == null），需允許讀取以偵測刪除
    function isOwnerOrDeleted() {
      return request.auth != null && (resource == null || resource.data.userId == request.auth.uid);
    }

    // ===== User Private Data (syncState) =====
    match /users/{userId}/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }

    // ===== Entity Collections =====
    // 共用邏輯：只能存取自己的資料（userId 欄位 == auth uid）
    // get 使用 isOwnerOrDeleted() 以支援 HybridSyncListener 偵測已刪除的文件

    match /sessions/{docId} {
      allow get: if isOwnerOrDeleted();
      allow list: if isOwner();
      allow create: if isOwnerWrite();
      allow update, delete: if isOwner();
    }

    match /categories/{docId} {
      allow get: if isOwnerOrDeleted();
      allow list: if isOwner();
      allow create: if isOwnerWrite();
      allow update, delete: if isOwner();
    }

    match /products/{docId} {
      allow get: if isOwnerOrDeleted();
      allow list: if isOwner();
      allow create: if isOwnerWrite();
      allow update, delete: if isOwner();
    }

    // 交易記錄：業務邏輯為 create-only，但 Firestore 層允許完整 CRUD
    // （Cascade Delete 需要 delete 權限）
    match /transactions/{docId} {
      allow get: if isOwnerOrDeleted();
      allow list: if isOwner();
      allow create: if isOwnerWrite();
      allow update, delete: if isOwner();
    }

    // 庫存異動：業務邏輯為 create + delete，但 Firestore 層允許完整 CRUD
    match /inventoryChanges/{docId} {
      allow get: if isOwnerOrDeleted();
      allow list: if isOwner();
      allow create: if isOwnerWrite();
      allow update, delete: if isOwner();
    }

    match /qrCodes/{docId} {
      allow get: if isOwnerOrDeleted();
      allow list: if isOwner();
      allow create: if isOwnerWrite();
      allow update, delete: if isOwner();
    }
  }
}
```

> **設計重點**：
> - `isOwnerOrDeleted()` 允許 get 已刪除的文件（`resource == null`），讓 HybridSyncListener 可以偵測到文件已被其他裝置刪除
> - 所有 Entity Collection 都允許 delete，因為 Cascade Delete（刪 Session 連帶刪 Transaction/InventoryChange）需要此權限
> - 業務層面的 create-only / create+delete 限制由 App 端控制，不在 Firestore Rules 層面限制

### Firebase Storage 結構

```
storage/
├── profile_photos/
│   └── {uid}.jpg                     # 用戶頭貼（200x200 JPEG）
├── users/{userId}/
│   ├── products/
│   │   └── {productId}.jpg           # 產品圖片（200x200 JPEG）
│   └── qrcodes/
│       └── {qrCodeId}.png            # QR Code 圖片（512x512 PNG 無損）
```

> **注意**：QR Code 使用 `.png` 格式（無損），產品圖片和頭貼使用 `.jpg` 格式（壓縮）。頭貼路徑為 `profile_photos/{uid}.jpg`，不在 `users/` 下。

---

## Firestore 索引設定

### 為什麼需要索引？

Firestore 單欄位查詢會自動建立索引，但**複合查詢**（多欄位 + 排序）需要手動建立索引。

### 需要建立的複合索引

| Collection | 索引欄位 | 用途 |
|------------|---------|------|
| categories | `userId` (ASC) + `sessionId` (ASC) | 取得某場次的所有類別 |
| products | `userId` (ASC) + `sessionId` (ASC) | 取得某場次的所有產品 |
| products | `userId` (ASC) + `categoryId` (ASC) | 取得某類別的所有產品 |
| transactions | `userId` (ASC) + `sessionId` (ASC) + `timestamp` (DESC) | 取得某場次的交易記錄（按時間排序）|
| inventoryChanges | `userId` (ASC) + `sessionId` (ASC) + `timestamp` (DESC) | 取得某場次的庫存異動 |
| inventoryChanges | `userId` (ASC) + `productId` (ASC) + `timestamp` (DESC) | 取得某產品的庫存異動 |

### firestore.indexes.json

```json
{
  "indexes": [
    {
      "collectionGroup": "categories",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "userId", "order": "ASCENDING" },
        { "fieldPath": "sessionId", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "products",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "userId", "order": "ASCENDING" },
        { "fieldPath": "sessionId", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "products",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "userId", "order": "ASCENDING" },
        { "fieldPath": "categoryId", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "transactions",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "userId", "order": "ASCENDING" },
        { "fieldPath": "sessionId", "order": "ASCENDING" },
        { "fieldPath": "timestamp", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "inventoryChanges",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "userId", "order": "ASCENDING" },
        { "fieldPath": "sessionId", "order": "ASCENDING" },
        { "fieldPath": "timestamp", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "inventoryChanges",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "userId", "order": "ASCENDING" },
        { "fieldPath": "productId", "order": "ASCENDING" },
        { "fieldPath": "timestamp", "order": "DESCENDING" }
      ]
    }
  ]
}
```

### 部署索引

```bash
firebase deploy --only firestore:indexes
```

---

## Model 共用策略

### 架構設計

Domain Model 與 CoreData/Firestore **共用**，透過 Extension 做轉換：

```
┌─────────────────────────────────────────────────────────────┐
│                   Domain Model (共用)                        │
│            struct ProductModel: Codable { }                 │
│            struct QRCodeModel: Codable { }                  │
└─────────────────────────────────────────────────────────────┘
           │                              │
           ▼                              ▼
┌─────────────────────┐      ┌─────────────────────┐
│   CoreData 轉換      │      │   Firestore 轉換     │
│   init(entity:)     │      │   toFirestoreData() │
│   toEntity()        │      │   init(from:)       │
└─────────────────────┘      └─────────────────────┘
```

### 轉換 Extension 範例

```swift
// Domain Model（現有）
struct ProductModel: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var price: Decimal
    // ...
}

// MARK: - CoreData 轉換（現有）
extension ProductModel {
    init(entity: CDProductEntity) {
        self.id = entity.id
        self.name = entity.name
        self.price = entity.price.decimalValue
        // ...
    }
}

// MARK: - Firestore 轉換（新增）
extension ProductModel {
    /// 轉換為 Firestore Dictionary
    func toFirestoreData(userId: String) -> [String: Any] {
        return [
            "id": id.uuidString,
            "userId": userId,
            "name": name,
            "price": decimalToCents(price),  // Decimal → Integer（分）
            // ...
        ]
    }

    /// 從 Firestore Document 建立
    init?(from document: [String: Any]) {
        guard let idString = document["id"] as? String,
              let id = UUID(uuidString: idString),
              let name = document["name"] as? String,
              let priceCents = document["price"] as? Int
        else { return nil }

        self.id = id
        self.name = name
        self.price = centsToDecimal(priceCents)  // Integer（分）→ Decimal
        // ...
    }
}
```

### QRCodeModel（新增）

目前 QRCode 沒有 Domain Model，需要新增 `QRCodeModel.swift`：

```swift
//
//  QRCodeModel.swift
//  Tilli
//

import SwiftUI

struct QRCodeModel: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var imageData: Data?              // 本地圖片資料
    var imageURL: String?             // Firebase Storage URL
    var createdAt: Date = Date()

    // 計算屬性：取得 UIImage
    var image: UIImage? {
        get {
            guard let data = imageData else { return nil }
            return UIImage(data: data)
        }
        set {
            imageData = newValue?.jpegData(compressionQuality: 0.8)
        }
    }
}

// MARK: - CoreData 轉換
extension QRCodeModel {
    init(entity: CDQRCodeEntity) {
        self.id = entity.id
        self.imageData = entity.imageData
        self.createdAt = entity.createdAt
        self.imageURL = entity.imageURL
    }
}

// MARK: - Firestore 轉換
extension QRCodeModel {
    func toFirestoreData(userId: String) -> [String: Any] {
        var data: [String: Any] = [
            "id": id.uuidString,
            "userId": userId,
            "createdAt": createdAt,
            "updatedAt": Date()
        ]
        if let url = imageURL {
            data["imageURL"] = url
        }
        // imageData 不上傳（改用 imageURL 指向 Storage）
        return data
    }

    init?(from document: [String: Any]) {
        guard let idString = document["id"] as? String,
              let id = UUID(uuidString: idString),
              let createdAt = (document["createdAt"] as? Timestamp)?.dateValue()
        else { return nil }

        self.id = id
        self.createdAt = createdAt
        self.imageURL = document["imageURL"] as? String
        self.imageData = nil  // 圖片從 URL 下載後再填入
    }
}
```

### Firestore 轉換 Model 清單

所有 Firestore Extension 統一放在 `Data/Sync/ModelFirestoreExtensions.swift`：

| Model | Extension 方法 | 狀態 |
|-------|---------------|------|
| SessionModel | `toFirestoreData()` / `init?(from:)` | ✅ 已完成 |
| CategoryModel | `toFirestoreData()` / `init?(from:)` | ✅ 已完成 |
| ProductModel | `toFirestoreData()` / `init?(from:)` | ✅ 已完成 |
| TransactionModel | `toFirestoreData()` / `init?(from:)` | ✅ 已完成 |
| InventoryChangeModel | `toFirestoreData()` / `init?(from:)` | ✅ 已完成 |
| DiscountModel | `toFirestoreData()` / `init?(from:)` | ✅ 已完成 |
| SummaryItemModel | `toFirestoreData()` / `init?(from:)` | ✅ 已完成 |
| QRCodeModel | `toFirestoreData()` / `init?(from:)` | ✅ 已完成 |

---

## CoreData Schema 更新

### 設計說明

#### 為什麼需要 sessionId 冗餘欄位？

Firestore 是 NoSQL 文件資料庫，沒有關聯式資料庫的 relationship 概念：

```
CoreData (關聯式):
┌─────────────┐         ┌─────────────┐
│   Session   │◄────────│  Category   │
│             │ 1    N  │             │
└─────────────┘         └─────────────┘
      透過 relationship 連結

Firestore (文件式):
sessions/abc123          categories/xyz789
┌─────────────┐         ┌─────────────────┐
│ id: abc123  │         │ id: xyz789      │
│ title: "..."│         │ sessionId: abc123 │ ← 必須用 ID 綁定
└─────────────┘         └─────────────────┘
      沒有 relationship，用欄位值查詢
```

**決策：Category 和 InventoryChange 加冗餘的 sessionId 屬性**
- 查詢快、程式碼簡單
- CoreData 和 Firestore 結構一致
- UUID 只佔 16 bytes，成本極低

#### Binary vs JSON String 資料格式

**決策：維持 Binary，同步時轉換**

| 項目 | CoreData | Firestore | 轉換時機 |
|------|----------|-----------|---------|
| discountsData | Binary (Data) | JSON String | 同步時 |
| itemsData | Binary (Data) | JSON String | 同步時 |

理由：
- Binary 在本地讀寫更快
- 現有程式碼已用 Binary，改動成本高
- 同步轉換成本低（頻率不高）

```swift
// 同步到 Firestore 時轉換
if let discountsData = session.discountsData,
   let jsonString = String(data: discountsData, encoding: .utf8) {
    data["discountsData"] = jsonString
}

// 從 Firestore 下載時轉換回 Binary
if let jsonString = doc.get("discountsData") as? String,
   let data = jsonString.data(using: .utf8) {
    cdSession.discountsData = data
}
```

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
attribute sessionId: UUID             // 冗餘欄位，給 Firestore 用（保留 relationship）
attribute updatedAt: Date
attribute syncStatus: String
```

#### CDProductEntity
```swift
// 新增欄位
attribute userId: String
attribute createdAt: Date             // 產品建立時間
attribute updatedAt: Date
attribute syncStatus: String
attribute imageURL: String?           // Firebase Storage URL（上傳後填入）
// 保留 imageData: Binary（本地快取用）
```

#### CDTransactionEntity
```swift
// 新增欄位
attribute userId: String
attribute syncStatus: String
// 不需要 createdAt（使用現有的 timestamp）
// 不需要 updatedAt（交易記錄不可修改）
```

#### CDInventoryChangeEntity
```swift
// 新增欄位
attribute userId: String
attribute sessionId: UUID             // 冗餘欄位，給 Firestore 用（保留 relationship）
attribute syncStatus: String
// 不需要 createdAt（使用現有的 timestamp）
```

#### CDQRCodeEntity
```swift
// 新增欄位
attribute userId: String
attribute updatedAt: Date
attribute syncStatus: String
attribute imageURL: String?           // Firebase Storage URL
// 保留 imageData: Binary（本地快取用）
```

### 新增 Entity：CDPendingSyncOperation

用於離線時記錄待同步的操作（詳見下一章節）。

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

## CDPendingSyncOperation 詳解

### 用途

CDPendingSyncOperation 是一個**離線操作佇列**，用於處理無網路時的 CRUD 操作，確保資料最終一致性。

### 運作流程

```
使用者操作（新增/修改/刪除）
            │
            ▼
┌─────────────────────────────────────────────┐
│ 1. 寫入 CoreData (syncStatus = "pending")   │
└─────────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────────┐
│ 2. 檢查網路狀態                               │
└─────────────────────────────────────────────┘
       │                    │
   有網路                  無網路
       │                    │
       ▼                    ▼
┌──────────────┐    ┌──────────────────────────┐
│ 直接上傳     │    │ 3. 建立 PendingSyncOperation │
│ Firestore    │    │    記錄操作類型和資料         │
└──────────────┘    └──────────────────────────┘
       │                    │
       ▼                    ▼
syncStatus =           等待網路恢復
  "synced"                  │
                           ▼
                ┌──────────────────────────┐
                │ 4. 網路恢復，處理佇列      │
                │    依序執行所有待同步操作   │
                └──────────────────────────┘
                           │
                           ▼
                ┌──────────────────────────┐
                │ 5. 成功：刪除該筆 Operation │
                │    失敗：retryCount + 1    │
                └──────────────────────────┘
```

### 欄位說明

| 欄位 | 類型 | 說明 | 範例 |
|------|------|------|------|
| `id` | UUID | 操作的唯一識別碼 | `550e8400-e29b-41d4-a716-446655440000` |
| `entityType` | String | 操作的實體類型 | `"session"`, `"product"`, `"category"` |
| `entityId` | UUID | 被操作的實體 ID | 產品的 UUID |
| `operationType` | String | CRUD 操作類型 | `"create"`, `"update"`, `"delete"` |
| `payload` | Binary? | 操作的資料內容 (JSON) | `{"name": "新商品", "price": 100}` |
| `createdAt` | Date | 操作建立時間 | 用於排序執行順序 |
| `retryCount` | Int16 | 重試次數 | 0, 1, 2（最多 3 次）|
| `lastError` | String? | 最後一次錯誤訊息 | `"Network unavailable"` |

### 實作範例

```swift
// 1. 用戶在離線時新增商品
func addProduct(_ product: ProductModel) {
    // 寫入 CoreData，標記 syncStatus = "pending"
    let cdProduct = saveToLocalCoreData(product, syncStatus: .pending)

    if networkMonitor.isConnected {
        // 有網路：直接上傳
        Task {
            do {
                try await uploadToFirestore(product)
                cdProduct.syncStatus = "synced"
                try context.save()
            } catch {
                // 上傳失敗：加入佇列
                enqueuePendingOperation(for: product, operation: .create)
            }
        }
    } else {
        // 無網路：加入佇列
        enqueuePendingOperation(for: product, operation: .create)
    }
}

// 2. 建立 PendingSyncOperation
func enqueuePendingOperation(for product: ProductModel, operation: OperationType) {
    let pending = CDPendingSyncOperation(context: context)
    pending.id = UUID()
    pending.entityType = "product"
    pending.entityId = product.id
    pending.operationType = operation.rawValue
    pending.payload = try? JSONEncoder().encode(product)  // 序列化資料
    pending.createdAt = Date()
    pending.retryCount = 0
    pending.lastError = nil

    try? context.save()
}

// 3. 網路恢復時處理佇列
func processPendingQueue() async {
    let request = CDPendingSyncOperation.fetchRequest()
    request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

    guard let pendingOps = try? context.fetch(request) else { return }

    for op in pendingOps {
        do {
            switch op.operationType {
            case "create":
                try await uploadEntity(op)
            case "update":
                try await updateEntity(op)
            case "delete":
                try await deleteEntity(op)
            default:
                break
            }

            // 成功：刪除這筆 pending operation
            context.delete(op)

            // 更新原實體的 syncStatus
            updateEntitySyncStatus(entityType: op.entityType,
                                   entityId: op.entityId,
                                   status: .synced)

        } catch {
            // 失敗：增加 retryCount，記錄 error
            op.retryCount += 1
            op.lastError = error.localizedDescription

            if op.retryCount >= 3 {
                // 超過重試次數，標記原實體為 error 狀態
                updateEntitySyncStatus(entityType: op.entityType,
                                       entityId: op.entityId,
                                       status: .error)
            }
        }
    }

    try? context.save()
}
```

### 為什麼需要這個 Entity？

| 原因 | 說明 |
|------|------|
| **保證操作順序** | 按 createdAt 排序執行，避免邏輯錯誤（如先刪除再建立）|
| **錯誤追蹤** | 記錄失敗原因和重試次數，方便除錯 |
| **重試機制** | 網路不穩定時自動重試，最多 3 次 |
| **持久化** | 即使 App 被殺掉，重開後佇列仍在 |
| **離線優先** | 用戶操作立即生效（寫入本地），同步在背景進行 |

### 注意事項

1. **操作順序很重要**：必須按 createdAt 順序處理，否則可能出現「更新不存在的資料」
2. **payload 要完整**：確保 payload 包含足夠資訊重建操作
3. **delete 操作不需 payload**：只需要 entityId
4. **避免重複**：同一實體的多次 update 可以合併（只保留最新的）

---

## 圖片處理策略

### Hybrid 存儲方案

同時保留 `imageData` 和 `imageURL`，兼顧離線使用和雲端同步：

```
CoreData:
  - imageData: Data?    // 本地快取（優先使用）→ 零流量
  - imageURL: String?   // Firebase Storage URL（同步用）
```

### 讀取優先順序

```swift
// 優先使用本地，節省流量
func getProductImage(product: ProductModel) -> UIImage? {
    // 1. 優先使用本地 imageData（零流量）
    if let data = product.imageData, let image = UIImage(data: data) {
        return image
    }

    // 2. 若無本地資料，回傳 nil，由 View 層使用 Kingfisher 載入 URL
    return nil
}
```

### View 層實作：SyncableImageView（實際元件）

位於 `View/Components/SyncableImageView.swift`，是一個通用的 SwiftUI 元件：

```swift
struct SyncableImageView: View {
    let imageData: Data?        // 本地 CoreData 圖片資料
    let imageURL: String?       // Firebase Storage URL
    let entityId: UUID          // Entity ID（Product / QRCode）
    let entityType: String      // "product" / "qrcode"
    let placeholder: Image      // 無圖片時的 placeholder

    // 顯示邏輯：
    // 1. 有本地 imageData → 直接顯示（零流量）
    // 2. 無本地 + 有 imageURL → KFImage 載入 + onSuccess 回寫 CoreData
    // 3. 無本地 + 無 URL → 顯示 placeholder
}
```

> **核心特點**：
> - 本地優先策略，有 imageData 就不請求網路
> - Kingfisher 下載成功後自動回寫到 CoreData（`imageData`），下次就不需要再下載
> - 回寫時不改變 `syncStatus`（這只是本地快取行為）

### 節省 Firebase 費用的策略

| 策略 | 說明 | 節省比例 |
|------|------|---------|
| **1. 上傳壓縮 + 調整尺寸** | 壓縮至 500KB 以下，限制最大寬高 1024px | 70%+ Storage |
| **2. Kingfisher 磁碟快取** | 設定快取過期時間（7 天），避免重複下載 | 90%+ 重複流量 |
| **3. 本地優先策略** | 有本地 imageData 就不請求 URL | 幾乎 100% |
| **4. 下載後回寫本地** | Kingfisher 下載成功後存入 imageData | 後續零流量 |
| **5. 延遲載入 (Lazy Load)** | 只在進入詳情頁時下載，列表用 placeholder | 50%+ |
| **6. WiFi Only 同步** | 圖片同步只在 WiFi 環境進行（可選） | 100% 行動數據 |
| **7. 差異同步** | 追蹤 updatedAt，只下載有變更的圖片 | 大幅減少 |

### 上傳時的壓縮處理（實際實作）

`ImageSyncService` 使用 `ImageType` enum 決定處理規格：

```swift
enum ImageType {
    case qrCode     // 512x512px PNG 無損
    case thumbnail  // 200x200px JPEG 0.8 壓縮
}

class ImageSyncService {
    /// 核心上傳方法：調整尺寸為正方形 → 轉換格式 → 上傳 Storage → 取得 URL
    private func uploadImage(_ image: UIImage, path: String, type: ImageType) async throws -> String {
        // 1. 裁切為正方形 + 縮放到目標尺寸
        let resized = resizeImageToSquare(image, targetSize: type.targetSize)

        // 2. 轉換為指定格式
        let imageData: Data
        if type.usePNG {
            guard let data = resized.pngData() else { throw SyncError.imageUploadFailed }
            imageData = data
        } else {
            guard let data = resized.jpegData(compressionQuality: type.compressionQuality) else {
                throw SyncError.imageUploadFailed
            }
            imageData = data
        }

        // 3. 上傳到 Firebase Storage
        let ref = storage.reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = type.contentType
        _ = try await ref.putDataAsync(imageData, metadata: metadata)

        // 4. 取得下載 URL
        let url = try await ref.downloadURL()
        return url.absoluteString
    }
}
```

### Kingfisher 快取設定

```swift
// AppDelegate 或 App init 中設定
func setupKingfisherCache() {
    let cache = ImageCache.default

    // 記憶體快取：100MB
    cache.memoryStorage.config.totalCostLimit = 100 * 1024 * 1024

    // 磁碟快取：500MB，7 天過期
    cache.diskStorage.config.sizeLimit = 500 * 1024 * 1024
    cache.diskStorage.config.expiration = .days(7)
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

離線排隊整合在 `SyncManager` 中，使用 `CDPendingSyncOperation` CoreData Entity 持久化：

```swift
// SyncManager 中的離線排隊（實際實作）
@MainActor
class SyncManager {
    /// 離線時 enqueue 操作到 CoreData
    private func enqueueOperation(entityType: String, entityId: UUID, operation: SyncOperation, payload: Data?) {
        let pending = CDPendingSyncOperation(context: context)
        pending.id = UUID()
        pending.entityType = entityType
        pending.entityId = entityId
        pending.operationType = operation.rawValue
        pending.payload = payload
        pending.createdAt = Date()
        pending.retryCount = 0
        try? context.save()
    }

    /// 網路恢復時處理所有排隊操作
    func processPendingQueue() async {
        let request = CDPendingSyncOperation.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        guard let pendingOps = try? context.fetch(request) else { return }

        for op in pendingOps {
            do {
                try await processOperation(op)
                context.delete(op)  // 成功後刪除
            } catch {
                op.retryCount += 1
                op.lastError = error.localizedDescription
                if op.retryCount >= 3 {
                    // 超過重試次數，標記原實體為 error
                    updateEntitySyncStatus(entityType: op.entityType!, entityId: op.entityId, status: "error")
                }
            }
        }
        try? context.save()
    }
}
```

### 監聽機制（HybridSyncListener）

> **不使用傳統的 Collection Listener**（每次變更讀取完整文件 1-2KB），改用 Hybrid Listener 只監聽 syncState 文件（200-500 bytes），節省約 73% 費用。詳見 [Hybrid Listener 費用優化](#hybrid-listener-費用優化) 章節。

### 圖片同步服務

`ImageSyncService` 負責圖片的壓縮、上傳到 Firebase Storage、及下載：

```swift
class ImageSyncService {
    static let shared = ImageSyncService()

    /// 上傳產品圖片（200x200 JPEG 壓縮）
    func uploadProductImage(_ image: UIImage, productId: UUID) async throws -> String

    /// 上傳 QR Code 圖片（512x512 PNG 無損）
    func uploadQRCodeImage(_ image: UIImage, qrCodeId: UUID) async throws -> String

    /// 上傳頭貼圖片（200x200 JPEG，URL 加時間戳避免快取）
    func uploadProfileImage(_ image: UIImage, uid: String) async throws -> String

    /// 處理圖片供本地儲存（調整尺寸 + 轉換格式）
    func processImageForLocal(_ image: UIImage, type: ImageType) -> Data?

    /// 刪除圖片（單一 / 批次 / 根據 URL）
    func deleteProductImage(productId: UUID) async throws
    func deleteQRCodeImage(qrCodeId: UUID) async throws
    func deleteImages(urls: [String]) async

    /// 圖片處理：裁切為正方形 → 縮放到目標尺寸
    private func resizeImageToSquare(_ image: UIImage, targetSize: CGFloat) -> UIImage
}

enum ImageType {
    case qrCode    // 512x512px PNG 無損
    case thumbnail // 200x200px JPEG 0.8 壓縮
}
```

---

## Hybrid Listener 費用優化

### 核心概念

傳統的 Firestore Listener 會監聽完整的資料 collection，每次有變更都會讀取完整文件（1-2 KB），產生大量讀取費用。

**Hybrid Listener 策略**：只監聽一個輕量的 `syncState` 文件（200-500 bytes），收到變更通知後再精確下載需要的資料。

### 費用對比

| 項目 | 傳統 Listener | Hybrid Listener |
|------|--------------|-----------------|
| Listener 讀取大小 | 1-2 KB/次 | **200-500 bytes/次** |
| 100 用戶/月 | $9.30 | **$2.50** |
| 1000 用戶/月 | $93 | **$25** |
| **節省** | - | **約 73%** |

### Firestore 結構

```
firestore/
├── products/{productId}              // 完整資料（不監聽）
├── sessions/{sessionId}              // 完整資料（不監聯）
├── categories/{categoryId}           // 完整資料（不監聽）
├── transactions/{transactionId}      // 完整資料（不監聽）
└── users/{userId}/
    └── private/
        └── syncState                 // ⚡ 只監聽這個文件！
            {
              "version": 123,
              "lastUpdate": timestamp,
              "pendingChanges": {
                "products": ["id1", "id2"],
                "sessions": ["id3"],
                "categories": [],
                "transactions": ["id4"]
              }
            }
```

**syncState 文件大小：約 200-500 bytes**

### 運作規則

1. **Listener 只監聽 `syncState`**（不監聽實際資料 collection）
2. **pendingChanges 上限 50 個 ID**（超過就清空該類別）
3. **清空時 version +1**（其他裝置看到空清單 + 版本號變大 → 全量下載）

### 寫入邏輯

```swift
/// 上傳資料時，同時更新 syncState
func uploadProduct(_ product: ProductModel) async throws {
    guard let userId = currentUserId else { throw SyncError.authenticationRequired }

    let batch = db.batch()

    // 1. 上傳完整資料
    let productRef = db.collection("products").document(product.id.uuidString)
    batch.setData(product.toFirestoreData(userId: userId), forDocument: productRef)

    // 2. 更新 syncState
    let syncStateRef = db.collection("users").document(userId)
        .collection("private").document("syncState")

    batch.updateData([
        "version": FieldValue.increment(Int64(1)),
        "lastUpdate": FieldValue.serverTimestamp(),
        "pendingChanges.products": FieldValue.arrayUnion([product.id.uuidString])
    ], forDocument: syncStateRef)

    try await batch.commit()

    // 3. 檢查是否超過上限（非同步處理）
    Task {
        await trimPendingChangesIfNeeded(userId: userId, entityType: "products")
    }
}

/// 清理超過上限的 pendingChanges
private func trimPendingChangesIfNeeded(userId: String, entityType: String) async {
    let syncStateRef = db.collection("users").document(userId)
        .collection("private").document("syncState")

    do {
        let doc = try await syncStateRef.getDocument()
        guard let data = doc.data(),
              let pendingChanges = data["pendingChanges"] as? [String: [String]],
              let ids = pendingChanges[entityType],
              ids.count > 50 else { return }

        // 超過 50 個，清空該類別
        try await syncStateRef.updateData([
            "pendingChanges.\(entityType)": FieldValue.delete()
        ])
    } catch {
        print("trimPendingChanges error: \(error)")
    }
}
```

### 監聽邏輯

```swift
class HybridSyncListener {
    private var listener: ListenerRegistration?
    private var localVersion: Int = 0

    func startListening(userId: String) {
        let syncStateRef = db.collection("users").document(userId)
            .collection("private").document("syncState")

        // 讀取本地版本號
        localVersion = UserDefaults.standard.integer(forKey: "syncVersion")

        listener = syncStateRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self,
                  let data = snapshot?.data() else { return }

            let cloudVersion = data["version"] as? Int ?? 0

            // 版本號沒變，不處理
            guard cloudVersion > self.localVersion else { return }

            let pendingChanges = data["pendingChanges"] as? [String: [String]] ?? [:]

            Task {
                await self.processChanges(pendingChanges, cloudVersion: cloudVersion)
            }
        }
    }

    private func processChanges(_ pendingChanges: [String: [String]], cloudVersion: Int) async {
        // Products
        if let productIds = pendingChanges["products"], !productIds.isEmpty {
            // 有精確清單：只下載這些
            for id in productIds {
                await downloadProduct(id: id)
            }
        } else if cloudVersion > localVersion {
            // 清單是空的但版本號變了：全量下載
            await downloadAllProducts()
        }

        // Sessions（同樣邏輯）
        if let sessionIds = pendingChanges["sessions"], !sessionIds.isEmpty {
            for id in sessionIds {
                await downloadSession(id: id)
            }
        } else if cloudVersion > localVersion {
            await downloadAllSessions()
        }

        // Categories、Transactions... 同樣邏輯

        // 更新本地版本號
        localVersion = cloudVersion
        UserDefaults.standard.set(cloudVersion, forKey: "syncVersion")

        // 清除已處理的 pendingChanges
        await clearProcessedChanges()
    }

    private func clearProcessedChanges() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let syncStateRef = db.collection("users").document(userId)
            .collection("private").document("syncState")

        try? await syncStateRef.updateData([
            "pendingChanges": [
                "products": [],
                "sessions": [],
                "categories": [],
                "transactions": []
            ]
        ])
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }
}
```

### 初始化 syncState（首次登入時）

```swift
func initializeSyncState(userId: String) async throws {
    let syncStateRef = db.collection("users").document(userId)
        .collection("private").document("syncState")

    let doc = try await syncStateRef.getDocument()

    if !doc.exists {
        try await syncStateRef.setData([
            "version": 0,
            "lastUpdate": FieldValue.serverTimestamp(),
            "pendingChanges": [
                "products": [],
                "sessions": [],
                "categories": [],
                "transactions": []
            ]
        ])
    }
}
```

### Firestore Security Rules

syncState 的存取權限已包含在 [Firestore 安全規則](#firestore-安全規則) 中：

```javascript
// users/{userId} 底下所有子集合（包含 private/syncState）
match /users/{userId}/{document=**} {
    allow read, write: if request.auth != null && request.auth.uid == userId;
}
```

### 使用場景

| 場景 | 行為 |
|------|------|
| **正常使用**（每天少量變更）| 精確下載 pendingChanges 中的 ID |
| **離線 3 天後重新連線** | pendingChanges 已清空，根據 version 全量下載 |
| **批次匯入 100 個產品** | 超過 50 個後自動清空，觸發全量下載 |

---

## 衝突處理與刪除策略

### 運行時衝突：Last-Write-Wins

當多台裝置同時編輯同一筆資料時，使用 `updatedAt` 判斷哪個版本較新：

```swift
/// 處理從 Firestore 收到的遠端變更
func handleRemoteChange<T: NSManagedObject>(
    remoteData: [String: Any],
    localEntity: T
) where T: SyncableEntity {
    guard let remoteUpdatedAt = (remoteData["updatedAt"] as? Timestamp)?.dateValue() else {
        return
    }

    if remoteUpdatedAt > localEntity.updatedAt {
        // 遠端較新，更新本地資料
        localEntity.update(from: remoteData)
        localEntity.syncStatus = "synced"
        try? context.save()
    }
    // 本地較新時不做處理，本地會在下次同步時覆蓋遠端
}
```

### Cascade Delete 策略

#### Session 刪除時的連鎖處理

| Entity | 處理方式 | 原因 |
|--------|---------|------|
| Categories | 刪除 | 類別屬於場次 |
| Products | 刪除 | 產品屬於場次 |
| InventoryChanges | 刪除 | 庫存異動屬於場次 |
| Transactions | **保留** | 交易記錄是歷史資料，需保留供分析 |
| Storage 圖片 | 刪除 | 避免孤立檔案（尚未實作） |

#### Product 刪除時的連鎖處理

| Entity | 處理方式 | 原因 |
|--------|---------|------|
| InventoryChanges | 刪除 | 庫存異動屬於該產品（透過 productId 關聯）|
| Storage 圖片 | 刪除 | 避免孤立檔案（尚未實作） |

> **注意**：Product 與 InventoryChange 之間沒有 CoreData relationship，僅透過 `productId` UUID 欄位關聯。因此需要在 `ProductRepository.deleteProduct()` 中手動刪除。

#### Category 刪除時的連鎖處理

| Entity | 處理方式 | 原因 |
|--------|---------|------|
| Products | 刪除 | 產品屬於該類別 |
| InventoryChanges | 刪除 | 被刪除產品的庫存異動也一併刪除 |

#### 智能刪除邏輯（Product）

產品刪除會檢查是否有相關 Transaction：
- **有 Transaction** → 只停用（`isDisabled = true`），不硬刪除
- **無 Transaction** → 硬刪除產品 + 連帶刪除 InventoryChanges

### Session 刪除實作

由 `FirestoreUploader.deleteSessionWithChildren()` 處理 Firestore 端的 cascade delete：

```swift
// FirestoreUploader（實際實作摘要）
func deleteSessionWithChildren(_ sessionId: UUID) async throws {
    let sessionIdStr = sessionId.uuidString
    guard let userId = currentUserId else { throw SyncError.authenticationRequired }

    // 1. 查詢所有子文件
    let categories = try await db.collection("categories")
        .whereField("userId", isEqualTo: userId)
        .whereField("sessionId", isEqualTo: sessionIdStr)
        .getDocuments()

    let products = try await db.collection("products")
        .whereField("userId", isEqualTo: userId)
        .whereField("sessionId", isEqualTo: sessionIdStr)
        .getDocuments()

    let inventoryChanges = try await db.collection("inventoryChanges")
        .whereField("userId", isEqualTo: userId)
        .whereField("sessionId", isEqualTo: sessionIdStr)
        .getDocuments()

    // ⚠️ Transactions 不刪除，保留歷史記錄

    // 2. 收集所有被刪除的 ID
    var allDeletedIds: [String] = [sessionIdStr]
    // ... 收集 category, product, inventoryChange IDs

    // 3. 批次刪除（自動分批處理 Firestore 500 筆限制）
    // 4. 更新 syncState（version+1, pendingChanges 加入所有 ID）
}
```

> **本地端**：CoreData 的 cascade relationship 會自動處理 Session → Category → Product 的連鎖刪除。InventoryChange 因為透過 relationship 連結到 Session，也會被 cascade 刪除。

### 大量資料的分批刪除

```swift
/// Firestore batch 最多 500 筆，需要分批處理
func batchDelete(documents: [QueryDocumentSnapshot]) async throws {
    let chunks = documents.chunked(into: 450)  // 預留一些空間

    for chunk in chunks {
        let batch = db.batch()
        for doc in chunk {
            batch.deleteDocument(doc.reference)
        }
        try await batch.commit()
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
```

### 同步順序：Batch Write + Parent-First

#### 什麼是 Batch Write？

Firestore Batch Write 是**原子操作**，多個寫入要嘛全部成功，要嘛全部失敗：

```swift
// 沒有 Batch（可能部分成功，導致資料不一致）
try await db.collection("sessions").document(id).setData(sessionData)  // ✅ 成功
try await db.collection("categories").document(id).setData(catData)    // ❌ 失敗
// 結果：Session 存在，但 Category 沒有

// 使用 Batch（原子操作）
let batch = db.batch()
batch.setData(sessionData, forDocument: db.collection("sessions").document(id))
batch.setData(catData, forDocument: db.collection("categories").document(id))
try await batch.commit()  // 全部成功或全部失敗
```

#### Parent-First 同步實作

```swift
func syncNewSession(_ session: SessionModel) async throws {
    let batch = db.batch()

    // 1. Parent: Session
    let sessionRef = db.collection("sessions").document(session.id.uuidString)
    batch.setData(session.toFirestoreData(), forDocument: sessionRef)

    // 2. Children: Categories
    for category in session.categories {
        let catRef = db.collection("categories").document(category.id.uuidString)
        var catData = category.toFirestoreData()
        catData["sessionId"] = session.id.uuidString  // 加入關聯 ID
        batch.setData(catData, forDocument: catRef)

        // 3. Grandchildren: Products
        for product in category.products {
            let prodRef = db.collection("products").document(product.id.uuidString)
            batch.setData(product.toFirestoreData(), forDocument: prodRef)
        }
    }

    // 原子提交
    do {
        try await batch.commit()
        // 成功：更新本地 syncStatus
        updateLocalSyncStatus(session, status: .synced)
    } catch {
        // 失敗：加入佇列重試
        enqueuePendingOperation(
            entityType: "session",
            entityId: session.id,
            operationType: "create"
        )
        throw error
    }
}
```

### 匿名用戶 userId 處理

#### userId 來源

使用 Firebase Auth 直接取得，不另外封裝 AuthManager：

```swift
// 在所有 Repository 中直接使用：
entity.userId = Auth.auth().currentUser?.uid
```

> **重要**：所有 Entity 建立/更新時都必須設定 `userId`，否則 Firestore Security Rules 會拒絕寫入。

#### 建立資料時存入 userId

```swift
// 範例：ProductRepository.addProduct()
let productEntity = CDProductEntity(context: context)
productEntity.update(from: productModel, context: context)
productEntity.userId = Auth.auth().currentUser?.uid  // ← 必須存入
productEntity.syncStatus = "pending"
productEntity.updatedAt = Date()
productEntity.category = categoryEntity
```

#### 已設定 userId 的所有位置

| Repository | 方法 | 設定 userId 的 Entity |
|------------|------|----------------------|
| SessionRepository | addSession() | Session, Category, Product |
| SessionRepository | addTransaction() | Transaction |
| SessionRepository | duplicateSession() | Session, Category, Product, InventoryChange |
| ProductRepository | addProduct() | Product |
| InventoryChangeRepository | addChange() | InventoryChange |
| InventoryChangeRepository | addChanges() | InventoryChange (batch) |

#### 登入後更新 userId（情況 C）

> **尚未實作**，將在 Phase 4 實作。匿名帳號連結（Link）到 Google/Apple 帳號後，需要更新所有本地資料的 userId 並觸發全量上傳。

---

## 登入流程與資料處理

> **⚠️ 此章節為 Phase 4 規劃，尚未實作。** 目前 `AuthenticationManager` 只有基礎登入功能，尚未整合同步邏輯。

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

### 登出流程（Phase 4 規劃）

```swift
func signOut() {
    // 1. 停止 Firestore 監聽
    SyncManager.shared.stopListening()

    // 2. 重置同步狀態
    SyncManager.shared.resetSync()

    // 3. 清除所有本地資料
    clearAllLocalData()

    // 4. Firebase Auth 登出
    try? Auth.auth().signOut()

    // 5. 重新匿名登入
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

> **目前狀態**：`signOut()` 目前只做 Firebase Auth signOut + 重新匿名登入，尚未整合步驟 1-3。

---

## 網路監控

使用 Alamofire 的 `NetworkReachabilityManager` 監控網路狀態。

### NetworkMonitor 實作

```swift
import Alamofire

class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let reachabilityManager = NetworkReachabilityManager()
    private var statusChangeCallback: ((Bool) -> Void)?

    /// 當前是否有網路連線
    var isConnected: Bool {
        return reachabilityManager?.isReachable ?? false
    }

    /// 是否透過 WiFi 連線
    var isConnectedViaWiFi: Bool {
        return reachabilityManager?.isReachableOnEthernetOrWiFi ?? false
    }

    /// 是否透過行動網路連線
    var isConnectedViaCellular: Bool {
        return reachabilityManager?.isReachableOnCellular ?? false
    }

    private init() {}

    /// 開始監控網路狀態
    func startMonitoring(onStatusChange: @escaping (Bool) -> Void) {
        statusChangeCallback = onStatusChange

        reachabilityManager?.startListening { [weak self] status in
            switch status {
            case .reachable(.ethernetOrWiFi), .reachable(.cellular):
                self?.handleNetworkRestored()
                onStatusChange(true)

            case .notReachable, .unknown:
                onStatusChange(false)
            }
        }
    }

    /// 停止監控
    func stopMonitoring() {
        reachabilityManager?.stopListening()
        statusChangeCallback = nil
    }

    /// 網路恢復時的處理
    private func handleNetworkRestored() {
        Task {
            // 處理待同步的操作
            await SyncManager.shared.processPendingQueue()
        }
    }
}
```

### 在 App 啟動時開始監控

```swift
// AppDelegate 或 App init
func setupNetworkMonitoring() {
    NetworkMonitor.shared.startMonitoring { isConnected in
        if isConnected {
            print("網路已連線")
        } else {
            print("網路已斷線")
        }
    }
}
```

### 在同步操作中使用

```swift
func saveProduct(_ product: ProductModel) async {
    // 1. 先寫入本地
    let cdProduct = saveToLocalCoreData(product, syncStatus: .pending)

    // 2. 檢查網路狀態
    if NetworkMonitor.shared.isConnected {
        do {
            try await uploadToFirestore(product)
            cdProduct.syncStatus = "synced"
        } catch {
            // 上傳失敗，加入佇列
            enqueuePendingOperation(for: product)
        }
    } else {
        // 無網路，加入佇列等待
        enqueuePendingOperation(for: product)
    }

    try? context.save()
}
```

---

## 實作排序與任務清單

### Phase 1：基礎建設（預估 2-3 天）

- [x] **1.1 Domain Model 更新**
  - [x] 新增 `QRCodeModel.swift`
  - [x] 為所有 Model 新增 Firestore 轉換 Extension（toFirestoreData / init(from:)）
  - [x] 新增 Decimal ↔ Integer（分）轉換工具函數

- [x] **1.2 CoreData Schema 更新**（App 尚未上架，無需 Migration 腳本）
  - [x] 新增 `userId`, `updatedAt`, `syncStatus` 欄位到所有 Entity
  - [x] 新增 `sessionId` 欄位到 Category 和 InventoryChange（Firestore 同步用）
  - [x] 新增 `imageURL` 欄位到 Product 和 QRCode
  - [x] 新增 `createdAt` 欄位到 Product
  - [x] 新增 `CDPendingSyncOperation` Entity

- [x] **1.3 Firestore Schema 建立**
  - [x] 設定 Security Rules（Firebase/firestore.rules）
  - [x] 設定 Storage Rules（Firebase/storage.rules）
  - [x] 設定複合索引（Firebase/firestore.indexes.json）
  - [x] 部署到 Firebase（firebase deploy）

- [x] **1.4 建立基礎服務類別**
  - [x] `SyncManager` — 同步管理器（@MainActor singleton）
  - [x] `SyncError` enum — 同步錯誤類型
  - [x] `NetworkMonitor` — 網路狀態監控（使用 Alamofire）
  - [x] 使用現有 `AuthenticationManager`（不需要新建 AuthManager）
  - [x] `ModelFirestoreExtensions` — 所有 Model 的 Firestore 轉換

### Phase 2：上傳同步（預估 3-4 天）✅ **已完成大部分**

- [x] **2.1 資料上傳服務**
  - [x] `FirestoreUploader` - 上傳資料到 Firestore
  - [x] Session 上傳（單一 + 批次 + Batch Write）
  - [x] Category 上傳（單一 + 批次）
  - [x] Product 上傳（單一 + 批次）
  - [x] Transaction 上傳（單一 + 批次）
  - [x] InventoryChange 上傳（單一 + 批次）
  - [x] QRCode 上傳（單一）
  - [x] Update 功能（Session, Category, Product, QRCode）
  - [x] Delete 功能（所有 Entity + Cascade Delete）
  - [x] **Hybrid Listener 整合**
    - [x] `initializeSyncState()` - 初始化 syncState 文件
    - [x] `syncStateExists()` - 檢查 syncState 是否存在
    - [x] `trimPendingChangesIfNeeded()` - 超過 50 個時清空
    - [x] 所有上傳/更新方法整合 syncState 更新（Batch Write）
    - [x] 所有刪除方法整合 version 遞增
    - [x] 更新 firestore.rules（允許 private subcollection）

- [x] **2.2 圖片上傳服務**
  - [x] `ImageSyncService` - 圖片壓縮與上傳
  - [x] 產品圖片上傳（200x200 JPEG）
  - [x] QR Code 圖片上傳（512x512 PNG）
  - [x] 頭貼圖片上傳（200x200 JPEG）
  - [x] 圖片刪除（單一 + 批次）
  - [x] 圖片處理（調整尺寸為正方形）

- [x] **2.3 離線排隊機制**
  - [x] `SyncManager` 基礎實作
  - [x] `CDPendingSyncOperation` CRUD
  - [x] 網路恢復時自動處理排隊（processPendingQueue）
  - [x] 重試機制（syncWithRetry）

- [x] **2.4 整合到現有 Repository**
  - [x] `SessionRepository` 整合同步
  - [x] `ProductRepository` 整合同步
  - [x] `TransactionRepository` 整合同步
  - [x] `InventoryChangeRepository` 整合同步
  - [x] `QRCodeRepository` 整合同步

### Phase 3：下載同步（預估 2-3 天）

- [x] **3.1 資料下載服務**
  - [x] `FirestoreDownloader` - 從 Firestore 下載資料
  - [x] Session 下載並寫入 CoreData
  - [x] Category 下載
  - [x] Product 下載
  - [x] Transaction 下載
  - [x] InventoryChange 下載
  - [x] QRCode 下載

- [x] **3.2 圖片下載服務**
  - [x] 使用 Kingfisher 下載並快取
  - [x] 下載後更新 CoreData 的 imageData

- [x] **3.3 完整同步功能**
  - [x] `fullSync()` - 完整同步所有資料
  - [x] 進度回報 UI

### Phase 4：登入流程整合（預估 3-4 天）

#### 現狀分析

目前 `AuthenticationManager` 已有基礎登入功能：
- `signInAnonymously()` — App 啟動時自動匿名登入
- `signInWithGoogle()` — Google 登入（link 或 sign-in）
- `handleLinkSuccess()` — 匿名帳號成功連結到 Google
- `handleSignInSuccess()` — 全新 Google 登入成功
- `signOut()` — 登出

#### 需要修改/新增的項目

**問題 1：登入成功後未觸發 fullSync（情況 B）**
- `handleSignInSuccess()` 登入已有雲端資料的帳號時，未呼叫 `SyncManager.fullSync()` 下載資料

**問題 2：Link 成功後未更新 userId（情況 C）**
- `handleLinkSuccess()` 匿名→Google 時，未更新本地資料的 userId，也未觸發全量上傳

**問題 3：衝突處理 UI 未實作（情況 D）**
- 有本地匿名資料 + 有雲端帳號資料時，未提供衝突處理 UI

**問題 4：登出未清除本地資料**
- `signOut()` 未呼叫 `clearAllLocalData()`，可能殘留上一個帳號的資料

**問題 5：登出後殘留 userId-less 資料**
- 匿名期間若有未設 userId 的資料，登出後會殘留

#### 實作步驟

- [x] **4.1 SyncManager 新增登入流程方法** ✅（已完成）
  - [x] `hasLocalData() -> Bool` — 檢查本地是否有資料（Session count > 0）
  - [x] `hasCloudData(userId:) -> Bool` — 檢查 Firestore 是否有該 userId 的資料
  - [x] `updateAllUserIds(from:to:)` — 批次更新所有 Entity 的 userId
  - [x] `fullUploadAllData()` — 全量上傳所有本地資料到 Firestore
  - [x] `clearAllLocalData()` — 清除所有本地 CoreData 資料

- [ ] **4.2 修改 handleLinkSuccess()（情況 C：本地有資料 + 雲端沒資料）**
  - [ ] 取得舊 anonymousUID 和新 googleUID（Link 前先記住 anonymous uid）
  - [ ] 呼叫 `updateAllUserIds(from: oldUID, to: newUID)` 更新本地資料
  - [ ] 呼叫 `fullUploadAllData()` 上傳到新帳號的 Firestore
  - [ ] 重新 initializeSync（新 userId）

- [ ] **4.3 修改 handleSignInSuccess()（情況 B/D）**
  - [ ] 檢查本地是否有匿名資料（`hasLocalData()`）
  - [ ] 檢查雲端是否有帳號資料（`hasCloudData(userId:)`）
  - [ ] 情況 A：兩邊都沒 → 直接完成
  - [ ] 情況 B：只有雲端 → `fullSync()` 下載
  - [ ] 情況 D：兩邊都有 → 顯示衝突 UI

- [ ] **4.4 DataConflictView 衝突處理 UI**
  - [ ] `DataConflictView` — 衝突選擇畫面
  - [ ] `DataSummary` — 本地/雲端資料摘要（Session 數、Product 數、Transaction 數）
  - [ ] 選項 1：使用雲端資料 → `clearAllLocalData()` + `fullSync()`
  - [ ] 選項 2：使用本地資料 → 清除雲端 + `fullUploadAllData()`
  - [ ] 選項 3：取消登入 → 回到匿名狀態

- [x] **4.5 修改 signOut()** ✅（已完成）
  - [x] 呼叫 `SyncManager.resetSync()` 停止監聽並重置同步狀態
  - [x] 呼叫 `clearAllLocalData()` 清除所有本地資料
  - [x] Firebase Auth signOut + GIDSignIn signOut
  - [x] 重新 `signInAnonymously()`

- [x] **4.6 Apple Sign In 取消註解 + 重構** ✅（已完成，取代原本的 4.6）
  - [x] 取消註解 `import AuthenticationServices`, `import CryptoKit`
  - [x] 取消註解 `currentNonce` 屬性
  - [x] 取消註解並重構 `signInWithApple()` + `handleAppleSignIn()`
  - [x] `handleAppleSignIn()` 改用共用的 `handleLinkSuccess(user:provider:.apple)` / `handleSignInSuccess(user:provider:.apple)`
  - [x] credentialAlreadyInUse 路徑加入匿名帳號清理（對齊 Google 流程）
  - [x] 刪除 Apple 專用 handler（`handleAppleLinkSuccess`, `handleAppleSignInSuccess`）
  - [x] 取消註解 `randomNonceString()`, `sha256()` helper 方法
  - [x] 取消註解 `ASAuthorizationControllerDelegate` extension

- [ ] **4.7 App 生命週期整合**
  - [ ] Loading 畫面（fullSync 下載中顯示進度）
  - [ ] 衝突 UI 的導航流程（DataConflictView 接入 AuthenticationManager）

### Phase 5：Hybrid Listener 即時監聽（預估 2-3 天）

- [x] **5.1 syncState 基礎建設**
  - [x] 新增 `users/{userId}/private/syncState` 文件結構
  - [x] 更新 Firestore Security Rules（允許存取 private subcollection）
  - [x] `initializeSyncState()` - 首次登入時初始化 syncState
  - [x] 在 FirestoreUploader 中整合 syncState 更新

- [x] **5.2 HybridSyncListener 實作**
  - [x] `HybridSyncListener` - 只監聽 syncState 文件
  - [x] `startListening()` - 開始監聽
  - [x] `stopListening()` - 停止監聽
  - [x] `processChanges()` - 根據 pendingChanges 下載資料
  - [x] `clearProcessedChanges()` - 清除已處理的變更

- [x] **5.3 pendingChanges 管理**
  - [x] 寫入時加入 pendingChanges（arrayUnion）
  - [x] `trimPendingChangesIfNeeded()` - 超過 50 個時清空
  - [x] 版本號遞增邏輯

- [x] **5.4 變更處理**
  - [x] 精確下載：根據 pendingChanges 的 ID 下載
  - [x] 全量下載：pendingChanges 為空但版本號變了
  - [x] 本地版本號快取（UserDefaults）

- [x] **5.5 整合到 App 生命週期**
  - [x] 登入時開始監聽 + 初始化 syncState
  - [x] 登出時停止監聽
  - [x] App 進入前台時檢查版本號

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

### 錯誤 UI 元件

當 `syncStatus = "error"` 時，在 UI 上顯示錯誤圖示和重試按鈕：

```swift
/// 同步錯誤標示元件
struct SyncErrorBadge: View {
    let syncStatus: String
    let onRetry: () -> Void

    var body: some View {
        if syncStatus == "error" {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.icloud.fill")
                    .foregroundColor(.red)
                    .font(.caption)

                Button(action: onRetry) {
                    Text("重試")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
        }
    }
}

// 使用範例
struct ProductRow: View {
    let product: ProductModel

    var body: some View {
        HStack {
            // 產品資訊...
            Text(product.name)

            Spacer()

            // 同步狀態指示
            SyncErrorBadge(syncStatus: product.syncStatus) {
                // 重試同步
                Task {
                    await SyncManager.shared.retrySync(for: product)
                }
            }
        }
    }
}
```

### 同步狀態指示器（可選）

```swift
/// 顯示待同步、同步中、錯誤狀態
struct SyncStatusIndicator: View {
    let syncStatus: String
    @State private var isAnimating = false

    var body: some View {
        switch syncStatus {
        case "pending":
            Image(systemName: "icloud.and.arrow.up")
                .foregroundColor(.orange)

        case "synced":
            EmptyView()  // 已同步不顯示

        case "error":
            Image(systemName: "exclamationmark.icloud.fill")
                .foregroundColor(.red)

        default:
            EmptyView()
        }
    }
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

## 附錄 A：實際檔案結構

```
Tilli/
├── Model/
│   └── Domain/
│       ├── SessionModel.swift             # ✅ Firestore Extension 在 ModelFirestoreExtensions.swift
│       ├── CategoryModel.swift            # ✅ Firestore Extension 在 ModelFirestoreExtensions.swift
│       ├── ProductModel.swift             # ✅ Firestore Extension 在 ModelFirestoreExtensions.swift
│       ├── TransactionModel.swift         # ✅ Firestore Extension 在 ModelFirestoreExtensions.swift
│       ├── InventoryChangeModel.swift     # ✅ Firestore Extension 在 ModelFirestoreExtensions.swift
│       ├── DiscountModel.swift            # ✅ Firestore Extension 在 ModelFirestoreExtensions.swift
│       ├── SummaryItemModel.swift         # ✅ Firestore Extension 在 ModelFirestoreExtensions.swift
│       └── QRCodeModel.swift              # ✅ 已建立
├── Data/
│   ├── CoreData/
│   │   └── Tilli.xcdatamodeld             # ✅ 已更新 Schema
│   ├── Repositories/
│   │   ├── SessionRepository.swift        # ✅ 已整合同步
│   │   ├── ProductRepository.swift        # ✅ 已整合同步
│   │   ├── InventoryChangeRepository.swift # ✅ 已整合同步
│   │   └── AuthenticationManager.swift    # ✅ 現有，Phase 4 將修改
│   └── Sync/
│       ├── SyncManager.swift              # ✅ 同步管理器（@MainActor singleton）
│       ├── FirestoreUploader.swift        # ✅ 上傳/更新/刪除 + syncState 管理
│       ├── FirestoreDownloader.swift      # ✅ 下載 + LWW 衝突解決
│       ├── HybridSyncListener.swift       # ✅ 輕量監聽 syncState 文件
│       ├── ImageSyncService.swift         # ✅ 圖片壓縮/上傳/下載
│       ├── ModelFirestoreExtensions.swift  # ✅ 所有 Model 的 toFirestoreData() / init(from:)
│       ├── NetworkMonitor.swift           # ✅ 網路監控（Alamofire）
│       └── DecimalHelper.swift            # ✅ Decimal ↔ Integer（分）轉換
├── View/
│   └── Components/
│       └── SyncableImageView.swift        # ✅ 本地優先 + Kingfisher 下載 + CoreData 回寫
├── Firebase/
│   ├── firestore.rules                    # ✅ Security Rules
│   └── firestore.indexes.json             # ✅ 複合索引設定
```

> **說明**：
> - 所有 Firestore 轉換 Extension 統一放在 `ModelFirestoreExtensions.swift`，而非分散在各 Model 檔案中
> - 不存在獨立的 `SyncStatus.swift`、`SyncQueue.swift`、`ConflictResolver.swift`、`AuthManager.swift`
>   - SyncStatus 為 String（"synced" / "pending" / "error"），直接使用
>   - 離線排隊整合在 SyncManager + CDPendingSyncOperation
>   - 衝突處理在 FirestoreDownloader 中以 LWW 實作
>   - 使用現有的 `AuthenticationManager`，不另建 AuthManager

---

## 附錄 B：CoreData Schema 變更總表

快速查閱各 Entity 需要新增的欄位：

| Entity | 新增欄位 | 說明 |
|--------|---------|------|
| **CDSessionEntity** | `userId: String` | 所屬用戶 ID |
| | `updatedAt: Date` | 最後更新時間 |
| | `syncStatus: String` | synced / pending / error |
| **CDCategoryEntity** | `userId: String` | 所屬用戶 ID |
| | `sessionId: UUID` | 冗餘欄位（Firestore 用）|
| | `updatedAt: Date` | 最後更新時間 |
| | `syncStatus: String` | synced / pending / error |
| **CDProductEntity** | `userId: String` | 所屬用戶 ID |
| | `createdAt: Date` | 產品建立時間 |
| | `updatedAt: Date` | 最後更新時間 |
| | `syncStatus: String` | synced / pending / error |
| | `imageURL: String?` | Firebase Storage URL |
| **CDTransactionEntity** | `userId: String` | 所屬用戶 ID |
| | `syncStatus: String` | synced / pending / error |
| **CDInventoryChangeEntity** | `userId: String` | 所屬用戶 ID |
| | `sessionId: UUID` | 冗餘欄位（Firestore 用）|
| | `syncStatus: String` | synced / pending / error |
| **CDQRCodeEntity** | `userId: String` | 所屬用戶 ID |
| | `updatedAt: Date` | 最後更新時間 |
| | `syncStatus: String` | synced / pending / error |
| | `imageURL: String?` | Firebase Storage URL |
| **CDPendingSyncOperation** | 全新 Entity | 離線操作佇列 |

### 保留不變的欄位

| Entity | 欄位 | 說明 |
|--------|------|------|
| CDSessionEntity | `discountsData: Binary` | 維持 Binary，同步時轉 JSON String |
| CDTransactionEntity | `itemsData: Binary` | 維持 Binary，同步時轉 JSON String |
| CDTransactionEntity | `timestamp: Date` | 用作建立時間，不需額外 createdAt |
| CDTransactionEntity | `occurredAt: Date?` | 補記帳時間，不影響離線同步 |
| CDProductEntity | `imageData: Binary` | 保留，本地快取用 |
| CDQRCodeEntity | `imageData: Binary` | 保留，本地快取用 |

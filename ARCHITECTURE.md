# Tilli 資料架構總表

> 建立日期：2026-09-12
> **本文件是資料結構的唯一真相來源（single source of truth）。**
>
> 所有 CoreData 欄位都必須在 §4 的分類表上有一列。
> §6 的驗證腳本會檢查這件事 —— **新增欄位卻忘記分類，腳本就會失敗。**
> 這是「不會漏掉任何東西」的機制：靠結構保證，不靠記憶。

---

## 目錄

1. [文件導覽](#1-文件導覽)
2. [掃描基準](#2-掃描基準)
3. [六種欄位分類](#3-六種欄位分類)
4. [完整欄位分類表](#4-完整欄位分類表)
5. [內嵌模型分類表](#5-內嵌模型分類表)
6. [驗證腳本](#6-驗證腳本)
7. [執行總覽](#7-執行總覽)
8. [第一步：刪除同步層](#8-第一步刪除同步層)

---

## 1. 文件導覽

| 文件 | 用途 | 何時看 |
|------|------|--------|
| **`ARCHITECTURE.md`**（本文件） | **資料結構的唯一真相**：每個欄位是什麼、同步時怎麼處理 | **任何時候要動資料結構** |
| `FEATURE_PLAN_V1.md` | 本機功能階段的細節：24 項查核、7 個共用元件、折扣／組合套餐、測試 | 寫本機功能時 |
| `SYNC_ARCHITECTURE_V2.md` | 同步階段的細節：Outbox、Pull-by-cursor、Device Handoff、訂閱 | 重建同步時 |
| `_archive:/` | 已被取代的舊規劃（SYNC_IMPLEMENTATION_PLAN、PRO_SYNC_BUGS、DISCOUNT_REFACTOR_PLAN、NAVIGATION_RESTRUCTURE_PLAN） | 不要看 |

**規則：三份文件如果對同一件事有不同說法，以本文件為準。**

---

## 2. 掃描基準

> 2026-09-12 全專案掃描結果。修改資料結構後請更新這一節。

```
程式碼      114 個 Swift 檔（排除 _Deprecated）、21,468 行
CoreData    8 個 entity、87 個屬性、8 個關聯
內嵌模型    2 個（SummaryItemModel、DiscountModel，以 JSON 存在 Binary 欄位內）
```

**Domain model 與 CoreData 欄位完全對得上，沒有結構落差。**

---

## 3. 六種欄位分類

| 代號 | 名稱 | 定義 | 會變嗎 | 同步策略 |
|------|------|------|--------|----------|
| **L** | 即時值 (Live) | 反映當前狀態，使用者可編輯 | ✅ | 上傳，衝突用 LWW（`updatedAt` 比較） |
| **S** | **快照 (Snapshot)** | 寫入當下凍結，**永遠不再更新** | ❌ | 上傳，但值永不改變 |
| **R** | 參照 (Reference) | id，或建立時決定後不變 | ❌ | 上傳，不變 |
| **D** | 推導 (Derived) | 從其他資料算出來 | — | **不上傳**，本機重算 |
| **X** | 純本機 (Local-only) | 只在這台裝置有意義 | — | **不上傳** |
| **M** | 同步後設 (Meta) | 同步機制自己用的 | — | 視欄位，見下 |

### 3.1 決定 L 還是 S 的唯一準則

> **這筆資料是「文件」還是「流水帳」？**
>
> - **文件** = 描述「現在的狀態」（場次、類別、商品、收款方式、使用者資料）→ 欄位是 **L**
> - **流水帳** = 記錄「當時發生了什麼」（交易、庫存異動）→ **整筆都是 S**
>
> 流水帳沒有「現在的狀態」可言，它就是歷史本身。所以**流水帳的任何欄位都不該被更新** ——
> 包含那些看起來像是「複製過來」的欄位（`eventTitle`、商品名、單價、類別名）。

這條準則直接決定了兩個現存 bug 的修法：

| 現況 | 問題 | 依準則的正解 |
|------|------|-------------|
| `EventRepository:581` 改場次名時更新所有交易的 `eventTitle` | 流水帳被更新了，而且沒設 `syncStatus` → 本機與雲端不一致 | **刪掉這個更新**。`eventTitle` 是 S |
| `EventRepository:321` 改類別名時更新所有商品的 `categoryName` | 文件存了別人的快照 → 更新風暴 | **刪掉這個欄位**。文件不存快照，顯示時查 relationship |

### 3.2 M 類的細分

| 欄位 | 上傳嗎 | 說明 |
|------|--------|------|
| `updatedAt` | ✅ | LWW 依據 + pull cursor。同步時寫入 `serverTimestamp()` |
| `userId` | ✅ | Firestore rules 與查詢用 |
| `syncStatus` | ❌ | **純本機狀態**（synced / pending / local），不上雲端 |
| `deletedAt`（計畫） | ✅ | tombstone |

---

## 4. 完整欄位分類表

> ⚠️ **CoreData 的每一個屬性都必須在這裡有一列。** 由 §6 的腳本驗證。
>
> `狀態` 欄：`現有` = 已存在　`新增` = 計畫加入　`刪除` = 計畫移除

### CDEventEntity

> 資料類型：**文件**

| 欄位 | 分類 | 狀態 | 說明 |
|------|------|------|------|
| `id` | R | 現有 | 主鍵 |
| `title` | L | 現有 | 場次名稱。⚠️ 改名時**不可**回頭更新交易的 `eventTitle` |
| `startDate` | L | 現有 | |
| `endDate` | L | 現有 | nil = 無限期 |
| `dateType` | L | 現有 | single / multi / permanent。multi 與 permanent 需要 Pro |
| `currency` | L | 現有 | |
| `discountsData` | L | 現有 | `[DiscountModel]` 的 JSON。見 §5 |
| `bundlesData` | L | **新增** | `[BundleModel]` 的 JSON（組合／套餐）。見 §5 |
| `createdAt` | R | 現有 | |
| `updatedAt` | M | 現有 | LWW + cursor |
| `userId` | M | 現有 | |
| `syncStatus` | M·X | 現有 | 純本機 |

### CDCategoryEntity

> 資料類型：**文件**

| 欄位 | 分類 | 狀態 | 說明 |
|------|------|------|------|
| `id` | R | 現有 | |
| `name` | L | 現有 | ⚠️ 改名時**不可**回頭更新商品的 `categoryName`（該欄位將被刪除） |
| `isDisabled` | L | 現有 | 停用。**語意純化：只代表「停用」，不再兼任偽刪除** |
| `sortOrder` | L | 現有 | |
| `eventId` | R | 現有 | 冗餘但必要 —— Firestore 無 relationship |
| `createdAt` | R | 現有 | |
| `updatedAt` | M | 現有 | |
| `userId` | M | 現有 | |
| `syncStatus` | M·X | 現有 | |

### CDProductEntity

> 資料類型：**文件**

| 欄位 | 分類 | 狀態 | 說明 |
|------|------|------|------|
| `id` | R | 現有 | |
| `name` | L | 現有 | 有交易後不可編輯（UI 限制） |
| `price` | L | 現有 | 有交易後不可編輯（UI 限制） |
| `note` | L | 現有 | 隨時可改 |
| `isDisabled` | L | 現有 | 下架。**語意純化：不再兼任偽刪除** |
| `sortOrder` | L | 現有 | |
| `categoryId` | R | 現有 | 有交易後不可編輯（UI 限制） |
| `categoryName` | — | **刪除** | ⚠️ 反正規化冗餘，造成更新風暴。改查 relationship |
| `eventId` | R | 現有 | 冗餘但必要 |
| `stock` | **D** | 現有→降級 | ⚠️ **改為推導值**：`Σ InventoryChange.change`。**停止上傳** |
| `imageData` | **X** | 現有 | 本機圖。**不上傳**（雲端存 `imageURL`） |
| `imageURL` | L | 現有 | Storage 下載網址 |
| `createdAt` | R | 現有 | |
| `updatedAt` | M | 現有 | |
| `userId` | M | 現有 | |
| `syncStatus` | M·X | 現有 | |

### CDTransactionEntity

> 資料類型：**流水帳** —— 除了 id 與參照，**全部是 S，永不更新**

| 欄位 | 分類 | 狀態 | 說明 |
|------|------|------|------|
| `id` | R | 現有 | |
| `eventId` | R | 現有 | |
| `eventTitle` | **S** | 現有 | ⚠️ **快照，永不更新** → 刪掉 `EventRepository.updateRelatedTransactions` |
| `currency` | S | 現有 | |
| `itemsData` | S | 現有 | `[SummaryItemModel]` 的 JSON，整包都是 S。見 §5 |
| `totalAmount` | S | 現有 | 折扣後的實收金額 |
| `paymentMethod` | S | 現有 | cash / ePayment |
| `timestamp` | S | 現有 | 記錄建立時間 |
| `occurredAt` | S | 現有 | 補記帳的實際發生時間 |
| `discountType` | — | **刪除** | 由 `appliedDiscountsData` 取代 |
| `discountValue` | — | **刪除** | 同上 |
| `appliedDiscountsData` | S | **新增** | `[AppliedDiscount]` 的 JSON，含實際折抵金額快照 |
| `paymentQRCodeId` | R | **新增** | 用哪一張收款碼 |
| `paymentQRCodeLabel` | S | **新增** | 收款碼名稱快照 |
| `updatedAt` | M | **新增** | ⚠️ **pull cursor 必需**。建立時寫入，之後不變 |
| `userId` | M | 現有 | |
| `syncStatus` | M·X | 現有 | |

### CDInventoryChangeEntity

> 資料類型：**流水帳** —— 全部是 S

| 欄位 | 分類 | 狀態 | 說明 |
|------|------|------|------|
| `id` | R | 現有 | |
| `productId` | R | 現有 | |
| `change` | S | 現有 | +10 進貨 / −3 銷售 |
| `reason` | S | 現有 | |
| `customReason` | S | 現有 | |
| `transactionId` | R | 現有 | 僅銷售出庫時有值 |
| `timestamp` | S | 現有 | |
| `eventId` | R | 現有 | |
| `bundleId` | R | **新增** | 來自哪個組合／套餐 |
| `bundleName` | S | **新增** | 組合名稱快照 |
| `updatedAt` | M | **新增** | ⚠️ pull cursor 必需 |
| `userId` | M | 現有 | |
| `syncStatus` | M·X | 現有 | |

> ⚠️ 另需新增 `product` relationship + inverse。現況有 `event` 卻沒有 `product`，不對稱。

### CDQRCodeEntity

> 資料類型：**文件**。將改名為 `CDPaymentQRCodeEntity` 並改為集合語意（多張收款碼）

| 欄位 | 分類 | 狀態 | 說明 |
|------|------|------|------|
| `id` | R | 現有 | ⚠️ 查找一律用 `id`，**不要用 `userId`**（現況錯誤） |
| `title` | L | **新增** | 使用者自訂：「Line Pay」「街口」 |
| `colorIndex` | L | **新增** | 卡片顏色（內建色票）。**不內建第三方品牌 logo** |
| `note` | L | **新增** | |
| `sortOrder` | L | **新增** | 卡片順序，第一張 = 預設 |
| `isDisabled` | L | **新增** | 暫時停用 |
| `imageData` | **X** | 現有 | ⚠️ 型別改為 optional（現況非 optional，空值變 `Data()`） |
| `imageURL` | L | 現有 | |
| `createdAt` | R | 現有 | |
| `updatedAt` | M | 現有 | |
| `userId` | M | 現有 | |
| `syncStatus` | M·X | 現有 | |

### CDUserProfileEntity

> 資料類型：**文件**（singleton，以 `uid` 識別而非 UUID）

| 欄位 | 分類 | 狀態 | 說明 |
|------|------|------|------|
| `uid` | R | 現有 | 主鍵。Firebase Auth 發的，不是自產 UUID |
| `email` | L | 現有 | |
| `name` | L | 現有 | |
| `photoURL` | L | 現有 | ⚠️ 移除網址後綴的 `?t=timestamp`（多餘，害 Kingfisher 每次重下載） |
| `imageData` | **X** | 現有 | 本機頭貼 |
| `provider` | R | 現有 | google / apple |
| `accountStatus` | L | 現有 | guest / member |
| `membership` | **D** | 現有→降級 | ⚠️ 真相改為 StoreKit entitlement，此欄降為快取 |
| `expiryDate` | **D** | 現有→降級 | 同上 |
| `currentDeviceId` | L | 現有 | Device Handoff 用 |
| `createdAt` | R | 現有 | |
| `updatedAt` | M | 現有 | |
| `syncStatus` | M·X | 現有 | |

### CDPendingSyncOperation

> ⚠️ **整個 entity 刪除** —— 由 `CDOutboxOperation` 取代（見 `SYNC_ARCHITECTURE_V2.md` §7.6）

| 欄位 | 分類 | 狀態 | 說明 |
|------|------|------|------|
| `id` | M·X | **刪除** | |
| `entityId` | M·X | **刪除** | |
| `entityType` | M·X | **刪除** | |
| `operationType` | M·X | **刪除** | |
| `payload` | M·X | **刪除** | 新設計不存 payload，只存指標 |
| `createdAt` | M·X | **刪除** | |
| `retryCount` | M·X | **刪除** | |
| `lastError` | M·X | **刪除** | |

---

## 5. 內嵌模型分類表

> 以 JSON 存在 Binary 欄位內，沒有獨立的 CoreData entity。不受 §6 腳本檢查，**請手動維護**。

### SummaryItemModel（存於 `CDTransactionEntity.itemsData`）

> 資料類型：**流水帳** —— 全部是 S

| 欄位 | 分類 | 狀態 | 說明 |
|------|------|------|------|
| `id` | R | 現有 | |
| `productId` | R | 現有 | |
| `categoryId` | R | 現有 | ⚠️ **類別報表一律用這個快照分組**，不要用商品當前的類別 |
| `name` | S | 現有 | 商品名快照 |
| `price` | S | 現有 | 單價快照 |
| `category` | S | 現有 | 類別名快照 |
| `quantity` | S | 現有 | |
| `timestamp` | S | 現有 | |
| `originalSubtotal` | S | **新增** | 原價小計 = price × quantity |
| `allocatedDiscount` | S | **新增** | 分攤到的折扣（套餐差額 + 整筆折扣） |
| `actualRevenue` | S | **新增** | 實際營收 = original − allocated |
| `bundleId` | R | **新增** | |
| `bundleName` | S | **新增** | |

### DiscountModel（存於 `CDEventEntity.discountsData`）

> 資料類型：**文件**（是場次的設定）

| 欄位 | 分類 | 狀態 |
|------|------|------|
| `id` | R | 現有 |
| `type` | L | 現有 |
| `value` | L | 現有 |

### AppliedDiscount（存於 `CDTransactionEntity.appliedDiscountsData`）

> 資料類型：**流水帳** —— 全部是 S

| 欄位 | 分類 | 狀態 | 說明 |
|------|------|------|------|
| `discountId` | R | **新增** | 對應 `event.discounts` |
| `type` | S | **新增** | |
| `value` | S | **新增** | |
| `amount` | S | **新增** | ⚠️ 實際折抵金額快照 —— 之後改折扣設定，歷史不受影響 |

### BundleModel（存於 `CDEventEntity.bundlesData`）

> 資料類型：**文件**

| 欄位 | 分類 | 狀態 | 說明 |
|------|------|------|------|
| `id` | R | **新增** | |
| `name` | L | **新增** | |
| `price` | L | **新增** | 組合價 |
| `mode` | L | **新增** | fixed（套餐）/ chooseAny(N)（任選 N 個） |
| `productIds` | L | **新增** | 成員或候選清單 |
| `sortOrder` | L | **新增** | 套用優先順序 |
| `isDisabled` | L | **新增** | |

---

## 6. 驗證腳本

> 用途：**CoreData 有的欄位，分類表上一定要有。** 新增欄位卻忘記分類 → 腳本失敗。

腳本位置：`scripts/check_field_classification.py`

### 檢查規則

| 情況 | 結果 |
|------|------|
| CoreData 有、表上沒有 | ❌ **未分類** —— 必須補上 |
| 表上標「現有」、CoreData 沒有 | ❌ **表過期** —— 必須更新 |
| 表上標「新增」、CoreData 沒有 | ⏳ 待實作（正常） |
| 表上標「刪除」、CoreData 還有 | ⏳ 待移除（正常） |

### 執行

```bash
python3 scripts/check_field_classification.py
```

建議加入 CI，或在每次改 `Tilli.xcdatamodeld` 後手動跑一次。

### 已驗證（2026-09-12）

**正向**：對現況執行 → `✅ 所有 CoreData 屬性都已分類`（87 屬性全數對上，退出碼 0）

**反向**：故意從分類表刪掉 `sortOrder` 那一列後執行 →

```
❌ 錯誤（2）
   CDCategoryEntity.sortOrder → ❌ 未分類
   CDProductEntity.sortOrder → ❌ 未分類
退出碼 = 1
```

腳本確實抓得到漏掉的欄位，不是只會回報成功。

### 目前的計畫中項目（24）

| 類型 | 數量 | 內容 |
|------|------|------|
| ⏳ 待實作（表上有、CoreData 還沒有） | 13 | `bundlesData`、`appliedDiscountsData`、`paymentQRCodeId/Label`、Transaction 與 InventoryChange 的 `updatedAt`、`bundleId/bundleName`、PaymentQRCode 的 5 個新欄位 |
| ⏳ 待移除（CoreData 有、表上標刪除） | 11 | `CDPendingSyncOperation` 全部 8 個、`Product.categoryName`、`Transaction.discountType/discountValue` |

數字校驗：87（CoreData）+ 13（待實作）= 100（分類表列數）✅

---

## 7. 執行總覽

```
① 刪除同步層（見 §8）                                    半天
② 建立本文件 + 驗證腳本                                   ✅ 已完成
③ 本機功能開發   → FEATURE_PLAN_V1.md 第 0～6 批          主要工作
④ 重建同步       → SYNC_ARCHITECTURE_V2.md Phase 0～9     最後
```

### 為什麼 ① 要先做

留著 4,171 行註定要重寫的同步程式碼，代價是**每改一次 schema 都要考慮「會不會弄壞舊同步」**。刪掉之後功能開發就是純本機的，心智負擔歸零。

### 為什麼 ② 能保證不漏

| | 清單式追蹤 | **窮舉式分類（本文件）** |
|---|---|---|
| 形式 | 「這次又加了什麼」的流水清單 | 每個欄位都在表上 |
| 保證來源 | 靠記得登記 | **靠結構** |
| 驗證 | 無法驗證 | **腳本自動比對** |

到了 ④ 重建同步時，**這張表就是完整規格** —— 逐列照做即可，不需要回頭考古。

---

## 8. 第一步：刪除同步層

### 8.1 刪除前先抽出（否則會編譯失敗）

| 要保留的 | 現在在哪 | 被誰用 | 搬到 |
|---|---|---|---|
| `processImageForLocal` + `ImageType` | `ImageSyncService.swift` | **5 處**：`ProductModel:36`、`QRCodeModel:29`、`UserProfileModel:38` 的 `image` setter、`AddNewProductViewModel:351`、`SyncableImageView:81` | `Utilities/Helpers/ImageProcessor.swift`（新建） |
| `SyncStatus` enum | `CDPendingSyncOperation+CoreDataProperties.swift` | 2 處 Repository | CoreData 共用檔 |

### 8.2 刪除清單

| 檔案 / 項目 | 行數 | 外部依賴 |
|---|---|---|
| `Data/Sync/SyncManager.swift` | 1,246 | 9 個檔案呼叫 → 一併拔除 |
| `Data/Sync/FirestoreUploader.swift` | 984 | 無 |
| `Data/Sync/FirestoreDownloader.swift` | 932 | 無 |
| `Data/Sync/ModelFirestoreExtensions.swift` | 427 | 無 |
| `Data/Sync/ImageSyncService.swift` | 292 | 抽出 §8.1 後可刪 |
| `Data/Sync/HybridSyncListener.swift` | 165 | 無 |
| `Data/Sync/DecimalHelper.swift` | 60 | 僅被 `ModelFirestoreExtensions` 使用 |
| `CDPendingSyncOperation` entity | — | |
| `.syncDidComplete` 通知 | — | 3 個 Repository 訂閱 → 一併移除 |
| **合計** | **4,106** | |

**保留**：`Data/Sync/NetworkMonitor.swift`（65 行，登入前檢查網路用）、Firebase Auth、Cloud Functions、Firebase SDK。

### 8.3 要拔除 `SyncManager` 呼叫的 9 個檔案

```
Tilli/TilliApp.swift
Tilli/View/EventsPage/RootTabView.swift          ← 含全螢幕轉圈的遮罩
Tilli/View/MyPage/TilliProSheetView.swift
Tilli/ViewModel/QRCodeViewModel.swift
Tilli/Data/Repositories/EventRepository.swift
Tilli/Data/Repositories/ProductRepository.swift
Tilli/Data/Repositories/InventoryChangeRepository.swift
Tilli/Data/Repositories/QRCodeRepository.swift
Tilli/Data/Repositories/AuthenticationManager.swift  ← 保留 Auth，只拔同步
```

### 8.4 刪除後的狀態

- `userId` 欄位照常填入（`Auth.auth().currentUser?.uid ?? guestUserId`），只是沒有東西會上傳
- `syncStatus` 欄位保留，一律維持 `pending`（重建同步時才有意義）
- `imageURL` 欄位保留但永遠是 nil（本機只用 `imageData`）
- 登入流程保留可測，但登入後不會發生任何同步

---

## 版本記錄

| 日期 | 變更 |
|------|------|
| 2026-09-12 | 初版。全專案掃描：8 entity / 87 屬性 / 8 關聯，建立六種分類與完整分類表、驗證腳本、刪除同步層的執行清單 |

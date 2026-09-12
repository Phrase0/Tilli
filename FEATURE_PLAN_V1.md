# Tilli 功能規劃 v1：流程統一、折扣、組合套餐

> 建立日期：2026-09-11　最後更新：2026-09-12
> 範圍：本輪功能改動 + **全專案流程統一重構**
> 同步架構見 `SYNC_ARCHITECTURE_V2.md`
>
> 📐 **資料結構以 `ARCHITECTURE.md` 為準。**
> 任何欄位的分類（即時值／快照／推導／純本機）、以及同步時怎麼處理，都看那份。
> 本文件與它衝突時，以 `ARCHITECTURE.md` 為準。

> **前提：App 尚未上架、沒有真實使用者。**
> 不需考慮資料轉移、不需考慮歷史資料一致性、可直接刪 App 重裝。
> 本文件只追求「正確、統一、沒有多餘的設計」。

---

## 目錄

1. [完整查核結果（24 項）](#1-完整查核結果24-項)
2. [共用元件設計](#2-共用元件設計)
3. [功能 A：刪除與停用規則](#3-功能-a刪除與停用規則)
4. [功能 B：編輯限制（維持現況）](#4-功能-b編輯限制維持現況)
5. [功能 C：報表調整](#5-功能-c報表調整)
6. [功能 D：折扣 UI 與多重折扣](#6-功能-d折扣-ui-與多重折扣)
7. [功能 E：折扣攤提移到結帳](#7-功能-e折扣攤提移到結帳)
8. [功能 F：組合優惠與套餐](#8-功能-f組合優惠與套餐)
9. [功能 G：POS 類別列](#9-功能-gpos-類別列)
10. [功能 H：庫存 +/−（Backlog）](#10-功能-h庫存-backlog)
11. [執行順序](#11-執行順序)
12. [測試清單](#12-測試清單)
13. [待確認事項](#13-待確認事項)

---

## 1. 完整查核結果（24 項）

> 掃描範圍：全專案 114 個 Swift 檔（排除 `_Deprecated/`），21,468 行。

### 1.1 🔴 資料源不一致（6 項，本輪主要目標）

| # | 問題 | 位置 | 後果 |
|---|------|------|------|
| **A1** | **「是否有交易」有 5 個實作，類別的兩個判斷依據相反** | `InventoryViewModel:454`、`AddNewProductViewModel:309`、`AddEventViewModel:381`、`ProductRepository:235`、`EventRepository:602` | 同一個問題會得到不同答案 |
| **A2** | **event 的新鮮度機制不一致** | `POSViewModel:18` 用 `@Binding`（自動更新）；`InventoryViewModel:98` 值複製 + `InventoryView:130` 的 `onChange` 手動補救 | 兩套機制，其中一套靠 View 層補丁 |
| **A3** | **商品是「新鮮的」、類別是「快照」** | 商品每次 `fetchProducts()` 現查；類別來自傳入的 `event.categories` | 別處改了類別，POS/庫存頁的過濾條件是舊的 |
| **A4** | **`transactionSummary` 重複 2 次，而且加法不同** | `EventsViewModel:35` 用原生 `+`；`EventsCalendarViewModel:134` 用 `MoneyHelper.add` | 同一個數字兩種算法，捨入可能不同 |
| **A5** | **三個報表方法各自重複 fetch 同一份交易** | `ProductPerformanceViewModel:194/305/451` | 同一個 timeRange 查 3 次資料庫 |
| **A6** | **兩張報表營收口徑不同** | 銷售分析用 `transaction.totalAmount`；商品績效從 items 重新攤提 | 目前巧合一致，加套餐後必定分歧 |
| **A7** | **兩個反正規化欄位的維護方式相反：一個太多、一個太少** | `EventRepository:321-327`（`categoryName`）vs `:581-599`（`eventTitle`） | 一個造成更新風暴、一個造成本機與雲端不一致 |

#### A1 的具體衝突

```
商品 A 原在「大福」類別，賣了 10 個（SummaryItem.categoryId = 大福）
之後 A 被移到「特價品」類別

「大福」有交易嗎？    AddEventViewModel:381 說有（快照） ／ EventRepository:602 說沒有（現在沒這商品）
「特價品」有交易嗎？  AddEventViewModel:381 說沒有       ／ EventRepository:602 說有（現在有 A，A 賣過）
```

兩者分別被「UI 要不要顯示刪除鍵」和「repository 要不要擋刪除」使用 —— 意見不合時行為無法預測。

#### A7 的具體問題

改場次名稱與改類別名稱，都會去回頭更新已經寫好的資料，但**兩者的做法完全相反**：

| | `categoryName`（`EventRepository:321-327`） | `eventTitle`（`EventRepository:581-599`） |
|---|---|---|
| 更新本機 | ✅ | ✅ |
| 設 `syncStatus = "pending"` | ✅ | ❌ **沒有** |
| 設 `updatedAt` | ✅ | ❌ **沒有** |
| 實際後果 | **更新風暴** —— 改一次類別名 = 該類別所有商品重新上傳 | **本機與雲端不一致** —— 本機顯示新場次名，雲端／其他裝置／重裝後顯示舊名 |

**一個做太多、一個做太少，而且都錯。** 正確答案是同一條原則：

| 欄位 | 所屬 | 正解 |
|------|------|------|
| `Transaction.eventTitle` | 流水帳 | **是歷史快照，根本不該更新** → 刪掉 `updateRelatedTransactions`，不一致自然消失 |
| `Product.categoryName` | 文件 | **是冗餘欄位，不該存在** → 刪除欄位，顯示時從 relationship 查，更新風暴自然消失 |

> `InventoryViewModel:255 / :354` 已經示範了正確做法（`getCategoryName(for: categoryId)` 從類別查），
> 只有 `POSViewModel:258` 還在用 `product.categoryName`。移除成本比想像低。

### 1.2 🔴 重複計算（6 項）

| # | 問題 | 重複次數 | 位置 |
|---|------|---------|------|
| **B1** | 折扣金額計算（`switch discountType`） | **3 次**（同一檔案內） | `ProductPerformanceViewModel:218 / :329 / :475` |
| **B2** | `transactionSubtotal` 的 reduce | **3 次** | `ProductPerformanceViewModel:207 / :318 / :464` |
| **B3** | 交易 fetch + timeRange 判斷樣板 | **4 次** | `ProductPerformanceViewModel:192-200 / :303-311 / :449-457`、`SalesAnalyticsViewModel:342-350` |
| **B4** | 折扣 switch 散落 | **7 處** | `POSViewModel:202 / :216 / :229`、`TransactionHistoryViewModel:240`、`ProductPerformanceViewModel` ×3 |
| **B5** | CSV 建檔樣板（temp dir + 檔名淨化 + 寫入） | **9 次** | `ProductPerformanceViewModel` ×2、`InventoryViewModel` ×2、`SalesAnalyticsViewModel` ×4、`TransactionHistoryViewModel` ×1 |
| **B6** | 商品可販售判斷（`isDisabled`） | **6 處**，只有 1 處檢查兩層 | `POSViewModel:41/54/110`、`POSView:97`、`AddNewProductViewModel:62`、`InventoryViewModel:69/123` |

#### B6 的隱性 bug

```swift
// POSViewModel:45 —— 找不到 category 時 nil == false → false → 商品被【靜默隱藏】
let isCategoryEnabled = categories.first(where: { $0.id == product.categoryId })?.isDisabled == false
```

其餘 5 處只檢查一層，所以「類別停用但商品顯示出來」在部分畫面會發生。

### 1.3 🟠 寫入路徑不一致（4 項）

| # | 問題 | 位置 |
|---|------|------|
| **C1** | 設了 `syncStatus` 但沒設 `updatedAt` | `EventRepository:397`（交易）、`:494`（複製場次的庫存異動）、`InventoryChangeRepository:32`、`:53` |
| **C2** | `CDTransactionEntity` / `CDInventoryChangeEntity` **沒有 `updatedAt` 欄位** | CoreData model |
| **C3** | **Transaction / InventoryChange 的 `toFirestoreData` 沒有 `updatedAt`** | `ModelFirestoreExtensions:187 / :271` |
| **C4** | 每個 Repository 各自寫 `syncStatus = "pending"` + `updatedAt = Date()`（14 + 8 + 2 + 1 處） | 全部 Repository |

> **C2 / C3 對現況是正確的**（流水帳 append-only，下載用 skip-if-exists，不需要 LWW）。
> **但對新架構的 pull-by-cursor 是致命的** —— 沒有 server-side 時間欄位就無法做增量下載。
> 已同步修正 `SYNC_ARCHITECTURE_V2.md`，見 §1.6。

### 1.4 🟡 Dead code 與遺留（5 項）

| # | 項目 | 位置 | 說明 |
|---|------|------|------|
| **D1** | `MoneyHelper.applyDiscount(price:discountPercentage:)` | `MoneyHelper:152` | 舊的「商品級固定折扣」遺留，**全專案無人呼叫** |
| **D2** | `MoneyHelper.calculateTotal(price:quantity:discountPercentage:)` | `MoneyHelper:163` | 同上，**無人呼叫** |
| **D3** | 有交易 → 自動停用（商品） | `ProductRepository:204` | **不可達**：`InventoryViewModel:558 getActionType` 已先擋 |
| **D4** | 有交易 → 自動停用（類別） | `EventRepository:267` | **不可達**：`AddEventViewModel:487 getSwipeAction` 已先擋 |
| **D5** | `ProductSalesStats.unitPrice` + 註解「假設同商品單價一致」 | `ProductPerformanceService:20/31` | 就是價格被鎖住的根因 |

### 1.5 🟠 效能（3 項）

| # | 問題 | 量級 |
|---|------|------|
| **E1** | `hasTransaction` 對每個商品做全表掃描 + JSON decode | `InventoryView` 50 商品 × 500 交易 = **25,000 次 decode** |
| **E2** | 報表三個方法各自查一次 DB | 每次切換 timeRange = **3 次重複查詢** |
| **E3** | `EventsCalendarViewModel:108 / :114` 每次呼叫 `DateFormatter()` | DateFormatter 建立成本高，且已有共用的 `Extension/DateFormatter.swift`（7 個 static） |

### 1.6 ⚠️ 跨文件架構漏洞（已同步修正）

**`SYNC_ARCHITECTURE_V2.md` §6.2 假設所有資料文件都有 `updatedAt`（serverTimestamp）供 pull cursor 使用，但 Transaction / InventoryChange 實際上沒有這個欄位。**

修正方向（已寫入同步文件）：
- 流水帳也要有 server-side 時間欄位，**統一叫 `updatedAt`**
- 值 = 建立當下的 `serverTimestamp()`，之後**永不改變**（append-only）
- 這樣 `SyncableEntity.updatedAt` 對六個 collection 都成立，pull 不需要分支

---

## 2. 共用元件設計

上面 24 項用 **7 個共用元件**一次收斂。

### 2.1 `TransactionIndex` — 取代 5 個 `hasTransaction`（解 A1、E1）

```swift
/// 一次掃描全場次交易，建立索引供重複查詢
struct TransactionIndex {
    private let soldProductIds: Set<UUID>
    private let soldCategoryIds: Set<UUID>     // ⭐ 一律用 SummaryItem.categoryId 快照
    let hasAnyTransaction: Bool

    init(transactions: [TransactionModel]) {
        var products = Set<UUID>(), categories = Set<UUID>()
        for tx in transactions {
            for item in tx.items {
                products.insert(item.productId)
                categories.insert(item.categoryId)
            }
        }
        self.soldProductIds = products
        self.soldCategoryIds = categories
        self.hasAnyTransaction = !transactions.isEmpty
    }

    func hasTransaction(productId: UUID) -> Bool { soldProductIds.contains(productId) }
    func hasTransaction(categoryId: UUID) -> Bool { soldCategoryIds.contains(categoryId) }
}
```

**為什麼類別一律用快照**：「這個類別曾經賣過東西嗎」問的是歷史事實。商品之後被搬走，不改變「當時它在這個類別賣掉」的事實。用「目前的商品清單」判斷，答案會隨商品搬移而改變 —— 那不是歷史事實。

`EventRepository:602 hasRelatedTransactionsForCategory`（用當前商品那套）**整段刪除**。

效能：25,000 次 decode → 500 次（掃一次），之後都是 `Set.contains` O(1)。

### 2.2 `EventDataSource` — 單一場次的統一資料源（解 A2、A3、A5、E2）

```swift
/// 一個場次的完整資料快照，由 View 層建立一次，所有 ViewModel 共用
@MainActor
final class EventDataSource: ObservableObject {
    @Published private(set) var event: EventModel
    @Published private(set) var products: [ProductModel]
    @Published private(set) var categories: [CategoryModel]     // = event.categories，一起更新
    @Published private(set) var transactions: [TransactionModel]
    @Published private(set) var inventoryChanges: [InventoryChangeModel]
    @Published private(set) var transactionIndex: TransactionIndex

    /// 重新載入全部（資料變更 或 .syncDidComplete 時呼叫）
    func reload()

    /// 依時間範圍取交易（報表用，不重複查 DB）
    func transactions(in range: DateInterval?) -> [TransactionModel]
}
```

| 解決 | 說明 |
|------|------|
| **A2** | event 只有一個來源，不再有「@Binding vs 值複製」兩套機制 |
| **A3** | 商品與類別**一起**重載，不會一新一舊 |
| **A5 / E2** | 報表三個方法共用同一份 `transactions`，不再各自查 DB |
| **E1** | `transactionIndex` 建立一次，全場次共用 |

**取代**：`InventoryView:130` 的 `onChange(of: eventDataManager.events)` 補丁、各 ViewModel 的 `updateDataManagers()`。

### 2.3 `DiscountCalculator` — 取代散落 7 處的折扣計算（解 B4、B1）

```swift
enum DiscountCalculator {
    /// 折扣金額（已 clamp，保證 0 <= result <= subtotal）
    static func amount(for discounts: [AppliedDiscount], subtotal: Decimal) -> Decimal

    /// 套用折扣後的總額（先百分比、後定額）
    static func total(subtotal: Decimal, discounts: [AppliedDiscount]) -> Decimal

    /// 顯示文字
    static func displayText(for discount: AppliedDiscount, currency: String) -> String
}
```

**clamp 內建其中** —— 現況只有 `POSView:59` 呼叫 `effectiveDiscount()` 做保護，換個入口就會存進未 clamp 的折扣，報表攤提會算出**負營收**。保護不該依賴 View 層記得呼叫。

### 2.4 `RevenueAllocator` — 結帳時攤提（解 A6、B1、B2）

```swift
enum RevenueAllocator {
    /// 結帳當下把套餐差額與整筆折扣攤提到每個項目
    static func allocate(
        items: [SummaryItemModel],
        bundleApplications: [BundleApplication],
        discounts: [AppliedDiscount]
    ) -> [SummaryItemModel]     // 回傳已填好 actualRevenue 的 items
}
```

做完後 `ProductPerformanceViewModel` 的三處攤提（B1）與三處 subtotal reduce（B2）**整段刪除**，報表變成單純加總，兩張報表口徑自動統一（A6）。

### 2.5 `ProductAvailability` — 統一可販售判斷（解 B6）

```swift
extension ProductModel {
    /// 可在 POS 販售：未下架、所屬類別存在且未停用
    func isAvailableForSale(in categories: [CategoryModel]) -> Bool {
        guard !isDisabled else { return false }
        guard let category = categories.first(where: { $0.id == categoryId }) else {
            assertionFailure("商品 \(name) 的類別 \(categoryId) 不存在")
            Log.warning("商品 \(id) 的類別不存在，視為不可販售")
            return false      // fail-closed，但【有留下痕跡】
        }
        return !category.isDisabled
    }
}
```

6 處判斷全部改用它，並修掉「找不到 category 就靜默隱藏」。

### 2.6 `CSVExporter` — 取代 9 次建檔樣板（解 B5）

```swift
enum CSVExporter {
    /// 寫入暫存檔並回傳 URL（檔名自動淨化 + 時間戳）
    static func write(content: String, label: String, eventTitle: String) -> URL

    /// 共用的 CSV 逸出（處理逗號、引號、換行）
    static func escape(_ field: String) -> String
}
```

9 個 `createXXXCSVFileURL()` 各自做 temp dir、檔名淨化、時間戳、寫入 —— 全部改呼叫這個。

> 順帶：現行 CSV 產生沒有統一的欄位逸出，商品名稱含逗號或引號時會產生壞掉的 CSV。`escape()` 一併修掉。

### 2.7 `PendingSyncStamp` — 統一寫入標記（解 C1、C4）

```swift
extension NSManagedObject {
    /// 標記為待同步：一律同時設定 syncStatus 與 updatedAt（若該 entity 有此欄位）
    func markPendingSync(at date: Date = Date()) {
        setValue(SyncStatus.pending.rawValue, forKey: "syncStatus")
        if entity.attributesByName["updatedAt"] != nil {
            setValue(date, forKey: "updatedAt")
        }
    }
}
```

現況 25 處各自寫 `syncStatus = "pending"`，其中 **4 處漏了 `updatedAt`**（C1）。改用統一方法後不可能再漏，未來新增 entity 也自動涵蓋。

> `updatedAt` 是同步架構的 LWW 依據（`SYNC_ARCHITECTURE_V2.md` §6.2），漏設會讓衝突判斷選錯版本。

---

## 3. 功能 A：刪除與停用規則

### 3.1 規則（維持現況邏輯，只修正表達方式）

| 對象 | 無交易紀錄 | 有交易紀錄 |
|------|-----------|-----------|
| 商品 | ✅ 可刪除 | ❌ 只能下架 |
| 類別 | ✅ 可刪除 | ❌ 只能停用 |

**理由**：刪除後重建同名商品會讓報表統計分裂（兩個 UUID、同一個名字）。而「下架」已達成「管理頁清乾淨」的目的。

### 3.2 修正：守衛留著，但誠實失敗

```swift
// ❌ 現況（ProductRepository:204 / EventRepository:267）：靜默做了別的事
if hasRelatedTransactions(...) {
    entity.isDisabled = true
    return .disabledInstead("此產品已有交易記錄，已改為停用狀態")
}

// ✅ 改成：明確拒絕
if transactionIndex.hasTransaction(productId: productId) {
    return .failed(String.localized("productCannotDeleteHasTransactions"))
}
```

守衛保留的理由：repository 是最後一道防線，將來若有新呼叫點（批次刪除、匯入）會需要。但它不該「偷偷做別的事」。

### 3.3 連帶清理

| 項目 | 動作 |
|------|------|
| `ProductDeletionResult.disabledInstead` | **移除這個 case** |
| `InventoryViewModel:475` 對應分支 | **移除** |
| `ProductRepository:235 hasRelatedTransactions` | **刪除**，改用 `TransactionIndex` |
| `EventRepository:602 hasRelatedTransactionsForCategory` | **刪除**，改用 `TransactionIndex` |
| 3 個 ViewModel 的 `hasTransaction` | **刪除**，改用 `TransactionIndex` |

### 3.4 同名檢查：不需要修改

`ProductRepository:284 fetchProducts(forEventId:)` 沒有 `isDisabled` 過濾，`checkDuplicateName` 已經涵蓋下架商品。檢查範圍限「同一類別內」也是對的（跨類別同名合理）。

> 未來若引入 tombstone，同名檢查要**排除 `deletedAt != nil` 的商品**。

---

## 4. 功能 B：編輯限制（維持現況）

### 4.1 決定：名稱、價格、類別在有交易後**維持不可編輯**

現況 `AddNewProductView:51/88/170` 的 `.disabled(isEditingWithTransaction)` 與 `AddEventViewModel:413 canEditCategoryName` **全部保留**。

理由：開放編輯會牽動報表的顯示語意與類別歸屬，而 A1 的判斷不一致尚未收斂前，風險大於效益。等本輪統一完成、觀察一段時間再評估。

### 4.2 但要修 `unitPrice` 的假設（D5）

即使不開放改價，這行仍然是錯的：

```swift
// ProductPerformanceService:31
self.unitPrice = unitPrice // 假設同商品單價一致
```

**因為組合優惠與套餐會讓同一商品出現不同的成交單價**（§8）。改成計算屬性：

```swift
var averageUnitPrice: Decimal {
    totalQuantity > 0 ? MoneyHelper.divide(originalRevenue, Decimal(totalQuantity)) : 0
}
```

`originalRevenue` 本來就是用每筆快照單價逐筆累加，總額一直正確，只需換顯示方式。

### 4.3 UI：維持 disabled，不要隱藏

| | 隱藏 | disabled + 灰字（現況） |
|---|------|---------------------------|
| 看得到目前的值嗎 | ❌ | ✅ |
| 使用者反應 | 「怎麼沒有價格欄位？是 bug 嗎？」 | 「喔，有交易了不能改」 |

現況做法正確。只建議把提示文案寫清楚原因。

---

## 5. 功能 C：報表調整

### 5.1 熱門商品榜單 → 商品銷售排行

| 項目 | 現況 | 改為 |
|------|------|------|
| 範圍 | 只有賣過的商品（從交易反推） | **列出所有商品**，沒賣過的銷量 0 |
| 單價欄 | `unitPrice`（失真） | **平均單價**（§4.2） |
| 資料來源 | 三個方法各自查 DB | **共用 `EventDataSource`**（§2.2） |
| 攤提 | 報表時算（重複 3 次） | **結帳時已算好**，直接加總（§7） |

**「列出所有商品」的實作**：先從 `EventDataSource.products` 建立骨架，再用交易資料填入銷售數字。不能只從交易反推。

### 5.2 欄位精簡

| 欄位 | 建議 |
|------|------|
| 排名、商品名、類別、銷量 | ✅ 保留 |
| **實際營收** | ✅ **必須保留** —— 拿掉就跟實際收到的錢對不起來 |
| 原價總額、折扣金額 | 🤔 可拿掉或收進展開區 |
| 貢獻率 | 可留可不留 |

### 5.3 營收口徑統一（解 A6）

做完功能 E 後：

| 報表 | 營收來源 |
|------|----------|
| 銷售分析（日/月） | `transaction.totalAmount` |
| 商品績效 | `Σ SummaryItem.actualRevenue` |

兩者數學上相等（攤提總和 = 總額），捨入差額由「最後一項吃掉」保證。**測試 R2 專門驗證這件事。**

---

## 6. 功能 D：折扣 UI 與多重折扣

> ### ⚠️ 與 `DISCOUNT_REFACTOR_PLAN.md` 的關係
>
> 該文件是**已完成的歷史文件** —— 描述的結構（`EventModel.discounts`、
> `TransactionModel.discountType/discountValue`、`CDEventEntity.discountsData`）
> 與現行程式碼吻合，重構已做完。
>
> 但其中兩點**已被本文件取代，不可再依循**：
>
> | 舊文件的決策 | 本文件取代為 |
> |---|---|
> | 「折扣不可疊加（每筆訂單只能套用一個）」 | **可同時一個百分比 + 一個定額**（§6.1） |
> | UI 位置在 `ProductDetailView` | 該檔已移入 `_Deprecated/`，折扣 UI 在 `POSView` |
>
> 其餘內容（Event 級別自訂折扣、兩種折扣型別、金額折扣針對整筆訂單）仍然成立。

### 6.1 Schema 變更

```swift
// ❌ 現況：Transaction 只能存一個折扣
var discountType: DiscountType?
var discountValue: Decimal?

// ✅ 改成
var appliedDiscounts: [AppliedDiscount]     // 最多一個 percentage + 一個 amount

struct AppliedDiscount: Codable, Hashable {
    var discountId: UUID      // 對應 event.discounts 的設定
    var type: DiscountType
    var value: Decimal
    var amount: Decimal       // ⭐ 快照：實際折抵金額（clamp 後）
}
```

`amount` 快照很重要 —— 否則之後改了折扣設定，歷史交易的折抵金額會算錯。

CoreData：`CDTransactionEntity` 的 `discountType` / `discountValue` → 改為 `appliedDiscountsData: Binary`（沿用 `itemsData` / `discountsData` 的模式）。

### 6.2 計算順序

```
先百分比、後定額

100 元 × 9折 = 90 → −10 = 80   ✅ 採用
(100 − 10) × 0.9 = 81          ❌ 不採用（差 1 元）
```

### 6.3 Clamp 規則

```
定額折抵 = min(折扣值, 套用百分比後的金額)
最終總額永遠 >= 0
```

內建在 `DiscountCalculator`（§2.3），不再依賴 View 層。

### 6.4 UI

```
┌──────────────────────────────┐
│  折扣                         │
│  百分比（單選，可取消）        │
│   [95%] [9折] [85折] [8折]    │  ← 升冪排列
│                              │
│  折抵金額（單選，可取消）      │
│   [−5] [−10] [−20] [−50]     │  ← 升冪排列
│                              │
│  小計 200 → 折後 160          │  ← 即時顯示
└──────────────────────────────┘
```

兩區分開各自單選（可再點一次取消），已選 chip 高亮，升冪排列，不提供拖曳換序。

---

## 7. 功能 E：折扣攤提移到結帳

### 7.1 為什麼要做

| 理由 | 狀態 |
|------|------|
| 歷史數字凍結 | ❌ 已確認無所謂（App 未上架） |
| **消除重複 3 次的攤提邏輯（B1、B2）** | ✅ 成立 |
| **統一兩張報表營收口徑（A6）** | ✅ 成立 |
| **加套餐時只改一處** | ✅ **成立，主要理由** |

套餐的攤提若在報表時算，報表要反推「這幾個 item 屬於同一個套餐、套餐價多少、差額怎麼分」—— 但套餐設定可能已經改了。

### 7.2 `SummaryItemModel` 擴充

```swift
struct SummaryItemModel: Identifiable, Codable, Hashable {
    // 既有快照
    var id, productId, name, price, categoryId, category, quantity, timestamp

    // ⭐ 新增
    var originalSubtotal: Decimal    // 原價小計 = price × quantity
    var allocatedDiscount: Decimal   // 分攤到的折扣總額（套餐差額 + 整筆折扣）
    var actualRevenue: Decimal       // 實際營收 = original − allocated
    var bundleId: UUID?              // 來自哪個組合／套餐
    var bundleName: String?          // 組合名稱快照
}
```

### 7.3 攤提順序

```
① 原價小計        = Σ(price × quantity)
② 套餐／組合價差額 → 攤提到該組合成員（按各自原價比例）
③ 整筆百分比折扣   → 按 ② 之後的金額比例攤提到所有項目
④ 整筆定額折扣     → 同上
⑤ 捨入差額         → 最後一項吃掉
```

⚠️ 金額全部用整數（分）運算，避免捨入誤差累積。

### 7.4 報表端改動

`ProductPerformanceViewModel` 三處攤提（`:218/:329/:475`）與三處 subtotal reduce（`:207/:318/:464`）**整段刪除**：

```swift
productStats[productId]?.addSale(
    quantity: item.quantity,
    originalTotal: item.originalSubtotal,
    actualTotal: item.actualRevenue       // 直接用，不再計算
)
```

---

## 8. 功能 F：組合優惠與套餐

### 8.1 存放方式：沿用 `discountsData` 模式

`CDEventEntity` 已有 `discountsData: Binary`（折扣以 JSON 序列化存在 Event 上）。**組合／套餐用同一套**：新增 `CDEventEntity.bundlesData: Binary`。

| 好處 | 說明 |
|------|------|
| 零新 CoreData entity | 不用改 relationship、不用 migration mapping |
| 零新 Firestore collection | 跟著 Event 文件一起同步 |
| **零新同步邏輯** | 不用寫 `SyncableEntity` conformance、不用加進 pull 順序 |
| 不需要 tombstone | 用 `isDisabled` 就夠 |

唯一代價：改一個 bundle 會讓整個 Event 文件重新上傳。Event 只有幾 KB，可接受。

### 8.2 Model

```swift
struct BundleModel: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String              // 「任選三個」「下午茶套餐」
    var price: Decimal            // 組合價
    var mode: BundleMode
    var productIds: [UUID]        // fixed: 成員；chooseAny: 候選清單
    var sortOrder: Int            // 套用優先順序（可拖曳）
    var isDisabled: Bool = false
}

enum BundleMode: Codable, Hashable {
    case fixed                    // 套餐：productIds 全部都要，各一個
    case chooseAny(count: Int)    // 組合優惠：從候選清單任選 N 個
}
```

- **任選三個 100** → `.chooseAny(count: 3)`，`productIds` = 勾選的候選商品，`price` = 100
- **套餐** → `.fixed`，`productIds` = [大福, 抹茶, 紅豆]，`price` = 100

> `.fixed` 第一版每個成員固定 1 個。若未來需要「A×2 + B×1」，把 `productIds: [UUID]` 換成 `items: [BundleItem]`。

### 8.3 ⚠️ 兩種 mode 的互動方式完全不同

| | `.chooseAny`（組合優惠） | `.fixed`（套餐） |
|---|---|---|
| 怎麼進購物車 | **背景規則，自動套用** | **使用者主動點選**，像商品一樣 |
| POS 呈現 | 不出現在商品列表 | **出現在 POS，有獨立區塊** |
| 結帳頁顯示 | 「已套用 任選三個100 × 2 組，折抵 NT$40」 | 「下午茶套餐 × 1」 |
| 可否手動取消 | ✅ 結帳頁可取消 | 從購物車移除 |

資料層、庫存扣減、報表、同步四層共用，只有「怎麼進購物車」不同。

### 8.4 自動套用演算法（`.chooseAny`）

```
1. 找出購物車中符合候選清單的項目，展開成單品列表
2. 依【單價由高到低】排序        ← 對客人最有利，業界慣例
3. 每 N 個一組，套用組合價
4. 剩餘不足 N 個的照原價
```

**不讓使用者手選**（結帳要快），但要在結帳頁顯示套用結果並允許手動取消。

**多個組合同時符合**：依 `sortOrder` **貪婪套用**，使用者可拖曳排序決定優先權。第一版不做組合最佳化 —— 簡單、可預測。

### 8.5 庫存扣減

**扣成員商品的實際庫存。** 一筆套餐銷售 → N 筆 `InventoryChange`（每個成員一筆）。

`InventoryChangeModel` 新增兩欄，否則報表算不出「套餐賣了幾份」：

```swift
var bundleId: UUID?        // 來自哪個組合／套餐
var bundleName: String?    // 快照
```

### 8.6 可用性判斷：不擋、提示、自動失效

| 方案 | 評價 |
|------|------|
| (a) 要先下架套餐才能下架商品 | ❌ 擋住使用者。攤主可能只是今天缺貨 |
| (b) 下架商品 → 套餐自動下架 | ⚠️ 商品回來時套餐不會自己回來，狀態會亂 |
| **(c) 不擋，提示 + 自動變不可販售** | ✅ **採用** |

```
下架商品時    → 提示「有 2 個組合包含此商品，下架後這些組合將無法販售」
POS          → 該組合灰掉，顯示「含已下架商品」
組合管理頁    → 顯示 ⚠️ 警告標記
商品上架回來  → 組合【自動】恢復可販售
```

**關鍵：可不可賣是「算出來的」而不是「存起來的」** —— 跟 §2.5 同一原則。

```swift
extension BundleModel {
    /// 可販售：未停用、所有成員都存在且可販售
    func isAvailable(products: [UUID: ProductModel], categories: [CategoryModel]) -> Bool
}
```

### 8.7 放哪裡設定

場次工作區新增分頁「**組合／套餐**」，與「管理商品」同層。內部用 segmented control 切換兩區。

---

## 9. 功能 G：POS 類別列

### 9.1 需求

POS 最上方橫向類別列：`[全部] [類別1] [類別2] …`，點擊跳躍。
**用文字小框框（chip），不做 icon**（類別無 icon 欄位，不新增）。

### 9.2 實作要點

| 項目 | 說明 |
|------|------|
| 跳躍 | `ScrollViewReader` + `scrollTo(id:anchor:.top)` |
| 高亮 | 捲動主列表時偵測目前類別，chip 對應高亮 |
| chip 列自動捲動 | 類別多時自動捲到當前類別 |
| 「全部」 | 固定最前面，捲到頂端 |
| 過濾 | 只顯示未停用類別 |

### 9.3 順帶修正

`POSViewModel:41-45` 等 6 處的可販售判斷全部改用 `isAvailableForSale`（§2.5），修掉「找不到 category 就靜默隱藏」。

---

## 10. 功能 H：庫存 +/−（Backlog）

> 本輪不做，先記錄。

庫存調整從「輸入新總數」改成「輸入 +10 / −10」，直接對應 `InventoryChange.change`。

**但盤點情境要保留** —— 使用者盤點知道「實際有 7 個」，帳面 10，用 delta 介面得自己算 −3。

```
[ 調整 ]  [ 盤點 ]        ← 分頁切換

調整模式（預設）        盤點模式
  − 10  [  ]  + 10        目前帳面：10
  原因：進貨入庫 ▾        實際數量：[ 7 ]
                          → 將記錄 −3（盤損調整）
```

「盤點」模式日後可作為 `physicalCount` 絕對值分錄的入口（`SYNC_ARCHITECTURE_V2.md` §11.6）。

---

## 11. 執行順序

### 第 0 批 — Dead code 清除（最快，先做）

| # | 項目 | 解決 |
|---|------|------|
| 0.1 | 刪除 `MoneyHelper.applyDiscount` / `calculateTotal` | D1、D2 |
| 0.2 | `EventsCalendarViewModel:108/114` 改用共用 `DateFormatter` | E3 |

### 第 1 批 — 共用元件（後面全部依賴）

| # | 項目 | 解決 |
|---|------|------|
| 1.1 | `TransactionIndex` + 刪除 5 個 `hasTransaction` 實作 | A1、E1 |
| 1.2 | `EventDataSource` + 移除 `updateDataManagers` 與 `onChange` 補丁 | A2、A3、A5、E2 |
| 1.3 | `ProductAvailability.isAvailableForSale`（6 處改用、加 log） | B6 |
| 1.4 | `DiscountCalculator`（含內建 clamp） | B4、B1 |
| 1.5 | `CSVExporter`（含欄位逸出） | B5 |
| 1.6 | `PendingSyncStamp`（25 處改用，修 4 處漏設） | C1、C4 |
| 1.7 | 刪除守衛改誠實失敗 + 移除 `disabledInstead` | D3、D4 |
| 1.8 | `transactionSummary` 統一到 `EventDataSource`，統一用 `MoneyHelper.add` | A4 |
| 1.9 | **刪除 `updateRelatedTransactions`**（`eventTitle` 停止更新） | A7 |
| 1.10 | **刪除 `Product.categoryName` 欄位**，顯示改從 relationship 查 | A7 |
| 1.11 | 流水帳補 `updatedAt` 欄位 + `InventoryChange → Product` relationship | §14.3 |

### 第 2 批 — 報表

| # | 項目 | 解決 |
|---|------|------|
| 2.1 | `unitPrice` → `averageUnitPrice` | D5 |
| 2.2 | 商品銷售排行：列出所有商品（含銷量 0） | §5.1 |
| 2.3 | 報表三個方法改用 `EventDataSource` 的單一資料 | A5 |

### 第 3 批 — 折扣

| # | 項目 |
|---|------|
| 3.1 | `AppliedDiscount` schema + CoreData `appliedDiscountsData` |
| 3.2 | 折扣 chip UI（兩區各單選、升冪、即時顯示） |
| 3.3 | 場次設定頁的折扣管理調整 |
| 3.4 | 全部改呼叫 `DiscountCalculator` |

### 第 4 批 — 攤提（⭐ 必須在組合之前）

| # | 項目 | 解決 |
|---|------|------|
| 4.1 | `SummaryItemModel` 擴充 5 個欄位 | §7.2 |
| 4.2 | `RevenueAllocator`，結帳時計算 | A6 |
| 4.3 | **刪除** `ProductPerformanceViewModel` 三處攤提與三處 reduce | B1、B2 |
| 4.4 | 驗證兩張報表營收相等 | 測試 R2 |

### 第 5 批 — 組合與套餐（最大塊）

| # | 項目 |
|---|------|
| 5.1 | `BundleModel` + `CDEventEntity.bundlesData` |
| 5.2 | 組合／套餐管理 UI（新分頁、勾選商品、拖曳排序） |
| 5.3 | POS：套餐區塊（`.fixed` 可點選） |
| 5.4 | POS：組合自動套用演算法（`.chooseAny`） |
| 5.5 | 結帳頁顯示套用結果 + 可手動取消 |
| 5.6 | 庫存扣成員 + `InventoryChange.bundleId` |
| 5.7 | `BundleModel.isAvailable` 可用性判斷 |

### 第 6 批 — POS UI

| # | 項目 |
|---|------|
| 6.1 | 類別 chip 列 + 點擊跳躍 + 高亮 |

### Backlog

- 庫存 +/− 與盤點雙模式（§10）
- 組合／套餐績效報表
- 類別 icon
- 商品編輯開放（等本輪統一穩定後再評估）

---

## 12. 測試清單

### 12.1 ⭐ 一致性測試（本輪重點，驗證 24 項查核有真的收斂）

| # | 情境 | 預期 |
|---|------|------|
| **U1** | 商品從 A 類別搬到 B 類別後，問「A 類別有交易嗎」 | **所有呼叫端答案一致**（依快照：A 有、B 沒有） |
| **U2** | U1 之後，A 類別的 swipe 動作與 repository 守衛 | **一致**（都是「只能停用」） |
| **U3** | 在場次編輯頁改類別名稱 → 回到 POS | POS 立刻顯示新名稱（`EventDataSource` 一起重載） |
| **U4** | 在場次編輯頁停用類別 → 回到 POS 與庫存頁 | **兩個畫面都**立刻隱藏該類別商品 |
| **U5** | 場次列表的交易總額 vs 日曆頁的交易總額 | **完全相同**（統一用 `MoneyHelper.add`） |
| **U6** | 切換報表 timeRange | DB 查詢只發生 **1 次**（不是 3 次） |
| **U7** | 全專案搜尋 `syncStatus = "pending"` | **0 筆直接賦值**，全部走 `markPendingSync()` |
| **U8** | 新增交易 / 新增庫存異動後檢查 entity | `syncStatus` 與 `updatedAt`（若有該欄位）**都有被設定** |
| **U9** | 全專案搜尋 `switch discountType` / `switch discount.type` | **只在 `DiscountCalculator` 內出現** |
| **U10** | 全專案搜尋 `temporaryDirectory` | **只在 `CSVExporter` 內出現** |
| **U11** | 全專案搜尋 `func hasTransaction` | **只有 `TransactionIndex` 一份** |
| **U12** | 商品的類別不存在（手動製造異常資料） | **有 log / assertion**，不靜默隱藏 |
| **U13** | 商品名稱含逗號與引號時匯出 CSV | 欄位正確逸出，CSV 可正常開啟 |
| **U14** | 改場次名稱後，查看該場次的舊交易 | 交易顯示的是**當時的場次名稱**（快照不更新） |
| **U15** | 改類別名稱後，檢查該類別下的商品 | 商品**沒有被重新標記為 pending**（無更新風暴）；顯示的類別名稱是新的（從 relationship 查） |
| **U16** | 全專案搜尋 `updateRelatedTransactions` / `product.categoryName` | **0 筆**（已刪除） |
| **U17** | 新增交易 / 庫存異動後檢查 entity | `updatedAt` **有值**（欄位已於第 1.11 批補上） |

### 12.2 刪除與停用

| # | 情境 | 預期 |
|---|------|------|
| D1 | 刪除無交易的商品 | ✅ 真的刪除 |
| D2 | 有交易的商品 | 按鈕顯示為「下架」，無刪除選項 |
| D3 | 下架後再上架 | 可自由來回切換 |
| D4 | 刪除無交易的類別 | ✅ 真的刪除 |
| D5 | 有交易的類別 | 只能停用 |
| D6 | 直接呼叫 `deleteProduct` 傳有交易的商品（單元測試） | 回傳 `.failed`，**不會偷偷變成停用** |
| D7 | 下架商品後建同名商品 | ❌ 被同名檢查擋下 |

### 12.3 編輯限制（維持現況）

| # | 情境 | 預期 |
|---|------|------|
| E1 | 編輯有交易的商品 | 名稱、價格、類別 **disabled 且灰字**，但**看得到目前的值** |
| E2 | 編輯有交易的商品的描述 / 圖片 / 庫存 | ✅ 可改 |
| E3 | 編輯無交易的商品 | 所有欄位可改 |
| E4 | 有交易的類別 | 名稱不可編輯 |

### 12.4 報表

| # | 情境 | 預期 |
|---|------|------|
| R1 | 商品銷售排行 | **所有商品都出現**，沒賣過的顯示銷量 0 |
| **R2** | **Σ 商品實際營收 vs 日營收總和** | **相等**（捨入差額 ≤ 1 分） |
| R3 | 同一商品有多種成交單價（組合優惠造成） | 平均單價 = 原價總額 ÷ 總銷量 |
| R4 | 切換 timeRange 後三張圖表 | 數字互相一致（同一份資料） |
| R5 | 匯出 CSV | 檔名含場次名與時間戳，欄位逸出正確 |

### 12.5 折扣

| # | 情境 | 預期 |
|---|------|------|
| F1 | 只選百分比 | 正確 |
| F2 | 只選定額 | 正確 |
| F3 | 兩個都選 | **先百分比後定額**：200 → 9折 180 → −20 = 160 |
| F4 | 定額折扣 > 小計（例：小計 50、折抵 100） | clamp 成 50，總額 0，**報表不出現負營收** |
| **F5** | **繞過 View 直接呼叫付款流程並傳未 clamp 的折扣**（單元測試） | `DiscountCalculator` 內建 clamp，仍然不會產生負營收 |
| F6 | 取消已選的折扣 | 可再點一次取消 |
| F7 | F3 後修改場次的折扣設定 | 歷史交易的折抵金額**不變**（`amount` 快照） |

### 12.6 組合與套餐

| # | 情境 | 預期 |
|---|------|------|
| B1 | 建立「任選三個100」，勾 10 個候選商品 | 設定成功 |
| B2 | 購物車加 7 個候選商品 | 自動套用 2 組（挑單價最高的 6 個），剩 1 個原價 |
| B3 | B2 的結帳頁 | 顯示「任選三個100 × 2 組，折抵 NT$XX」，可手動取消 |
| B4 | 建立套餐並在 POS 點選 | 購物車出現「套餐 × 1」 |
| B5 | 賣出套餐 | 產生 N 筆 `InventoryChange`（每成員一筆），各帶 `bundleId` |
| B6 | B5 後看商品績效 | 成員商品各自計入，金額為攤提後的 `actualRevenue` |
| B7 | 下架套餐成員之一 | 提示「有 N 個組合包含此商品」；POS 該組合灰掉標示「含已下架商品」 |
| B8 | B7 後把商品上架回來 | 組合**自動恢復**可販售（不需手動處理） |
| B9 | 兩個組合優惠都符合 | 依 `sortOrder` 貪婪套用，結果可預測 |
| B10 | 套餐 + 整筆折扣同時 | 攤提順序正確：套餐差額 → 百分比 → 定額 |
| B11 | 套餐 + 組合優惠同時在購物車 | 不重複套用（同一件商品只被算進一個組合） |

### 12.7 POS 與效能

| # | 情境 | 預期 |
|---|------|------|
| P1 | 點擊類別 chip | 跳到該類別，chip 高亮 |
| P2 | 捲動商品列表 | chip 跟著高亮，chip 列自動捲動 |
| P3 | 停用類別 | 該類別與其商品在 POS 消失 |
| **P4** | **50 個商品 + 500 筆交易的庫存管理頁捲動** | 流暢（`TransactionIndex` 生效，25,000 次 decode → 500 次） |
| P5 | 進入報表頁 | 只查一次 DB（`EventDataSource`） |

### 12.8 回歸（確認重構沒有改壞既有行為）

| # | 情境 | 預期 |
|---|------|------|
| G1 | 現金結帳完整流程 | 交易、庫存異動、報表數字都正確 |
| G2 | 電子支付結帳完整流程 | 同上 |
| G3 | 補記帳（`occurredAt`） | 交易日期正確，報表歸屬正確的日期 |
| G4 | 複製場次 | 商品、類別、初始庫存分錄都正確複製 |
| G5 | 場次編輯：新增/刪除/停用類別 + 改名 | 所有連動正確，無孤兒資料 |
| G6 | 所有 CSV 匯出（8 種） | 內容與檔名正確 |

---

## 13. 待確認事項

| # | 項目 | 狀態 |
|---|------|------|
| 1 | 「任選三個 100」的候選是「勾選商品」還是「整個類別」 | 暫定**勾選商品**。若要支援類別，`BundleModel` 加 `categoryIds` |
| 2 | 折扣 chip 要不要內建幾組預設值 | 待定 |
| 3 | `.fixed` 套餐第一版每成員固定 1 個 | 若需要 A×2，`productIds` 換成 `items: [BundleItem]` |
| 4 | 組合／套餐要不要有圖片 | 暫定**不要**（省一套圖片同步） |
| 5 | 商品銷售排行是否保留「原價總額 / 折扣金額」兩欄 | 暫定收進展開區 |
| 6 | 類別 icon | 本輪不做 |
| 7 | `EventDataSource` 的持有層級（View 建立還是注入 environment） | 實作時決定；建議在場次工作區建立一份，往下傳 |

---

## 附錄：查核對照表（24 項 → 解決方案）

| 編號 | 問題 | 解決方案 | 批次 |
|------|------|----------|------|
| A1 | 5 個 `hasTransaction`，類別判斷相反 | `TransactionIndex` | 1.1 |
| A2 | event 新鮮度兩套機制 | `EventDataSource` | 1.2 |
| A3 | 商品新鮮、類別快照 | `EventDataSource` | 1.2 |
| A4 | `transactionSummary` 重複且加法不同 | `EventDataSource` + 統一 `MoneyHelper` | 1.8 |
| A5 | 報表三次重複 fetch | `EventDataSource` | 1.2 / 2.3 |
| A6 | 兩張報表營收口徑不同 | `RevenueAllocator` | 4.2 |
| A7 | `eventTitle` 更新不同步 / `categoryName` 更新風暴 | 刪 `updateRelatedTransactions` + 刪 `categoryName` 欄位 | 1.9 / 1.10 |
| B1 | 折扣計算重複 3 次 | `DiscountCalculator` + `RevenueAllocator` | 1.4 / 4.3 |
| B2 | subtotal reduce 重複 3 次 | `RevenueAllocator` | 4.3 |
| B3 | 交易 fetch 樣板重複 4 次 | `EventDataSource` | 1.2 |
| B4 | 折扣 switch 散落 7 處 | `DiscountCalculator` | 1.4 |
| B5 | CSV 建檔樣板重複 9 次 | `CSVExporter` | 1.5 |
| B6 | 可販售判斷散落 6 處 | `ProductAvailability` | 1.3 |
| C1 | 4 處漏設 `updatedAt` | `PendingSyncStamp` | 1.6 |
| C2 | 流水帳 entity 無 `updatedAt` | 見 `SYNC_ARCHITECTURE_V2.md` | 同步文件 |
| C3 | 流水帳 Firestore 無 `updatedAt` | 同上 | 同步文件 |
| C4 | 25 處各自寫入標記 | `PendingSyncStamp` | 1.6 |
| D1 | `MoneyHelper.applyDiscount` 無人用 | 刪除 | 0.1 |
| D2 | `MoneyHelper.calculateTotal` 無人用 | 刪除 | 0.1 |
| D3 | 商品自動停用不可達 | 改誠實失敗 | 1.7 |
| D4 | 類別自動停用不可達 | 改誠實失敗 | 1.7 |
| D5 | `unitPrice` 假設同單價 | `averageUnitPrice` | 2.1 |
| E1 | `hasTransaction` O(N×M) | `TransactionIndex` | 1.1 |
| E2 | 報表三次重複查詢 | `EventDataSource` | 1.2 |
| E3 | 重複建立 `DateFormatter` | 用共用 extension | 0.2 |

---

## 14. ⭐ 待接同步清單（重構 Firebase 前必讀）

> **本輪功能開發【不處理 Firebase 同步】** —— 同步層之後會依
> `SYNC_ARCHITECTURE_V2.md` 全部重寫，現在寫等於白工。
>
> **但每一次新增/修改資料結構，都必須在下表登記一列。**
> 重構同步時，這張表就是「哪些東西還沒接上雲端」的完整清單。

### 14.1 開發期間的規則

| 規則 | 說明 |
|------|------|
| **新欄位暫時不寫進 `toFirestoreData`** | 編譯正常、不 crash、舊功能的同步照常運作（還能驗證重構沒改壞） |
| **在對應位置標記 TODO** | 格式固定：`// TODO: [SYNC-PENDING] 說明`，重構時可 `grep -rn "SYNC-PENDING"` 一次撈出 |
| **在 §14.2 登記一列** | 清單與 code 標記**雙保險** —— 清單漏記時還有 grep 可以補 |
| **不要為了「先讓它同步」而改舊的同步層** | 那些程式碼會被整段刪除 |

```swift
// 範例
extension EventModel {
    func toFirestoreData(userId: String) -> [String: Any] {
        var data: [String: Any] = [...]
        // TODO: [SYNC-PENDING] bundles 尚未加入，見 FEATURE_PLAN_V1.md §14.2
        return data
    }
}
```

### 14.2 登記表

> 每完成一個 schema 變更就補一列。`分類`欄對應 `SYNC_ARCHITECTURE_V2.md` §3 的三分類。

| # | 日期 | 功能 | 新增/修改的資料 | 儲存位置 | 分類 | 同步時要做什麼 | 狀態 |
|---|------|------|----------------|----------|------|---------------|------|
| 0 | — | **見 §14.3：以下 4 項的 CoreData 部分在功能開發期就先做掉** | | | | | |
| 1 | 待填 | D 多重折扣（§6） | `AppliedDiscount` 結構<br>`TransactionModel.appliedDiscounts` | `CDTransactionEntity.appliedDiscountsData: Binary` | 流水帳 | `TransactionModel.toFirestoreData` 加 `appliedDiscounts`（JSON 陣列）<br>移除舊的 `discountType` / `discountValue` | ⬜ 未接 |
| 2 | 待填 | E 攤提（§7） | `SummaryItemModel` 加 5 欄：<br>`originalSubtotal`、`allocatedDiscount`、`actualRevenue`、`bundleId`、`bundleName` | 在 `CDTransactionEntity.itemsData` 內（跟著走） | 流水帳 | `SummaryItemModel.toFirestoreData` 加這 5 欄 | ⬜ 未接 |
| 3 | 待填 | F 組合套餐（§8） | `BundleModel`、`BundleMode` | `CDEventEntity.bundlesData: Binary` | 文件（跟 Event 走） | `EventModel.toFirestoreData` 加 `bundles`（JSON 陣列）<br>**不需要新 collection** | ⬜ 未接 |
| 4 | 待填 | F 組合套餐（§8.5） | `InventoryChangeModel.bundleId`<br>`InventoryChangeModel.bundleName` | `CDInventoryChangeEntity` 新欄位 | 流水帳 | `InventoryChangeModel.toFirestoreData` 加這 2 欄 | ⬜ 未接 |
| 5 | 待填 | 同步架構補正 | `updatedAt` | `CDTransactionEntity`<br>`CDInventoryChangeEntity` | 流水帳 | **CoreData 欄位已於第 1.11 批加好**（本機時間）。同步時只需在 `toFirestoreData` 改寫為 `serverTimestamp()`。見 `SYNC_ARCHITECTURE_V2.md` §6.2 | 🟡 已提前 |
| 6 | | | | | | | |

**狀態圖例**：⬜ 未接　🔄 重構中　✅ 已接上並測試

### 14.3 ⭐ 提前處理：功能開發期就先做掉的 schema 變更

> 判斷標準：**「純 CoreData / 純本機行為」的先做，「需要 Firestore 配合」的才延後。**
> 提前做的東西之後不用回頭改建立點，也不會被功能期的新程式碼繞過。

#### 現在就做（併入執行順序第 1 批）

| # | 項目 | 為什麼現在做 | 成本 |
|---|------|-------------|------|
| 1 | `CDTransactionEntity` / `CDInventoryChangeEntity` **加 `updatedAt: Date?`** | `PendingSyncStamp`（§2.7）會自動偵測並設定。之後才加，要回頭改所有建立點（`EventRepository:394`、`InventoryChangeRepository:29/49`…） | 極低（2 個 attribute） |
| 2 | `CDInventoryChangeEntity` **補 `product` relationship + inverse** | 現在就用得到（刪商品時要找它的異動紀錄）；而且有 `event` 卻沒有 `product` 是模型缺陷 | 低 |
| 3 | **刪除 `Product.categoryName`**（A7） | 純本機的冗餘欄位。留著的話功能期的新程式碼會繼續依賴它，之後移除更痛 | 中 |
| 4 | **刪除 `updateRelatedTransactions`**（A7） | 它現在就在製造「本機與雲端不一致」。`eventTitle` 是歷史快照，本來就不該更新 | 極低（刪呼叫 + 刪函式） |

#### 延後到同步重構

| 項目 | 為什麼延後 |
|------|-----------|
| `deletedAt` 欄位 + tombstone 行為 | 刪除行為的改變跟同步強耦合，本機單獨做沒有意義 |
| `CDOutboxOperation` | 純同步基礎設施 |
| `syncStatus = "local"` | 只在訂閱狀態下有意義 |
| `updatedAt` 改成 `serverTimestamp()` | Firestore 端的事，CoreData 先用本機時間即可 |
| §14.2 第 1–4 列的 `toFirestoreData` | 本來就是登記表要追蹤的 |

#### 一個介面形狀的約定（低成本、之後省很多）

報表需要看得到已刪除的商品，日常畫面則不需要。**現在就把 Repository 的 API 分成兩組**，即使目前兩者行為相同：

```swift
func fetchProducts(forEventId:) -> [ProductModel]              // 日常（之後內部加 deletedAt == nil）
func fetchProductsIncludingDeleted(ids:) -> [ProductModel]     // 報表 join（之後不加過濾）
```

這樣加 tombstone 時只要改 repository 內部，**不用回頭找 20 個呼叫點**。

### 14.4 重構同步時的檢查步驟

```
① grep -rn "SYNC-PENDING" Tilli/          ← 撈出所有 code 標記
② 逐一對照 §14.2 登記表                    ← 確認沒有漏記的
③ 依 SYNC_ARCHITECTURE_V2.md §3 的三分類，決定每一項的合併策略
④ 逐項改成 ✅，並補上對應的測試
⑤ 全部完成後，grep 應回傳 0 筆
```

### 14.5 已知不需要同步的東西

登記表只放「需要上雲端」的。以下刻意**不同步**，列在這裡避免重構時誤加：

| 項目 | 為什麼不同步 |
|------|-------------|
| `CDProductEntity.stock` | 推導值，由 ledger 算出（`SYNC_ARCHITECTURE_V2.md` §11） |
| `layoutMode`（POS 版型） | 裝置偏好，存 UserDefaults |
| `TransactionIndex` | 執行期索引，不落地 |
| `EventDataSource` 的快取 | 執行期狀態 |
| 報表的所有計算結果 | 推導值 |

---

## 版本記錄

| 日期 | 變更 |
|------|------|
| 2026-09-11 | 初版 |
| 2026-09-12 | 新增查核項 A7（`eventTitle` 更新不同步 / `categoryName` 更新風暴）；新增 §14.3 提前處理清單（4 項 schema 變更移到功能開發期）；執行順序補 1.9–1.11；測試補 U14–U17 |
| 2026-09-12 | 新增 §14 待接同步清單（開發期間的 SYNC-PENDING 標記規則 + 登記表）|
| 2026-09-12 | 擴大為全專案流程統一：完整查核 24 項、新增 7 個共用元件、新增一致性測試（U1–U13）與回歸測試（G1–G6）；編輯限制改為維持現況；新增查核對照表 |

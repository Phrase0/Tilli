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

1. [完整查核結果（28 項）](#1-完整查核結果28-項)
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

## 1. 完整查核結果（28 項）

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

##### ⚠️ A1 的可達性（2026-09-13 複查，修正原本的敘述）

上面這個例子**在目前的 UI 上做不到** —— 有交易的商品**不能改類別**，而且是雙重保險：

| 擋在哪 | 位置 |
|--------|------|
| 類別 Picker `.disabled(isEditingWithTransaction)` | `AddNewProductView:170` |
| 組 `ProductModel` 時強制沿用 `editing.categoryId` | `AddNewProductViewModel:352` |
| 唯一還能改 `categoryId` 的 `batchUpdateProducts` | **沒有任何呼叫端**（dead code） |

其餘可能造成兩種判斷分歧的路徑也都不成立：
商品下架不改 `categoryId`、賣過的商品不能刪、複製場次產生的是新 UUID（沒交易）、
刪場次是整個一起走。**目前沒有可達的分歧情境。**

所以 `TransactionIndex`（§2.1）的價值要誠實列為：

| 理由 | 成立？ |
|------|--------|
| **E1 效能** —— 25,000 次 JSON decode → 500 次 | ✅ 可實測 |
| **5 份實作收斂成 1 份** —— 維護成本 | ✅ |
| **為 Backlog「開放商品編輯」預先收斂** —— §4.1 的理由正是「A1 尚未收斂前風險大於效益」，現在前提達成了 | ✅ |
| 「修掉使用者現在會遇到的不一致」 | ❌ **不成立**，目前遇不到 |

**這不改變第 1 批的任何程式碼**，只是把測試從「手動操作」改成「單元測試」守住
（見 §11 第 1 批的測試區）。

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

### 1.7 🟠 本地化三條通道不一致（4 項，2026-09-12 新增）

> **修法取決於一個尚未決定的產品問題：App 內的語言切換要留還是拿掉？**
> 見 §13 待確認事項第 8 項。程式碼本輪不動，先登記。

App 目前有**三條**本地化通道，日期掛在沒接上的那一條：

| # | 通道 | 影響範圍 | 跟隨 App 語言？ |
|---|------|---------|----------------|
| 1 | `.environment(\.locale, Locale(identifier: selectedLanguage))`<br>`TilliApp:38` | SwiftUI `Text(LocalizedStringKey)`、`.formatted()`、Charts 軸標籤 | ✅ |
| 2 | `Bundle.appLocalized` + `String.localized(_:)`<br>`Bundle+AppLocalized.swift` | ViewModel 產出的字串（204 處呼叫） | ✅ |
| 3 | **`DateFormatter` / `Calendar.current` 的 symbols** | 所有日期字串、日曆星期列（37 處） | ❌ **吃 `Locale.current`（系統語言）** |

`.environment(\.locale,)` 只影響 SwiftUI view tree，**改不到 `Locale.current`** —— 那是 process 層級、由系統語言決定的值。

| # | 問題 | 位置 | 後果 |
|---|------|------|------|
| **F1** | **日期格式不跟隨 App 語言** —— `Extensions/DateFormatter.swift` 的 8 個 formatter 都沒設 `.locale` | `EventModel:29-34`、`EventsCalendarViewModel:104/108/112`、`TransactionHistoryViewModel:372`、`SalesAnalyticsViewModel:21/25` | 切成英文後，UI 文字變英文但日期仍是中文格式 |
| **F2** | **`Locale(identifier: "zh-Hant")` 沒有 region** —— 純語言碼把使用者地區資訊抹掉 | `TilliApp:38` | `region=nil`、`currency=nil`，SwiftUI 原生幣別格式變成 `XXX 1,234.50` |
| **F3** | **首次啟動強制中文** —— 沒有任何地方從系統語言初始化 `selectedLanguage` | `@AppStorage("selectedLanguage") = "zh-Hant"`（7 處） | 英文手機第一次開 App 得到中文 UI，要自己去「我的」改 |
| **F4** | **同一畫面兩套語言** —— Charts 軸走通道 1、日期標籤走通道 3 | `SalesAnalyticsView:641` vs `SalesAnalyticsViewModel:21/25` | 切英文時同一張圖上中英並存 |

#### F1 的實測範圍

只有「帶語言的 template formatter」有可見症狀；固定數字 pattern 的輸出兩種語言相同：

```
                   zh-Hant              en
dateWithWeekday    2026年01月04日 星期日   Sunday, 01/04/2026    ← ❌ 有差
yearMonth          2026年1月             January 2026          ← ❌ 有差
monthDayWeekday    1月4日 週日            Sun, Jan 4            ← ❌ 有差
veryShortWeekday   [日 一 二 三 四 五 六]   [S M T W T F S]        ← ❌ 有差
standardDate       2026/01/04           2026/01/04            ← 無差
dateTime           2026/01/04 16:00     2026/01/04 16:00      ← HH:mm 24 小時制，無差
shortDate / isoDate / fileTimestamp                           ← 無差
```

固定 pattern 那幾個目前沒有可見症狀，但仍有隱性風險：`Locale.current` 會帶系統的曆法偏好，
系統若設成日本和曆／佛曆，`yyyy` 會印出非西元年。設定 locale 可以一併釘死 Gregorian。

#### F2 的實測

```
zh-Hant      region=nil  currency=nil   幣別格式=「XXX 1,234.50」
en           region=nil  currency=nil   幣別格式=「¤1,234.50」
zh-Hant_TW   region=TW   currency=TWD   幣別格式=「$1,234.50」   ← 系統原本給的
```

**目前沒爆，是因為錢都走 `MoneyHelper.format`**（自己建 `NumberFormatter`，吃 `Locale.current`，不吃 environment）。
但任何人在 View 裡寫一個 `Text(amount, format: .currency(code:))` 就會拿到 `XXX 1,234.50`。

#### 兩條修法（等產品決定後選一條，不要兩條都做）

**路線 A：拿掉語言切換，全部跟系統（程式碼淨減）**

`Locale.current` 就是正解 → **`Extensions/DateFormatter.swift` 現在的寫法已經是對的，一行都不用改**。
F1～F4 全部自動消失。要做的是刪：

| 動作 | 位置 |
|------|------|
| 刪語言 Picker | `MyView:242`（`_Deprecated/ProfileView:263` 一起） |
| 刪 `.environment(\.locale, ...)` | `TilliApp:38` → 自動回到系統 locale（解 F2） |
| 刪 7 處 `@AppStorage("selectedLanguage")` | `TilliApp:21`、`RootTabView:12`、`EventsView:22`、`MyView:14`、`_Deprecated` |
| `Bundle.appLocalized` 刪除，`String.localized` 退化成不指定 bundle 的薄殼 | 204 處呼叫端**零改動** |

順帶效益：`RootTabView:12` 與 `EventsView:22` 那兩個「宣告了卻沒在 body 用」的強制重繪觸發器一起消失
—— 那正是 `CONVENTIONS.md`「資料同步規範」明文禁止的強制刷新 hack。

**路線 B：保留語言切換（要新增抽象）**

新增 `AppLocale`（單一真相，讀同一個 `selectedLanguage` key），8 個 formatter 從 `static let` 改成
`static var` + 依 locale 快取（`NSLock` 保護 dictionary，因為 `EventModel.displayDate` 是 model 層
computed property，不保證只在主執行緒呼叫）。呼叫端 37 處寫法不變。
**但 F2、F3 仍須各自另外修**，而且三條通道會永久共存。

⚠️ **兩條路線互斥。** 路線 A 成立時 `AppLocale` 是確定要刪的鷹架，所以產品決定之前不要先建。

---

## 2. 共用元件設計

上面 24 項用 **7 個共用元件**一次收斂（§1.7 的 4 項本地化問題不在其中，修法見該節）。

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

> **2026-09-13 更新：A1 已於第 1 批收斂**（單一 `TransactionIndex`，一律用 `SummaryItem.categoryId` 快照）。
> 上述「風險大於效益」的**前提條件已經達成**，要不要開放「有交易的商品改類別」
> 變成純產品決定。開放前請先讓 §11 第 1 批列的 `TransactionIndex` 單元測試到位 ——
> 那組測試就是為了這一天寫的。

### 4.1.1 ⚠️ 場次名稱目前【沒有】編輯限制

實際盤點（2026-09-13）：

| 對象 | 有交易時 | 位置 |
|------|---------|------|
| **場次名稱** | ✅ **可以改**（沒有任何 `.disabled`） | `AddEventView:42-49` |
| 場次幣別 | ❌ 鎖定 | `AddEventView:163` |
| 類別名稱 | ❌ 鎖定（該類別有交易時） | `AddEventView:383`／`canEditCategoryName` |
| 商品名稱 | ❌ 鎖定 | `AddNewProductView:51` |
| 商品價格 | ❌ 鎖定 | `AddNewProductView:88` |
| 商品類別 | ❌ 鎖定 | `AddNewProductView:170` ＋ `AddNewProductViewModel:352` |

場次名稱是這張表裡唯一沒鎖的。**暫定維持可改**，理由：
場次名不影響任何金額或歸屬，而且第 1.9 批之後歷史交易顯示的是當時的名稱快照，
改名不會污染歷史。若要改成一致（鎖起來），見 §13 待確認第 9 項。

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
| 範圍 | 只有賣過的商品（從交易反推）**且只有前 5 名** | 排行列**所有賣過的**（移除 `prefix(5)`）；沒賣過的收進**「本期未售出」摺疊區**（實作時的調整，見 §11 第 2 批） |
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

> **每批下方都有該批專屬的「測試」區**，拆成三塊：
> **自動—指令驗證**（grep／build，貼進終端機就能跑）、
> **自動—單元測試**（純函式，`TilliTests` 目標）、
> **手動**（要開 App 操作，附完整步驟與預期）。
>
> 與 §12 的關係：§12 是**跨批的總清單**（U／D／E／R／F／B／P／G 編號），
> 用來確認 28 項查核有沒有真的收斂；這裡是**逐批逐改動**的驗收，
> 每個改動都對得到至少一條。兩邊重疊的項目會標出 §12 的編號，
> 例如「（U1／U2）」，避免兩份清單各自漂移。
>
> 圖例：`✅` 已驗證通過　`⬜` 待補　`⚠️` 已知限制

### 第 0 批 — Dead code 清除（最快，先做）✅ 2026-09-12 完成

| # | 項目 | 解決 | 狀態 |
|---|------|------|------|
| 0.1 | 刪除 `MoneyHelper.applyDiscount` / `calculateTotal` | D1、D2 | ✅ |
| 0.2 | `EventsCalendarViewModel:108/114` 改用共用 `DateFormatter` | E3 | ✅ |

0.2 的共用 formatter：`monthYearString()` → 既有的 `DateFormatter.yearMonth`；
`selectedDateString()` 的 `MMMdEEE` 模板原本沒有對應 static，已在 `Extensions/DateFormatter.swift`
新增 `monthDayWeekday`（共 8 個 static）。已驗證 zh-Hant-TW／en-US／ja-JP 三個 locale 輸出與原本完全一致。

#### 測試

> 圖例：`✅` 已驗證通過　`⬜` 待補（需要新增測試檔）　`⚠️` 已知限制，本批不修

##### 自動 —— 指令驗證（不需開 App）

- ✅ **0.1 dead code 真的消失**
  `grep -rn "applyDiscount\|calculateTotal" --include="*.swift" Tilli` → **0 筆**
- ✅ **0.1 沒有誤刪其他 MoneyHelper API**
  `add` / `subtract` / `multiply` / `divide` / `round` / `format` / `average` / `sum` / `toDisplayString` / `toEditableString` 都還在，且 `Decimal.money` extension 未動
- ✅ **0.2 全專案沒有行內建立的 DateFormatter**
  `grep -rn "DateFormatter()" --include="*.swift" Tilli | grep -v "Extensions/DateFormatter.swift"` → **0 筆**
- ✅ **0.2 formatter 輸出等價性**（確認換成共用 static 後字串完全一樣）
  用 `swift` 腳本比對三個 locale 的輸出：
  - `zh-Hant`：`yearMonth` = `2026年1月`、`monthDayWeekday` = `1月4日 週日`
  - `en`：`January 2026`、`Sun, Jan 4`
  - `ja`：`2026年1月`、`1月4日(日)`
  - 三者皆與原本的 `setLocalizedDateFormatFromTemplate("yMMMM")` / `("MMMdEEE")` 逐字相同
- ✅ **0.2 `yearMonth` 的既有使用者沒被破壞**
  `_Deprecated/CalendarViewModel.swift` 仍在編譯目標內且有用到 `DateFormatter.yearMonth`
- ✅ **建置** `xcodebuild build` → `BUILD SUCCEEDED`

##### 自動 —— 單元測試

- 本批是「刪除 dead code + 換成共用 formatter」，沒有新的商業邏輯，
  等價性已由上面的 locale 腳本涵蓋，**不需要新增單元測試**。

##### 手動 —— 需操作 App

- **日曆頁月份標題**（`monthYearString`）
  1. 場次 tab → 切到日曆檢視
  2. 確認標題顯示為「2026年9月」這類格式（不是 `2026 September` 或亂碼）
  3. 左右切換月份數次，含**跨年**（12 月 → 1 月、1 月 → 12 月）
  - 預期：每次切換標題都正確更新，年份跟著跨年變動
- **日曆頁選中日期**（`selectedDateString`）
  1. 點選日曆上任一天
  2. 確認顯示為「9月13日 週日」這類格式，**星期要正確**
  3. 特別點選月初 1 號、月底最後一天、以及**閏年 2/29**（2028 年）
  - 預期：日期與星期都正確，無「週7」之類的異常
- **回歸：其他用到日期的畫面沒被影響**
  - 場次卡片的日期區間（`EventModel.displayDate`，用 `dateWithWeekday` / `standardDate`）
  - 庫存異動紀錄的時間（`dateTime`）
  - 交易紀錄的日期分組標題（`dateWithWeekday`）
  - 報表 CSV 檔名的時間戳（`fileTimestamp`）
  - 預期：全部與改動前相同
- ⚠️ **已知限制（本批不修）**：在「我的」頁切換 App 語言後，上述日期**不會**跟著變成英文。
  這是 §1.7 的 F1，三條本地化通道的問題，修法取決於 §13 待確認第 8 項的產品決定。
  測試時**不要**把這個當成第 0 批的 bug。

### 第 1 批 — 共用元件（後面全部依賴）✅ 2026-09-12 完成

| # | 項目 | 解決 | 狀態 |
|---|------|------|------|
| 1.1 | `TransactionIndex` + 刪除 5 個 `hasTransaction` 實作 | A1、E1 | ✅ |
| 1.2 | `EventDataSource` + 移除 `updateDataManagers` 與 `onChange` 補丁 | A2、A3、A5、E2 | ✅ |
| 1.3 | `ProductAvailability.isAvailableForSale`（6 處改用、加 log） | B6 | ✅ |
| 1.4 | `DiscountCalculator`（含內建 clamp） | B4、B1 | ✅ |
| 1.5 | `CSVExporter`（含欄位逸出） | B5 | ✅ |
| 1.6 | `PendingSyncStamp`（25 處改用，修 4 處漏設） | C1、C4 | ✅ |
| 1.7 | 刪除守衛改誠實失敗 + 移除 `disabledInstead` | D3、D4 | ✅ |
| 1.8 | `transactionSummary` 統一，統一用 `MoneyHelper.add` | A4 | ✅ |
| 1.9 | **刪除 `updateRelatedTransactions`**（`eventTitle` 停止更新） | A7 | ✅ |
| 1.10 | **刪除 `Product.categoryName` 欄位**，顯示改從 relationship 查 | A7 | ✅ |
| 1.11 | 流水帳補 `updatedAt` 欄位 + `InventoryChange → Product` relationship | §14.3 | ✅ |

#### 實作與計畫的差異（都是刻意的）

| # | 計畫寫的 | 實際做的 | 為什麼 |
|---|---------|---------|-------|
| 1.3 | 「6 處判斷全部改用 `isAvailableForSale`」 | 那 7 個點其實是**兩種語意**：只有 `POSViewModel.activeProducts` 是「商品可不可賣」（兩層）；其餘 5 處是「啟用中的類別」（一層）。前者改用 `isAvailableForSale`，後者收斂成 `[CategoryModel].active`；`InventoryViewModel` 依 `product.isDisabled` 分「銷售中／已下架」兩區**保持原樣** | 管理頁本來就要看得到下架商品，套用「可販售」會讓下架區消失 |
| 1.4 | `DiscountCalculator` 吃 `[AppliedDiscount]` | 核心 API 是陣列版（`amount(for:subtotal:)`／`total(subtotal:discounts:)`，先百分比後定額），另加現行單一折扣的便利版 | `AppliedDiscount` 是第 3 批才有的 schema；陣列版先就位，第 3 批換型別即可 |
| 1.4 | clamp 內建在計算器 | 另外把 clamp **下移到寫入邊界**（兩個付款 VM 與 `TestDataGenerator`），不再依賴 `POSView:59` 記得呼叫 `effectiveDiscount()` | 原本換個入口就會把超過小計的折扣存進流水帳 → 報表攤提出現負營收 |
| 1.7 | 類別守衛改誠實失敗 | 有交易的類別改成**原封不動留著**（不刪、也不偷偷停用）+ log | 它在 `updateCategoriesForEvent` 的批次儲存裡，無法單獨回傳失敗；「沒被刪掉」本身就是誠實回饋 |
| 1.8 | 統一到 `EventDataSource` | 實作放在 `[TransactionModel].summary / .total`，`EventDataSource` 也用它 | 兩個重複點（`EventsViewModel`／`EventsCalendarViewModel`）在場次列表，不在工作區內，拿不到 `EventDataSource` |
| — | — | 順帶刪除結帳鏈的 `@Binding var event`（7 個 View）與 `performCheckout` 的回傳值 | 那條寫回鏈是**死的**：`performCheckout` 只 `return event`（自己未修改的副本），寫回 `POSView` 的區域 `@State`，而 `POSViewModel` 拿的是 `.constant(event)`。正是 CONVENTIONS 禁止的跨頁 `@Binding` |
| — | — | 場次被刪除的偵測從 `InventoryView.onChange(of: eventDataManager.events)` 移到工作區容器 | 「場次還在不在」是容器層的事，不該由其中一個分頁負責；也移除了一個 CONVENTIONS 禁止的 `onChange` 觸發器 |
| — | — | `TilliTests` 的 `WorkspaceView` → `EventWorkspaceView`、`ProductModel.mock` 移除 `categoryName` | 前者在本批之前就已經編譯失敗（上次改名時漏改），測試目標整個跑不起來 |

#### 測試

> 圖例：`✅` 已驗證通過　`⬜` 待補（需要新增測試檔，目前 `TilliTests` 只有 3 個 smoke test）

##### 自動 —— 指令驗證（不需開 App，可直接貼進終端機）

```bash
# 1.1 TransactionIndex：全專案只有一份「有沒有賣過」的實作
grep -rn "soldProductIds\|soldCategoryIds" --include="*.swift" Tilli      # 應只出現在 TransactionIndex.swift
grep -rn "hasRelatedTransactions" --include="*.swift" Tilli               # 應 0 筆

# 1.2 EventDataSource：死的跨頁 Binding 已清除
grep -rn "@Binding var event" --include="*.swift" Tilli | grep -v _Deprecated   # 應 0 筆
grep -rn "\.constant(event)" --include="*.swift" Tilli | grep -v _Deprecated    # 應 0 筆

# 1.3 ProductAvailability：不再有「找不到類別就靜默隱藏」的寫法
grep -rn "isDisabled == false" --include="*.swift" Tilli \
  | grep -v ProductAvailability.swift                                      # 應 0 筆
  # 註：ProductAvailability.swift 的註解引用了這個舊寫法當反例，所以排除自身

# 1.4 DiscountCalculator（U9）
grep -rnE "switch (discountType|discount\.type)" --include="*.swift" Tilli \
  | grep -v DiscountCalculator.swift                                       # 應 0 筆

# 1.5 CSVExporter（U10）
grep -rn "temporaryDirectory" --include="*.swift" Tilli | grep -v CSVExporter.swift   # 應 0 筆
grep -rn 'with: "，"' --include="*.swift" Tilli | grep -v CSVExporter.swift           # 應 0 筆（假逸出）
grep -rc "CSVExporter.write" --include="*.swift" -r Tilli | grep -v ":0"              # 合計應 9 處

# 1.6 PendingSyncStamp（U7）
grep -rn 'syncStatus = "pending"' --include="*.swift" Tilli \
  | grep -v PendingSyncStamp.swift                                         # 應 0 筆
grep -rn "markPendingSync(" --include="*.swift" Tilli \
  | grep -v PendingSyncStamp.swift | wc -l                                 # 應 22（25 改用 − 3 隨守衛/風暴刪除）

# 1.7 刪除守衛
grep -rn "disabledInstead" --include="*.swift" Tilli                       # 應 0 筆

# 1.8 交易加總只有一種算法
grep -rn 'reduce(.*) { \$0 + \$1.totalAmount }' --include="*.swift" Tilli   # 應 0 筆（原生 + 已清除）

# 1.9 / 1.10（U16）
grep -rn "updateRelatedTransactions\|product\.categoryName" --include="*.swift" Tilli  # 應 0 筆
grep -c "categoryName" Tilli/Data/CoreData/Tilli.xcdatamodeld/Tilli.xcdatamodel/contents  # 應 0

# 1.11 schema
grep -c "updatedAt" Tilli/Data/CoreData/Tilli.xcdatamodeld/Tilli.xcdatamodel/contents     # 應 7（原 5 + 流水帳 2）
grep -o 'name="product"[^/]*'      Tilli/Data/CoreData/Tilli.xcdatamodeld/Tilli.xcdatamodel/contents
grep -o 'name="inventoryChanges"[^/]*' Tilli/Data/CoreData/Tilli.xcdatamodeld/Tilli.xcdatamodel/contents

# 建置與測試
xcodebuild -project Tilli.xcodeproj -scheme Tilli -destination 'generic/platform=iOS Simulator' build
xcodebuild test -project Tilli.xcodeproj -scheme Tilli -destination 'platform=iOS Simulator,name=iPhone 17'
```

- ✅ 以上 grep 全部符合預期
- ✅ `BUILD SUCCEEDED`
- ✅ `Executed 3 tests, with 0 failures`（`TilliSmokeTests` 已一併修復，本批之前它是編譯失敗的）

##### 自動 —— 單元測試 ✅ 2026-09-13 補齊（75 個，全數通過）

```
TilliTests/
├── TransactionIndexTests.swift        8 tests   1.1
├── DiscountCalculatorTests.swift     24 tests   1.4
├── CSVExporterTests.swift            10 tests   1.5
├── MoneyAggregationTests.swift        8 tests   1.8
├── ProductAvailabilityTests.swift    10 tests   1.3
├── PendingSyncStampTests.swift        7 tests   1.6 / 1.11
├── ProductDeletionGuardTests.swift    5 tests   1.7
└── TilliSmokeTests.swift              3 tests   （既有）
                                      ──────────
                                      75 tests   0 failures
```

**補測試時抓到的兩個真實缺陷**（都已修）：

| # | 缺陷 | 位置 | 症狀 |
|---|------|------|------|
| 1 | `total(subtotal:discounts:)` **沒有 clamp 定額折扣的負值** | `DiscountCalculator.swift` | 折扣值為負時**反而加錢** —— `total(200, [.amount(-50)])` 回 `250`。clamp 只做在 `amount(type:value:subtotal:)`，陣列版漏了。已改成每筆都 clamp 到 `0...running` |
| 2 | 每個 `NSPersistentContainer` 各自解析一份 `NSManagedObjectModel` | `Persistence.swift` | 測試另建 in-memory container 後，`+[CDxxxEntity entity]` 報 `Failed to find a unique match for an NSEntityDescription`，entity 取不到。已改成整個 process 共用一份（順帶省掉重複解析） |

覆蓋內容：

- ✅ **`TransactionIndex`**（1.1）
  - 空交易 → `hasAnyTransaction == false`、`transactionCount == 0`、任何查詢都是 `false`
  - 單筆交易含商品 A（類別甲）→ `hasTransaction(productId: A) == true`、`hasTransaction(categoryId: 甲) == true`
  - **A 之後被搬到類別乙**（直接改 `ProductModel.categoryId`，但交易的 `SummaryItem.categoryId` 仍是甲）
    → `hasTransaction(categoryId: 甲) == true`、`hasTransaction(categoryId: 乙) == false`
    ⭐ 這條是 A1 的核心：答案只看歷史快照，不隨商品搬移而改變。
    **目前 UI 走不到這個情境**（有交易的商品不能改類別，見下方「A1 的可達性」），
    所以只能、也必須用單元測試守住 —— 這正是為 Backlog 的「開放商品編輯」預先鋪路
  - 同一商品出現在多筆交易 → 不重複計數，`transactionCount` 等於交易筆數而非項目數
- ✅ **`DiscountCalculator`**（1.4，對應 F1–F5）
  - `amount(type: .percentage, value: 10, subtotal: 200)` == `20`
  - `amount(type: .amount, value: 20, subtotal: 200)` == `20`
  - **先百分比後定額**：`total(subtotal: 200, discounts: [9折, −20])` == `160`
    （若寫成先定額後百分比會得到 162，測試要能抓到）
  - **clamp 上界**：`total(subtotal: 50, discounts: [−100])` == `0`，且 `amount(...) == 50`（不是 100）
  - **clamp 下界**：負數折扣值 → `amount == 0`，總額不變
  - **百分比 clamp**：`value: 150` 視同 `100`，總額 `0`，不會變負
  - `subtotal == 0` → 所有 `amount` 都回 `0`，不會除以零
  - `effective(_:subtotal:)`：定額 100、小計 50 → 回傳 value 被改成 50 的 `DiscountModel`，**且 `id` 保持不變**
  - `deductionText`：`.percentage 5` → `"5%"`；`.amount 5` → `"-5"`
  - `displayText`：`.amount 5` + `"TWD"` → `"NT$5"`；未知幣別 → 走 `currencyDefaultSymbol`
- ✅ **`CSVExporter.escape`**（1.5，對應 U13）
  - 無特殊字元 → 原樣回傳（不加引號）
  - 含逗號 `大福,紅豆` → `"大福,紅豆"`
  - 含引號（例：`他說"好"`）→ 整欄加上引號，且內部每個引號變成連續兩個引號
  - 含換行 → 整欄加引號
  - 空字串 → 空字串
  - `row([...])` → 每欄逸出、以逗號相連、結尾 `\n`
- ✅ **`[SummaryItemModel].subtotal` / `[TransactionModel].summary`**（1.8）
  - 空陣列 → `0` / `(0, 0)`
  - 多筆小數金額相加，結果與逐次 `MoneyHelper.add` 相同（驗證沒退回原生 `+`）
- ✅ **`ProductModel.isAvailableForSale(in:)`**（1.3）
  - 商品啟用 + 類別啟用 → `true`
  - 商品下架 → `false`
  - 類別停用 → `false`
  - **類別不存在** → `.categoryMissing`（fail-closed）
    ⭐ 為了讓這條可測，`isAvailableForSale` 拆成兩層：純判斷的 `saleAvailability(in:)`
    （無副作用，測試測這個）＋ 外層負責 `assertionFailure` 與 log。
    否則 Debug 下測試會被 assertion 直接 trap
  - **商品已下架 + 類別也不存在** → 回 `.productDisabled`（短路，不會誤觸 assertion）
- ✅ **`[CategoryModel].active` / `.disabled`**（1.3）
  - 混合啟用/停用 + 亂序 `sortOrder` → 回傳正確子集且依 `sortOrder` 升冪
- ✅ **`markPendingSync(at:)`**（1.6）
  - 對 `CDProductEntity`（有 `updatedAt`）→ 兩個欄位都被設定
  - 對 `CDTransactionEntity`（1.11 剛加 `updatedAt`）→ 兩個欄位都被設定
  - 傳入固定 `date` → 批次內所有 entity 的 `updatedAt` 完全相同
- ✅ **`deleteProduct` 誠實失敗**（1.7，對應 D6）
  - 有交易的商品 → 回傳 `.failed`，且**該商品的 `isDisabled` 沒有被改動**
    ⭐ 這條專門防止「守衛偷偷做別的事」這個 bug 復發

##### 手動 —— 需操作 App

**前置：** 建一個測試場次，含 2 個類別（甲／乙）、每類別 3 個商品，並完成至少 1 筆含商品的交易。

- **1.1 ＋ 1.7｜類別的刪除／停用判斷**（U2／D4／D5）
  1. 類別甲底下的商品賣出 1 個（產生交易）；類別乙底下的商品都沒賣過
  2. 場次編輯頁對**類別甲**左滑 → 應顯示「停用」，沒有刪除
  3. 對**類別乙**左滑 → 應顯示「刪除」，按下去真的消失
  - 預期：甲**不會被偷偷改成停用**（改動前 repository 會靜默把它 `isDisabled = true`，
    呼叫端以為刪掉了；現在是原封不動留著 + log）
  - ⚠️ **U1 的「把商品搬到別的類別」步驟在 UI 上做不到** —— 見下方「A1 的可達性」說明，
    該情境改由單元測試覆蓋
- **1.1｜有交易的商品只能下架**（D1／D2）
  1. 對賣過的商品左滑 → 應只有「下架」，沒有刪除
  2. 對沒賣過的商品左滑 → 有「刪除」，按下去真的消失
- **1.2｜跨分頁資料一致（A3 的核心）**（U3／U4）
  1. 在場次編輯頁把類別甲**改名**，儲存
  2. 回到工作區，切到 **POS** 分頁 → 類別標題應是新名稱
  3. 切到 **管理商品** 分頁 → 類別標題也應是新名稱
  4. 再回場次編輯頁把類別甲**停用**，儲存
  5. POS 與管理商品**兩個畫面**都應立刻看不到甲的商品
  - 預期：不會出現「POS 已更新、庫存頁還是舊的」這種一新一舊
- **1.2｜場次被刪除時整個工作區退回**
  1. 進入場次工作區
  2. 用另一條路徑刪除該場次（回到場次列表左滑刪除）
  - 預期：自動 pop 回場次列表，不會停在空白的工作區
  - 註：這個偵測從 `InventoryView` 移到了容器，所以**在 POS 或報表分頁時也要會退回**（改動前只有在管理商品分頁才會）
- **1.2｜結帳後回到 POS，庫存有更新**（G1／G2）
  1. POS 加購商品 → 結帳（現金）→ 完成
  2. 回到 POS
  - 預期：該商品庫存數字已扣減；切到管理商品分頁也看得到新的庫存異動紀錄
  - ⭐ 這條專門驗證「刪掉死的 `@Binding` 寫回鏈後，資料仍然正確更新」
- **1.3｜可販售判斷**（U4／P3）
  1. 下架一個商品 → POS 看不到、管理商品的「已下架」區看得到
  2. 停用一個類別 → POS 整個類別區塊消失
  3. 上架 / 啟用回來 → 都恢復
- **1.3｜類別不存在時不靜默隱藏**（U12）
  1. 用 Xcode 的 CoreData 檢視或 `TestDataGenerator` 製造一個 `categoryId` 指向不存在類別的商品
  2. 進入 POS
  - 預期：Debug build **觸發 assertion 停下來**；Release build 在 console 看到 `🔴 商品 ... 的類別 ... 不存在`
  - 預期：**不會**只是安靜地少一個商品
- **1.4｜折扣**（F1／F2／F4／F6）
  1. 場次設定加一個 9 折與一個 −20
  2. POS 加購到小計 200 → 只選 9 折 → 應顯示 180
  3. 只選 −20 → 應顯示 180
  4. 再點一次已選的 chip → 取消，回到 200
  5. **把購物車清到小計 10，選 −20** → 總額應為 **0**，不是 −10
  6. 結帳完成後到交易紀錄查看
  - 預期：折扣標籤顯示 `-20`（不是 `-10`），**報表的營收不出現負數**
- **1.4｜折扣文字顯示位置**
  - POS 折扣 chip：`9%` / `NT$20` 格式
  - 交易紀錄列表的折扣標籤：`9%` / `-20` 格式
  - 交易明細 CSV 的折扣欄：同上，無折扣時為 `-`
  - ⭐ 折扣格式化已從 View 移進 ViewModel，要確認畫面顯示沒變
- **1.5｜CSV 逸出與檔名**（U13／R5／G6）
  1. 建一個商品叫 `大福,紅豆"特價"`（含逗號與引號）
  2. 賣出它
  3. 逐一匯出 **8 種 CSV**：庫存總覽、庫存異動明細、交易明細、熱門商品排行、類別銷售匯總、時段銷售分析、支付方式分析、日營收趨勢（永久場次再加月營收趨勢）
  4. 用 Numbers／Excel 開啟每一個
  - 預期：欄位不跑位，商品名完整顯示為 `大福,紅豆"特價"`
  - 預期：檔名為 `<標籤>_<場次名>_yyyyMMdd_HHmmss.csv`，場次名中的 `/ : \` 已被換成 `-`
  - ⭐ 改動前是把逗號偷換成全形「，」—— 現在資料是原樣的，逸出才是對的
- **1.6 ＋ 1.11｜寫入標記**（U8／U17）
  1. 新增一筆交易、一筆庫存異動、改一次商品、改一次場次
  2. 用 Xcode → Debug → 開啟 App 容器的 `.sqlite`（或加暫時 log）檢查對應 entity
  - 預期：`syncStatus == "pending"` **且** `updatedAt` 有值
  - ⭐ 交易與庫存異動的 `updatedAt` 是 1.11 才加的欄位，改動前這兩者根本沒有這個欄位
- **1.8｜兩個畫面的交易總額相同**（U5）
  1. 場次列表看某場次卡片的交易總額
  2. 切到日曆檢視，找同一個場次看總額
  - 預期：**完全相同**（改動前一邊用原生 `+`、一邊用 `MoneyHelper.add`，捨入可能不同）
  - 建議用含小數的幣別（USD/EUR）測，TWD 是整數看不出差異
- **1.9｜場次改名不影響歷史交易**（U14）
  > **前置確認：場次名稱在有交易後【仍然可以編輯】** —— `AddEventView` 的名稱 `TextField`
  > 沒有任何 `.disabled`。被鎖的是**幣別**（`AddEventView:163`）與**類別名稱**
  > （`canEditCategoryName`），不是場次名稱。所以這個情境是**可達的**。
  1. 場次「週末市集」賣出幾筆
  2. 回場次編輯頁，把名稱改為「週末市集（春）」→ 儲存（名稱欄應可正常輸入，不是灰的）
  3. 到報表 → 交易紀錄查看步驟 1 產生的舊交易
  - 預期：舊交易顯示的是**當時的名稱「週末市集」**
  - 預期：步驟 2 之後**新**產生的交易，`eventTitle` 才是「週末市集（春）」
  - ⭐ 這是刻意的行為改變：改動前會把歷史交易一起改名，而且只改本機、不標 `pending`，
    造成本機顯示新名、雲端／其他裝置／重裝後顯示舊名
- **1.10｜類別改名不造成更新風暴**（U15）
  1. 類別甲底下放 20 個商品
  2. 把類別甲改名
  3. 檢查這 20 個商品的 `syncStatus`
  - 預期：**沒有任何商品被標成 pending**（改動前 20 個全部會被重新標記 → 重構同步後會全部重傳）
  - 預期：POS 與管理商品顯示的類別名稱是**新的**（從 relationship 現查）
  - 預期：結帳後新產生的交易，其 `SummaryItem.category` 快照是**新名稱**
- **1.11｜relationship 與 Cascade**
  1. 對一個**沒賣過**的商品先做幾筆庫存異動（進貨、盤損）
  2. 刪除該商品
  3. 到管理商品 → 庫存異動明細 CSV 匯出檢查
  - 預期：該商品的異動紀錄一併消失，沒有孤兒紀錄
- **1.11｜複製場次**（G4）
  1. 複製一個有商品且有庫存的場次
  2. 檢查新場次
  - 預期：類別、商品、排序都正確；每個有庫存的商品各產生一筆「進貨入庫」異動
  - 預期：這些異動的 `syncStatus == "pending"` 且 `updatedAt` 有值（改動前這裡漏設 `updatedAt`）
- **回歸｜補記帳**（G3）
  1. 結帳頁開啟補記帳，選一個過去的日期
  2. 完成結帳
  - 預期：交易紀錄依 `occurredAt` 排序與分組；報表的日營收歸到**那一天**而非今天
- **回歸｜場次編輯的完整連動**（G5）
  1. 同一次編輯中：新增一個類別、刪除一個沒交易的類別、停用一個類別、改一個類別名、拖曳調整順序
  2. 儲存後回工作區
  - 預期：五種變更全部生效，沒有孤兒商品，POS 與管理商品的類別順序一致

### 第 2 批 — 報表 ✅ 2026-09-15 完成

| # | 項目 | 解決 | 狀態 |
|---|------|------|------|
| 2.1 | `unitPrice` → `averageUnitPrice` | D5 | ✅ |
| 2.2 | 商品銷售排行改成「排行 + 未售出摺疊區」 | §5.1 | ✅ |
| 2.3 | 報表三個方法改用 `EventDataSource` 的單一資料 | A5 | ✅（第 1 批已完成） |

#### 2.2 的最終設計：分兩區，不是一張大表

計畫原文是「列出所有商品，沒賣過的銷量 0」—— 也就是全部塞進同一張表。
實作時改成**分兩區**，理由來自 `PRODUCT.md` 的兩條產品原則：

> **收攤就算清**：報表不是高階分析工具，是攤商收攤後確認「今天賺了多少」的快速答案。
> **單手、單眼**：一手拿手機、一手找零，餘光瞄螢幕。

一張 50 列、後面 30 列全是 0 的表直接違背這兩條。但「哪些沒賣掉」是**下次要帶什麼**的
依據，而且只從交易反推的話滯銷品是**隱形的** —— 丟掉也不對。兩者是不同時刻的需求，所以分開放：

| 區塊 | 內容 | 欄位 |
|------|------|------|
| **商品銷售排行** | 只列**有賣出**的商品，**拿掉 `prefix(5)`**（只看前 5 名答不出「哪些下次不帶」） | 名次、名稱、類別、銷量、平均單價、原價總額、折扣、實際營收、貢獻率 |
| **本期未售出（N 項）** | 預設**收合**；展開後只列名稱與類別，已下架的加標記 | 不給名次與營收 —— 對這些商品一律是 0／沒有意義 |

**CSV 則全部列在同一張表**（未售出的排名欄為 `-`、數字欄為 0）。
CSV 是回家用 Excel 自己排序分析的，全部在一起才好用，沒有捲動成本的問題。

**「已下架且沒賣過」不做特例。** 它會落在「本期未售出」區，跟其他沒賣掉的商品一起。
補充一個複查結果：管理商品頁的 `getActionType` 是 `hasTransaction ? .disable : .delete`，
所以**從那個畫面下架不了沒賣過的商品**；但 `EventRepository.duplicateEvent:372`
複製場次時會原樣帶走 `isDisabled`，新場次零交易，那個商品就是下架 + 銷量 0 ——
所以這個狀態是可達的，只是不經由管理商品頁。

#### 實作與計畫的差異

| # | 計畫寫的 | 實際做的 | 為什麼 |
|---|---------|---------|-------|
| 2.2 | 列出所有商品，沒賣過的銷量 0（同一張表） | 分「排行」與「本期未售出（摺疊）」兩區；CSV 仍是一張表 | 見上方 |
| 2.2 | — | 空狀態改用新的 `hasSalesInRange` 判斷 | 排行榜現在只列賣出的，`topProducts.isEmpty` 仍可用；但語意上「有沒有資料」應該看有沒有交易，單一來源比較不會漂移 |
| — | — | **`loadData` 從非同步改成同步**（兩個報表 VM） | 原本包 `Task { await MainActor.run { ... } }`，但 VM 在第 1 批已標 `@MainActor`，那層沒有讓任何工作離開主執行緒，只是把結果延到下一個 runloop。**寫測試時才發現**：呼叫 `loadData()` 後同步讀 `topProducts` 永遠是空的 |
| — | — | 移除兩個報表 VM 的 `@Published var isLoading` | 全專案沒有任何 View 讀它（只有 `authManager.isLoading` 有人用）；同步化之後它也永遠不會被觀察到是 `true` |

#### 測試

##### 自動 —— 指令驗證

```bash
# 2.1 D5 的欄位已消失
grep -rn "假設同商品單價一致" --include="*.swift" Tilli          # 只剩解釋用註解 1 筆
grep -rn "averageUnitPrice" --include="*.swift" Tilli            # ProductSalesStats / ProductPerformanceData / View / CSV

# 2.2 不再只有前 5 名
grep -rn "prefix(5)" --include="*.swift" Tilli | grep -v _Deprecated   # 應 0 筆

# 2.3 報表不再自己查 DB，也不再有多餘的 async 包裝
grep -rn "fetchTransactions" --include="*.swift" Tilli/ViewModel/ReportsPage/   # 應 0 筆
grep -rn "Task {"            --include="*.swift" Tilli/ViewModel/ReportsPage/   # 只剩註解 1 筆
grep -rn "isLoading"         --include="*.swift" Tilli/ViewModel/ReportsPage/   # 應 0 筆
```

- ✅ 全部符合預期
- ⚠️ 注意：`grep -rn "\bunitPrice\b"` **不會是 0**，那是正常的 ——
  `addSale(quantity:unitPrice:actualTotal:)` 的**參數**（每筆交易的快照單價，用來算原價總額）
  以及交易明細／庫存 CSV 裡「該列的單價」都還在。被刪掉的是 `ProductSalesStats`
  那個會被覆蓋的**儲存欄位**。

##### 自動 —— 單元測試 ✅（新增 12 個，總計 87 個全過）

- ✅ **`ProductSalesStats.averageUnitPrice`**（2.1，`ProductSalesStatsTests` 5 個）
  - 3 個 × 100 ＋ 2 個 × 50 → `(300+100) ÷ 5 = 80`，**不是**「最後一筆的 50」⭐ 這條就是 D5
  - 只有一種單價時 → 等於該單價（確保沒有回歸）
  - 銷量 0 → `0`，**不會除以零**
  - `addSale` 正確累加 `originalRevenue` / `actualRevenue` / `totalDiscount`
  - `33.33 × 3` → 平均單價保持 `33.33`，不提前捨入
- ✅ **排行與未售出的切分**（2.2，`ProductPerformanceSplitTests` 7 個，走真實的 in-memory CoreData + `EventDataSource`）
  - 三個商品：1 個賣過、1 個沒賣過、1 個「已下架且沒賣過」
  - 排行**只列賣出的**，名次從 1 開始
  - 未售出清單**涵蓋每一個沒賣出的商品** ⭐ 滯銷品不可以是隱形的
  - 「已下架且沒賣過」照樣列出，只是多帶 `isDisabled` 標記
  - 未售出依商品自己的 `sortOrder` 排序（跟管理商品頁／POS 一致）
  - **兩區相加 == 該場次商品總數**（每個商品只出現在一區，且不漏）
  - 切到沒有交易的時間範圍 → `hasSalesInRange == false`、排行空、三個商品全部算未售出
  - `averageUnitPrice` 正確流到 `ProductPerformanceData`

##### 手動 —— 需操作 App

- **2.1 平均單價**
  1. 同一商品分兩筆交易賣出，其中一筆套用折扣讓成交單價不同
  2. 報表 → 商品績效 → 展開該商品的「詳細資訊」
  - 預期：欄位標題是「**平均單價**」，數值是原價總額 ÷ 總銷量
  - 預期：匯出「熱門商品排行」CSV 的標題列也是「平均單價(TWD)」
- **2.2 排行區**
  1. 場次建 8 個商品，賣掉其中 3 個
  2. 報表 → 商品績效
  - 預期：排行區有 **3 列**（不是 5 列、也不是 8 列），名次 1～3
  - 預期：**賣出 6 個以上不同商品時，第 6 名之後也看得到**（`prefix(5)` 已移除）
- **2.2 未售出摺疊區**
  1. 同上情境
  - 預期：排行下方有「**本期未售出（5 項）**」，**預設收合**
  - 預期：點一下展開，列出 5 個商品的名稱與類別，**沒有名次也沒有金額欄位**
  - 預期：再點一下收合
  - 預期：全部商品都賣掉時，這個區塊**整個不出現**
- **2.2 已下架商品的標記**
  1. 複製一個含下架商品的場次（下架商品才會被帶過去且零交易）
  2. 進新場次的報表
  - 預期：那個商品出現在「本期未售出」，名稱旁有「**已下架**」標記
- **2.2 切換 timeRange 的連動**
  1. 賣掉某商品後，把 timeRange 切到**該交易之前**的區間
  - 預期：該商品從排行消失、出現在「本期未售出」
  - 預期：所有商品都沒賣出時，顯示「尚無商品銷售數據」空狀態（而不是一整排 0）
- **2.2 CSV 含未售出**
  1. 匯出「熱門商品排行」CSV
  - 預期：賣出的在上（有名次），未售出的在下，**排名欄為 `-`**、數字欄為 0
  - 預期：列數 == 該場次商品總數
- **2.3 切換 timeRange 不重查 DB**（U6／P5）
  1. 在 `EventDataSource.reload()` 暫時加一行 `print`
  2. 進入報表頁 → console 只印 **1 次**
  3. 連續切換 timeRange 數次 → console **完全不再增加**
- **回歸：三張報表數字互相一致**（R4）
  - 同一個 timeRange 下，交易紀錄的總額、商品績效的營收合計、銷售分析的總營收三者一致
- **回歸：報表不再閃爍**
  - `loadData` 改同步後，切換 timeRange 的數字是**一次到位**，不會先空一格再填上

#### 測試（預定）

> 2.3 已在第 1 批一併完成（三個方法都改吃 `dataSource.transactions(in:)`），
> 本批只需補做 2.1 與 2.2，但驗收時三項一起測。

##### 自動 —— 指令驗證

- ⬜ `grep -rn "unitPrice" --include="*.swift" Tilli` → 應只剩 `averageUnitPrice`，舊名 0 筆
- ⬜ `grep -rn "假設同商品單價一致" --include="*.swift" Tilli` → 0 筆（D5 的註解連同欄位刪除）
- ⬜ `grep -rn "fetchTransactions" --include="*.swift" Tilli/ViewModel/ReportsPage/` → **0 筆**（報表一律走 `dataSource`）
- ⬜ 建置與既有測試仍通過

##### 自動 —— 單元測試（⬜ 待補）

- ⬜ **`averageUnitPrice` 計算**（2.1）
  - 同一商品兩筆交易：3 個 × 100、2 個 × 50 → 平均單價 = (300+100) ÷ 5 = **80**
  - 銷量 0 的商品 → 平均單價為 `0`，**不可除以零 crash**
  - 只有一種單價時 → 平均單價等於該單價（與改動前的 `unitPrice` 相同，確保沒有回歸）
- ⬜ **商品銷售排行的骨架來源**（2.2）
  - 場次有 5 個商品、只有 2 個賣過 → 回傳 **5 筆**，未售出的銷量 0、營收 0
  - 排序：有銷量的在前並依營收降冪，銷量 0 的在後（依 `sortOrder` 或名稱，實作時定案並鎖進測試）
  - **已下架但賣過**的商品 → 仍要出現（歷史績效不能消失）
  - **已下架且沒賣過**的商品 → **也要出現**，銷量 0

> **決定（2026-09-15）：排行榜不對 `isDisabled` 做任何特例，就是「該場次的所有商品」。**
>
> 背景：管理商品頁的 `getActionType` 是 `hasTransaction ? .disable : .delete`，
> 所以**從那個畫面下架不了沒賣過的商品**。但「已下架且沒賣過」仍然是可達狀態 ——
> `EventRepository.duplicateEvent:372` 複製場次時會原樣帶走 `isDisabled`，
> 新場次沒有任何交易，那個商品就是下架 + 銷量 0。
>
> 與其為這個邊界寫特例，不如不判斷 `isDisabled`：骨架直接取
> `EventDataSource.products`，全部列出。
- ⬜ **`transactions(in:)` 的邊界**（2.3，`EventDataSource`）
  - `range == nil` → 回傳全部
  - 交易剛好落在 `range.start` / `range.end` → **包含**（與 `TransactionRepository` 的 `>=` / `<=` 一致）
  - 補記帳交易依 `displayDate`（`occurredAt`）落點，不是 `timestamp`

##### 手動 —— 需操作 App

- **2.1 平均單價**
  1. 同一商品分兩筆交易賣出，其中一筆套用折扣讓成交單價不同
  2. 報表 → 商品績效 → 看該商品的單價欄
  - 預期：顯示**平均單價**，不是固定的第一筆單價
  - 預期：欄位標題也已改成「平均單價」而非「單價」
- **2.2 商品銷售排行列出所有商品**（R1）
  1. 場次建 5 個商品，只賣其中 2 個
  2. 報表 → 商品績效 → 商品銷售排行
  - 預期：**5 個全部出現**，沒賣過的顯示銷量 0、營收 0
  - 預期：匯出「熱門商品排行」CSV 也是 5 列
- **2.3 切換 timeRange 不重查 DB**（U6／R4／P5）
  1. 在 `EventDataSource.reload()` 暫時加一行 `print`
  2. 進入報表頁 → console 應只印 **1 次**
  3. 連續切換 timeRange（今天／本週／自訂）數次 → console **完全不再增加**
  - 預期：切篩選條件是純記憶體運算，0 次 DB 查詢
  - 註：第 1 批已把 `reloadAllData`（查 DB）與 `loadAllData`（只重算）分開，這裡是驗證它真的生效
- **2.3 三張報表數字互相一致**（R4）
  1. 同一個 timeRange 下比對：交易紀錄的筆數與總額、商品績效的營收合計、銷售分析的總營收
  - 預期：三者基於同一份交易，筆數一致、金額一致
- **回歸：報表 CSV**（G6）
  - 五種報表 CSV 內容與第 1 批測過的結果一致，只有單價欄語意改變

### 第 3 批 — 折扣 ✅ 2026-09-15 完成

| # | 項目 | 狀態 |
|---|------|------|
| 3.1 | `AppliedDiscount` schema + CoreData `appliedDiscountsData` | ✅ |
| 3.2 | 折扣 chip UI（兩區各單選、升冪、即時顯示） | ✅ |
| 3.3 | 場次設定頁的折扣管理調整 | ✅ |
| 3.4 | 全部改呼叫 `DiscountCalculator` | ✅ |

#### 實作與計畫的差異

| # | 計畫寫的 | 實際做的 | 為什麼 |
|---|---------|---------|-------|
| 3.2 | 兩個獨立的選取欄位 | `selectedDiscountIds: [DiscountType: UUID]`，用**型別當 key** | 之後多一種折扣型別時，`toggleDiscount` / `isSelected` 都不用改；也讓 U9（折扣 `switch` 只在 `DiscountCalculator` 內）字面上維持成立 |
| 3.3 | 「折扣管理調整」（未指定） | 依型別**分兩區、各自升冪**，並**移除拖曳換序** | POS 的 chip 一律照數值升冪排（§6.4），設定頁排了也不會反映到收銀畫面，留著只會讓人誤會 |
| 3.4 | — | 新增 `DiscountCalculator.sanitized(_:subtotal:)`，兩個付款 VM 在寫入前呼叫 | `AppliedDiscount.amount` 是呼叫端給的**快照**，不能無條件相信。原本的保護是 `effective()`，但它回傳 `DiscountModel`（沒有 amount），換成快照後需要對應的守門 —— 見 CONVENTIONS.md「保護要放在寫入邊界」 |
| — | — | `TestDataGenerator` **沒有更新** | 它已在第 1 批被移到 `_Deprecated/`，且列在 `project.pbxproj` 的 `membershipExceptions` 裡**不參與編譯**。跟其他 12 個 deprecated 檔一樣停在舊 API |

#### 3.1 的關鍵：`amount` 是快照，不重算

```swift
struct AppliedDiscount: Codable, Hashable, Identifiable {
    var discountId: UUID   // 對應 event.discounts；設定被刪除後仍可追溯
    var type: DiscountType
    var value: Decimal     // 快照：折扣設定的值
    var amount: Decimal    // ⭐ 快照：實際折抵金額（已 clamp）
}
```

`DiscountCalculator.amount(for: transaction)` **直接加總 `amount`**，不從 `value` 重算 ——
重算的話，之後改了場次的折扣設定，歷史交易的金額就會跟著變（F7）。

不變式：`Σ applied.amount == subtotal − total(subtotal:discounts:)`。
第 4 批的攤提會依賴這條（§7.3），已用多組輸入鎖進測試。

#### 測試

##### 自動 —— 指令驗證

```bash
# 3.1 舊欄位徹底消失（含 CoreData model）
grep -rn "discountType\|discountValue" --include="*.swift" . | grep -v _Deprecated   # 只剩 1 筆註解
grep -c  "discountType\|discountValue" Tilli/Data/CoreData/Tilli.xcdatamodeld/Tilli.xcdatamodel/contents   # 0
grep -o  'name="appliedDiscountsData"[^/]*' Tilli/Data/CoreData/Tilli.xcdatamodeld/Tilli.xcdatamodel/contents

# 3.2 / 3.4 舊的單選與 clamp 入口已移除
grep -rn "selectedDiscountId\b" --include="*.swift" Tilli | grep -v _Deprecated      # 0
grep -rn "effectiveDiscount"    --include="*.swift" Tilli | grep -v _Deprecated \
  | grep -v DiscountCalculator.swift                                                 # 0

# 3.3 拖曳換序已移除
grep -rn "moveDiscount" --include="*.swift" Tilli | grep -v _Deprecated              # 0

# U9 持續成立
grep -rnE "switch (discountType|discount\.type)" --include="*.swift" Tilli \
  | grep -v _Deprecated | grep -v DiscountCalculator.swift                           # 0
```

- ✅ 全部符合預期

##### 自動 —— 單元測試 ✅（新增 22 個，總計 109 個全過）

- ✅ **`DiscountCalculator.applied`**（3.1，`AppliedDiscountTests` 6 個）
  - 逐筆記下實際折抵：200 選 9 折 + −20 → `[percentage amount:20, amount amount:20]`
  - **無論輸入順序，輸出一律百分比在前**
  - ⭐ **`Σ amount == subtotal − total`**，用 7 組輸入驗（含 clamp、除不盡、小額）——
    第 4 批的攤提直接依賴這條
  - 定額 clamp 到「套用百分比之後」的餘額：200 → 九折剩 180 → 定額 500 只折 180
  - 小計 0 或無折扣 → 空陣列
  - `discountId` 保留，設定被刪除後仍可追溯
- ✅ **`DiscountCalculator.sanitized`**（3.4，4 個）
  - 合法輸入**原樣回傳**（快照不被動到）
  - 多筆累計超過小計 → 逐筆遞減收斂，`Σ amount == subtotal`
  - 負數 → 0；小計 0 → 空陣列
- ✅ **快照語意**（3.1，3 個）
  - ⭐ `value` 與 `amount` 刻意不一致時，`amount(for:)` 回**快照值**而不是重算值（F7）
  - JSON 往返後 `Decimal` 精度不丟失
  - 舊資料（`appliedDiscountsData == nil`）解碼成空陣列，不 crash
- ✅ **多折扣顯示**（1 個）：`deductionText(for:)` → `"10% -20"`
- ✅ **POS 選取邏輯**（3.2，`POSDiscountSelectionTests` 8 個）
  - 亂序建立的折扣，chip **自動分兩區且各自升冪**
  - 同一區選第二個會**取代**前一個
  - 再點一次**取消**
  - ⭐ 百分比與定額**可同時選**
  - `selectedDiscounts` **永遠百分比在前**（與套用順序一致）
  - 清空購物車一併清除折扣
  - 超額提示比的是**折後**金額而非原始小計

##### 手動 —— 需操作 App

> ⚠️ **這批是破壞性 schema 變更**（`discountType`/`discountValue` → `appliedDiscountsData`）。
> 測試前請**刪 App 重裝**。App 未上架，不需要資料轉移。

- **3.3 場次設定頁的折扣管理**
  1. 新增百分比折扣 10、5、20（刻意亂序輸入）
  2. 新增定額折扣 50、20
  - 預期：清單**分兩區**顯示，百分比區是 5／10／20，定額區是 20／50（**各自升冪**）
  - 預期：**沒有拖曳把手**，也拖不動
  - 預期：左滑仍可刪除
  3. 輸入邊界值：百分比 0／100／101、定額 0／負數、重複值
  - 預期：不合法的值被擋下並有提示
- **3.2 折扣 chip**
  1. POS 加購到小計 200
  - 預期：結帳列上方有**兩排 chip**，百分比一排、定額一排，各自升冪
  2. 點百分比 10
  - 預期：該 chip **高亮**，下方出現 `200 → 180`（原價有刪除線）
  3. 再點定額 20
  - 預期：**兩個 chip 同時高亮**，顯示 `200 → 160`
  - ⭐ 若顯示 162 就是順序錯了（變成先扣定額再打折）
  4. 再點一次百分比 10
  - 預期：取消，只剩定額，顯示 `200 → 180`
  5. 兩個都取消
  - 預期：`200 → ...` 那一行**整個消失**（沒有折抵時不顯示）
- **3.2 clamp 的視覺回饋**（F4）
  1. 把購物車減到小計 100，選 9 折（剩 90）再選定額 200
  - 預期：總計顯示 **0**，並出現「折扣不可超過商品金額，已自動調整」
  - ⭐ 提示的門檻是 **90**（折後）而不是 100（原始小計）
- **3.1 ＋ 3.4 全流程**
  1. 選百分比 + 定額 → 現金結帳
  2. 再做一次 → 電子支付結帳
  3. 報表 → 交易紀錄
  - 預期：每筆交易顯示**兩個**折扣標籤
  - 預期：展開後金額正確，實收 == 小計 − 兩個折抵
  4. 匯出交易明細 CSV
  - 預期：折扣欄顯示 `10% -20`（兩個以空格相連），無折扣時為 `-`
  5. 商品績效
  - 預期：營收為攤提後金額，**不出現負數**
- **3.1 快照不被設定變更影響**（⭐ F7）
  1. 用 9 折賣掉一筆
  2. 回場次設定頁，把那個 9 折**改成 5 折**（刪掉再新增）
  3. 回報表看**步驟 1 的那筆舊交易**
  - 預期：折抵金額**完全沒變**（快照），不是被重算成 5 折
  - 預期：商品績效的營收也沒變
- **回歸：不選折扣的結帳**（最常見路徑）
  - 現金與電子支付都正常，交易的折扣標籤不顯示，CSV 折扣欄為 `-`（G1／G2）
- **回歸：補記帳 + 折扣**
  - 補記帳開啟時選折扣結帳，日期與金額都正確（G3）

#### 測試（預定）

> ⚠️ 這批會把 `TransactionModel.discountType/discountValue` 換成 `appliedDiscounts`，
> 是**破壞性 schema 變更**。App 未上架，直接刪 App 重裝即可，但要確認舊路徑真的全部移除。

##### 自動 —— 指令驗證

- ⬜ `grep -rn "discountType\|discountValue" --include="*.swift" Tilli` → **0 筆**（含 CoreData properties）
- ⬜ CoreData model：`CDTransactionEntity` 不再有 `discountType` / `discountValue`，改有 `appliedDiscountsData`
- ⬜ `grep -rnE "switch (discountType|discount\.type|appliedDiscount)" --include="*.swift" Tilli | grep -v DiscountCalculator.swift` → 0 筆（U9 持續成立）
- ⬜ §14.2 登記表第 1 列狀態要從 ⬜ 更新

##### 自動 —— 單元測試（⬜ 待補）

- ⬜ **`AppliedDiscount` 的 `amount` 快照**（3.1，對應 F7）
  - 建立交易時 `amount` 寫入 clamp 後的實際折抵金額
  - **之後修改 `event.discounts` 的設定值** → 重新讀取該交易，`amount` **不變**
    ⭐ 這是 3.1 的核心：沒有快照的話，改折扣設定會讓歷史交易的金額整批算錯
- ⬜ **多重折扣組合**（3.4，對應 F1–F3）
  - 只有百分比、只有定額、兩者都有 → 三種都正確
  - 兩個百分比同時存在（UI 不允許，但資料層要可預測）→ 依序套用，不會爆
  - 空陣列 → 總額等於小計
- ⬜ **編碼往返**（3.1）
  - `[AppliedDiscount]` → JSON → `[AppliedDiscount]` 值完全相同（`Decimal` 精度不丟失）
  - `appliedDiscountsData == nil`（舊資料）→ 解碼成空陣列，不 crash

##### 手動 —— 需操作 App

- **3.3 場次設定頁的折扣管理**
  1. 新增百分比折扣、新增定額折扣、編輯、刪除
  2. 輸入邊界值：百分比 0 / 100 / 101、定額 0 / 負數
  - 預期：不合法的值被擋下並有提示
  - 預期：有交易的場次仍可改折扣設定（歷史交易不受影響，見 F7）
- **3.2 折扣 chip UI**
  1. POS 下方應有**兩區**：百分比、折抵金額
  2. 每區各自**單選**，chip 依值**升冪**排列
  3. 點已選的 chip → 取消
  4. 兩區**各選一個** → 兩個 chip 同時高亮
  5. 小計與折後金額**即時**更新
  - 預期：`200 → 9折 180 → −20 = 160`（**先百分比後定額**；若顯示 162 就是順序錯了）
- **3.2 clamp 的視覺回饋**（F4）
  1. 小計 10，選 −20
  - 預期：總額顯示 **0**，並出現「折扣不可超過商品金額，已自動調整」的提示
- **3.4 全流程一致**
  1. 選兩種折扣 → 結帳（現金與電子支付各一次）
  2. 交易紀錄 → 該筆交易應顯示**兩個**折扣標籤
  3. 交易明細 CSV → 折扣欄要能表達兩個折扣
  4. 商品績效 → 營收為攤提後的金額，**不出現負數**
- **3.1 破壞性變更的回歸**
  1. 刪 App 重裝 → 重新建場次、商品、交易
  - 預期：全流程正常，沒有因為 CoreData 欄位改名而崩潰
- **回歸**：不選任何折扣的結帳流程（最常見路徑）完全正常（G1／G2）

### 第 4 批 — 攤提（⭐ 必須在組合之前）

| # | 項目 | 解決 |
|---|------|------|
| 4.1 | `SummaryItemModel` 擴充 5 個欄位 | §7.2 |
| 4.2 | `RevenueAllocator`，結帳時計算 | A6 |
| 4.3 | **刪除** `ProductPerformanceViewModel` 三處攤提與三處 reduce | B1、B2 |
| 4.4 | 驗證兩張報表營收相等 | 測試 R2 |

#### 測試（預定）

> 這批是**金額正確性**的關鍵，捨入處理錯了會讓兩張報表對不起來。
> 單元測試的價值遠高於手動測試，建議先把 `RevenueAllocator` 的測試寫滿再接 UI。

##### 自動 —— 指令驗證

- ⬜ `grep -rn "itemProportion\|transactionSubtotal" --include="*.swift" Tilli/ViewModel/ReportsPage/` → **0 筆**（報表端攤提整段刪除）
- ⬜ `grep -rn "DiscountCalculator.amount(for: transaction)" --include="*.swift" Tilli/ViewModel/ReportsPage/` → 0 筆（報表改成直接加總 `actualRevenue`，不再重算折扣）
- ⬜ `grep -rn "reduce" --include="*.swift" Tilli/ViewModel/ReportsPage/ProductPerformanceViewModel.swift` → 只剩單純加總，沒有攤提邏輯

##### 自動 —— 單元測試（⬜ 待補，**本批最重要**）

- ⬜ **`RevenueAllocator` 恆等式（⭐ 對應 R2）**
  - **`Σ actualRevenue == transaction.totalAmount`**，對**任意**輸入都成立
  - 建議用隨機測試：隨機 1–10 個項目、隨機單價（含小數）、隨機數量、隨機折扣組合，跑 1000 次，每次都驗這條恆等式
  - ⭐ 這條就是 A6 的定義：兩張報表的口徑相等，不是靠巧合
- ⬜ **攤提順序**（§7.3）
  - ① 原價小計 → ② 套餐差額 → ③ 百分比 → ④ 定額 → ⑤ 捨入差額由最後一項吃掉
  - 驗證：把順序對調會得到不同結果，測試要能抓到
- ⬜ **捨入差額處理**
  - 小計 100 分成 3 項（各 33.33…）搭配 10% 折扣 → 三項 `actualRevenue` 相加**剛好**等於總額
  - 差額只出現在**最後一項**，且絕對值 ≤ 1 分
  - 全部用整數（分）運算，不會出現 `0.30000000000000004` 這類浮點殘渣
- ⬜ **邊界**
  - 單一項目 → 全部折扣都算在它身上
  - 折扣為 0 → `actualRevenue == originalSubtotal`、`allocatedDiscount == 0`
  - 折扣 clamp 到等於小計 → 所有 `actualRevenue` 都是 0，**沒有任何一項是負數**
  - 數量為 0 的項目（理論上不該存在）→ 不會除以零
  - 項目單價為 0（贈品）→ 攤提比例為 0，不會 NaN
- ⬜ **`SummaryItemModel` 新欄位的編碼往返**（4.1）
  - 5 個新欄位 JSON 往返後值不變
  - 舊資料（沒有這些欄位）解碼 → 有合理預設值且不 crash
- ⬜ **報表加總**（4.3）
  - 商品績效的營收 = `Σ SummaryItem.actualRevenue`，**不再重算折扣**
  - 同一份交易資料，新舊兩種算法結果相同（做為重構不改壞的護欄）

##### 手動 —— 需操作 App

- **4.4 兩張報表營收相等（⭐ R2，本批的驗收條件）**
  1. 建立多筆交易：含折扣的、不含折扣的、補記帳的都要有
  2. 報表 → 銷售分析 → 記下**總營收**
  3. 報表 → 商品績效 → 把所有商品的**實際營收**加總
  - 預期：**兩者相等**，捨入差額 ≤ 1 分
  - 預期：換不同 timeRange 重測數次，仍然相等
- **4.2 結帳當下就算好**
  1. 結帳完成後立刻看報表
  - 預期：數字馬上正確（攤提發生在結帳時，不是報表時）
  2. 之後**修改場次的折扣設定**，再看同一筆交易的報表
  - 預期：歷史數字**完全不變**（已凍結在 `SummaryItem` 裡）
- **4.1 攤提結果可追溯**
  1. 用 Xcode 檢查一筆含折扣交易的 `itemsData`
  - 預期：每個 item 都有 `originalSubtotal`、`allocatedDiscount`、`actualRevenue`
  - 預期：`originalSubtotal − allocatedDiscount == actualRevenue`，逐項成立
- **4.3 報表端沒有殘留的重複計算**
  1. 在原本三處攤提的位置確認程式碼已刪除
  2. 切換 timeRange，確認數字仍正確
  - 預期：報表只是單純加總，不再有 `switch discountType` 或比例分攤
- **回歸**：折扣、無折扣、補記帳三種結帳路徑的金額都正確（G1／G2／G3）

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

#### 測試（預定）

> 最大的一批，兩種 `BundleMode` 的互動方式完全不同（§8.3），測試要分開列。

##### 自動 —— 指令驗證

- ⬜ CoreData model：`CDEventEntity` 有 `bundlesData: Binary`；**沒有**新增任何 entity
- ⬜ `CDInventoryChangeEntity` 有 `bundleId` / `bundleName`
- ⬜ `grep -rn "isAvailable" --include="*.swift" Tilli` → 是**算出來的** computed property，不是存起來的欄位（與 §2.5 同原則）
- ⬜ `grep -rn "bundlesData\|bundleId" Tilli/Data/CoreData/Tilli.xcdatamodeld/Tilli.xcdatamodel/contents` → 都存在
- ⬜ §14.2 登記表第 3、4 列狀態要更新

##### 自動 —— 單元測試（⬜ 待補）

- ⬜ **`.chooseAny` 自動套用演算法**（5.4，對應 B2／B9／B11）
  - 候選 10 個、購物車 7 個、`count: 3` → 套用 **2 組**，剩 1 個原價
  - **挑單價最高的**：驗證被納入組合的是最貴的 6 個（對客人最有利）
  - 購物車只有 2 個（< count）→ **0 組**，全部原價
  - 剛好 3 個 → 1 組，無剩餘
  - 同一商品數量 5 個、`count: 3` → 展開成單品後套 1 組，剩 2 個原價
  - **兩個組合都符合** → 依 `sortOrder` 貪婪套用，結果**可預測且穩定**（同樣輸入永遠同樣輸出）
  - **同一件商品不被算進兩個組合**（B11）
- ⬜ **`.fixed` 套餐**（5.3）
  - 成員各 1 個，組合價取代成員原價總和
  - 成員清單為空 → 不可販售，不會產生 0 元交易
- ⬜ **`BundleModel.isAvailable`**（5.7，對應 B7／B8）
  - 所有成員都可販售 → `true`
  - 任一成員**下架** → `false`
  - 任一成員的**類別停用** → `false`（與 `isAvailableForSale` 同一套判斷）
  - 任一成員**已被刪除**（`productIds` 有但 `products` 查不到）→ `false`，且有 log
  - bundle 自己 `isDisabled` → `false`
  - 成員**上架回來** → 自動變回 `true`（不需任何額外操作）⭐ 這是「算出來而非存起來」的關鍵驗證
- ⬜ **攤提整合**（5.6，接第 4 批）
  - 套餐差額按成員**原價比例**攤提
  - `Σ actualRevenue == totalAmount` 在**有套餐**的情況下仍然成立
  - 套餐 + 整筆折扣同時 → 順序為「套餐差額 → 百分比 → 定額」（B10）
- ⬜ **編碼往返**：`BundleModel` / `BundleMode`（含 `.chooseAny(count:)` 的關聯值）JSON 往返值不變

##### 手動 —— 需操作 App

- **5.2 管理 UI**（B1）
  1. 工作區新分頁「組合／套餐」→ segmented control 切兩區
  2. 建立「任選三個 100」：勾 10 個候選商品
  3. 建立「下午茶套餐 100」：選 3 個成員
  4. 拖曳調整組合順序、編輯、停用、刪除
  - 預期：都正常；勾選清單能搜尋／依類別分組（商品多時可用）
- **5.4 ＋ 5.5 組合優惠自動套用**（B2／B3）
  1. POS 加入 7 個候選商品（單價刻意不同）
  2. 看結帳頁
  - 預期：顯示「任選三個100 × 2 組，折抵 NT$XX」
  - 預期：被納入的是**單價最高的 6 個**
  - 預期：可**手動取消**套用，取消後金額回到原價總和
  - 預期：取消後再回 POS 改數量，重新進結帳頁會**重新自動套用**
- **5.3 套餐點選**（B4）
  1. POS 應有獨立的「套餐」區塊
  2. 點選套餐 → 購物車出現「下午茶套餐 × 1」
  - 預期：套餐**不會**出現在一般商品列表裡
  - 預期：可加減數量、可移除
- **5.6 庫存扣減**（B5）
  1. 賣出 1 份套餐（3 個成員）
  2. 管理商品 → 看三個成員的庫存與異動紀錄
  - 預期：三個成員各扣 1，產生 **3 筆** `InventoryChange`
  - 預期：三筆都帶相同的 `bundleId` 與 `bundleName` 快照
  - 預期：庫存異動明細 CSV 看得出它們來自同一次套餐銷售
- **5.6 庫存不足的處理**
  1. 讓套餐其中一個成員庫存只剩 0
  2. 嘗試在 POS 點選該套餐
  - 預期：擋下並提示是哪個成員缺貨（不要靜默失敗或扣成負庫存）
- **5.7 可用性：不擋、提示、自動失效**（B7／B8）
  1. 下架一個被 2 個組合包含的商品
  - 預期：出現提示「有 2 個組合包含此商品，下架後這些組合將無法販售」
  - 預期：**下架動作本身不被阻擋**
  2. 回到 POS
  - 預期：那 2 個組合**灰掉**並顯示「含已下架商品」，點不下去
  3. 組合管理頁
  - 預期：那 2 個組合有 ⚠️ 標記
  4. 把商品**上架回來**
  - 預期：兩個組合**自動恢復**可販售，不需要任何手動操作 ⭐
- **5.7 成員被刪除的情況**
  1. 把某組合的成員商品**直接刪除**（該商品沒賣過所以可刪）
  - 預期：組合變不可販售並有明確標示，**不會 crash**
- **B6 報表**
  1. 賣出套餐後看商品績效
  - 預期：成員商品**各自計入**，金額是攤提後的 `actualRevenue`
  - 預期：成員營收加總 = 套餐售價（不是成員原價總和）
- **B10 套餐 + 整筆折扣**
  1. 購物車同時有套餐與一般商品，再套用 9 折 + −20
  - 預期：攤提順序正確，`Σ actualRevenue == totalAmount`
- **B11 套餐與組合優惠同時**
  1. 購物車同時觸發套餐與「任選三個」
  - 預期：同一件商品**只被算進一個**組合，沒有重複折抵
- **回歸**：完全不使用組合／套餐的原本結帳流程不受任何影響（G1／G2）

### 第 6 批 — POS UI

| # | 項目 |
|---|------|
| 6.1 | 類別 chip 列 + 點擊跳躍 + 高亮 |

#### 測試（預定）

##### 自動 —— 指令驗證

- ⬜ 類別列的資料來源是 `viewModel.activeCategories`（第 1 批已建立的單一定義），
  `grep -rn "filter { !\$0.isDisabled }" Tilli/View/POSPage/` → **0 筆**
- ⬜ 捲動位置、選中的 chip 屬於純 UI 狀態，應是 View 的 `@State`
  （CONVENTIONS「MVVM 規則」第 3 條）；跳躍目標的計算若含商業判斷才進 ViewModel

##### 手動 —— 需操作 App

- **6.1 點擊跳躍**（P1）
  1. POS 最上方應有橫向類別列 `[全部] [類別1] [類別2] …`
  2. 點某個類別 chip
  - 預期：商品列表捲到該類別區塊，該 chip **高亮**
  - 預期：點「全部」回到頂端
- **6.1 捲動連動**（P2）
  1. 手動捲動商品列表
  - 預期：chip 高亮**跟著**目前可見的類別變化
  - 預期：高亮的 chip 若在畫面外，chip 列**自動捲動**讓它可見
  - 預期：捲動時不會閃爍或與手動點擊互相打架
- **6.1 與類別狀態連動**（P3）
  1. 停用一個類別 → 回 POS
  - 預期：該 chip **消失**，商品也消失
  2. 類別改名 → 回 POS
  - 預期：chip 文字是新名稱（走第 1 批的 `EventDataSource`）
  3. 調整類別順序 → 回 POS
  - 預期：chip 順序跟著 `sortOrder`
- **6.1 邊界狀況**
  - 只有 1 個類別 → chip 列的呈現合理（或依設計隱藏）
  - 類別很多（10+）→ 可水平捲動，不擠壓商品區
  - 類別名稱很長 → 不破版（截斷或縮放，依 `DESIGN.md`）
  - 某類別底下沒有可販售商品 → 依設計決定 chip 要不要出現，並鎖進測試
- **6.1 兩種版面**
  - `list` 與 `grid` 兩種 `layoutMode` 下，跳躍與高亮都要正確
- **視覺**：對照 `DESIGN.md` 的 token（間距、圓角、選中/未選中顏色），不要自創樣式

### Backlog

- 庫存 +/− 與盤點雙模式（§10）
- 組合／套餐績效報表
- 類別 icon
- 商品編輯開放（等本輪統一穩定後再評估）
- 本地化三條通道收斂（§1.7 F1–F4，等語言切換去留的產品決定）

---

## 12. 測試清單

> 這裡是**跨批的總清單**，用來確認 §1 的 28 項查核有沒有真的收斂。
> **逐批、逐個改動的詳細驗收步驟在 §11 每批下方的「測試」區**，
> 那裡有指令、單元測試案例與完整的手動操作步驟。
> 本節的編號（U／D／E／R／F／B／P／G）會被 §11 引用。

### 12.1 ⭐ 一致性測試（本輪重點，驗證 24 項查核有真的收斂）

| # | 情境 | 預期 |
|---|------|------|
| **U1** | 商品從 A 類別搬到 B 類別後，問「A 類別有交易嗎」 | **所有呼叫端答案一致**（依快照：A 有、B 沒有）<br>⚠️ **UI 不可達**（有交易的商品不能改類別，見 §1.1「A1 的可達性」）→ 用單元測試覆蓋 |
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
| 8 | **App 內的語言切換要留還是拿掉** | **未定，且會決定 §1.7 F1–F4 的修法**。技術上「拿掉、全跟系統」淨減程式碼且三條通道收斂成一條；保留則須新增 `AppLocale`。取捨點是產品面：攤商會不會有「手機英文但想用中文介面」的需求 |
| 9 | **場次名稱在有交易後要不要比照幣別鎖起來** | **未定**。目前唯一沒鎖的編輯欄位（見 §4.1.1）。暫定**維持可改** —— 場次名不影響金額或歸屬，且歷史交易已有名稱快照。若要鎖，一行 `.disabled(viewModel.isEditingWithTransaction)` 即可 |

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
| 1 | 2026-09-15 | D 多重折扣（§6） | `AppliedDiscount` 結構<br>`TransactionModel.appliedDiscounts` | `CDTransactionEntity.appliedDiscountsData: Binary` | 流水帳 | `TransactionModel.toFirestoreData` 加 `appliedDiscounts`（JSON 陣列）<br>舊的 `discountType` / `discountValue` **已於第 3 批從 CoreData 移除**，重建同步時不會再看到它們 | ⬜ 未接 |
| 2 | 待填 | E 攤提（§7） | `SummaryItemModel` 加 5 欄：<br>`originalSubtotal`、`allocatedDiscount`、`actualRevenue`、`bundleId`、`bundleName` | 在 `CDTransactionEntity.itemsData` 內（跟著走） | 流水帳 | `SummaryItemModel.toFirestoreData` 加這 5 欄 | ⬜ 未接 |
| 3 | 待填 | F 組合套餐（§8） | `BundleModel`、`BundleMode` | `CDEventEntity.bundlesData: Binary` | 文件（跟 Event 走） | `EventModel.toFirestoreData` 加 `bundles`（JSON 陣列）<br>**不需要新 collection** | ⬜ 未接 |
| 4 | 待填 | F 組合套餐（§8.5） | `InventoryChangeModel.bundleId`<br>`InventoryChangeModel.bundleName` | `CDInventoryChangeEntity` 新欄位 | 流水帳 | `InventoryChangeModel.toFirestoreData` 加這 2 欄 | ⬜ 未接 |
| 5 | 2026-09-12 | 同步架構補正 | `updatedAt` | `CDTransactionEntity`<br>`CDInventoryChangeEntity` | 流水帳 | **CoreData 欄位已於第 1.11 批加好**（本機時間，由 `markPendingSync()` 自動偵測並設定）。同步時只需在 `toFirestoreData` 改寫為 `serverTimestamp()`。見 `SYNC_ARCHITECTURE_V2.md` §6.2 | 🟡 已提前 |
| 6 | 2026-09-12 | 第 1.11 批 | `CDInventoryChangeEntity.product` relationship<br>+ `CDProductEntity.inventoryChanges` inverse（Cascade） | CoreData relationship | 流水帳 | **純本機 relationship，不上傳**。建立點已接好（`InventoryChangeRepository.addChange/addChanges`、`EventRepository.duplicateEvent`） | 🟡 已提前 |
| 7 | 2026-09-12 | 第 1.10 批（A7） | **移除** `CDProductEntity.categoryName` / `ProductModel.categoryName` | — | 文件 | 重建 `ProductModel.toFirestoreData` 時**不要**再寫這個欄位；類別名稱一律從 relationship 查 | 🟡 已提前 |
| 8 | | | | | | | |

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
| 2026-09-12 | 第 0 批完成（0.1 刪 `MoneyHelper` 兩個 dead method、0.2 日曆改用共用 `DateFormatter` 並新增 `monthDayWeekday`）；新增 §1.7 本地化查核 F1–F4（查核總數 24 → 28）與 §13 待確認第 8 項 —— 本輪只登記不改碼 |
| 2026-09-12 | 第 1 批完成（1.1–1.11 全部）：新增 `TransactionIndex`／`EventDataSource`／`DiscountCalculator`／`CSVExporter`／`ProductAvailability`／`PendingSyncStamp` 六個共用元件；刪除 `updateRelatedTransactions`、`Product.categoryName`、`disabledInstead`、結帳鏈的死 `@Binding` 寫回；CoreData 補 `updatedAt` ×2 與 `InventoryChange↔Product` relationship。差異說明與靜態驗收見 §11 第 1 批 |
| 2026-09-13 | §11 每一批下方新增專屬「測試」區：自動（指令驗證／單元測試）與手動分開列點，逐項對應該批的每個改動，並標註 §12 的對應編號；§11、§12 開頭互加說明避免兩份清單漂移 |
| 2026-09-13 | 複查編輯限制後修正三處敘述：<br>① §1.1 新增「A1 的可達性」—— 有交易的商品**不能改類別**（雙重保險），A1 的分歧情境目前不可達，`TransactionIndex` 的價值改列為效能／收斂／為開放編輯鋪路<br>② §4.1.1 盤點六個編輯欄位，指出**場次名稱是唯一沒鎖的**<br>③ §11 第 1 批把做不到的手動步驟（搬類別）改成單元測試，U14 補上「場次名稱確實可改」的前置確認<br>④ §13 新增待確認第 9 項 |
| 2026-09-13 | 第 1 批單元測試補齊：新增 7 個測試檔共 72 個測試（連同既有 smoke test 共 75 個，全數通過）。過程中抓到並修正兩個真實缺陷 —— ① `DiscountCalculator.total` 未 clamp 定額折扣負值（負折扣會反而加錢）② `Persistence` 每個 container 各自載入 model 導致 `+[CDxxxEntity entity]` 取不到 entity。另把 `isAvailableForSale` 拆出純函式 `saleAvailability(in:)` 讓 fail-closed 分支可測。場次名稱依決定**維持可改**，未加限制 |
| 2026-09-15 | 第 2 批完成（2.1–2.3）：`unitPrice` → `averageUnitPrice`（D5）；商品銷售排行改成「排行 + 本期未售出摺疊區」兩區並移除 `prefix(5)`，CSV 仍是一張表；新增 `UnsoldProductData` 與 `hasSalesInRange`。順帶把兩個報表 VM 的 `loadData` 從非同步改同步（`@MainActor` 之後那層 `Task` 只是延到下一個 runloop，寫測試時才發現）並移除沒人讀的 `isLoading`。新增 12 個單元測試，總計 87 個全過 |
| 2026-09-15 | 第 3 批完成（3.1–3.4）：`TransactionModel.discountType/discountValue` → `appliedDiscounts: [AppliedDiscount]`（含 `amount` 快照），CoreData 換成 `appliedDiscountsData: Binary`；POS 折扣改成兩區 chip 各自單選、升冪、即時顯示折後金額；場次設定頁分區升冪並移除拖曳；新增 `DiscountCalculator.applied` 與 `sanitized`（寫入邊界保護）。新增 22 個單元測試，總計 109 個全過 |

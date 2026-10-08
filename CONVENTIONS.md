# Tilli 開發規範

本文件是長期維護用的規範，所有新頁面和重構都必須遵守。

---

## 資料同步規範

### 核心原則

**頁面間同步一律走 `onAppear` + Repository 重新載入。不用 Combine 轉發、不用 refreshID hack、不用 Binding 跨頁回寫。**

### 四條規則

#### 規則 1：ViewModel 用 `@StateObject` 建立，用 `@Published` 暴露狀態

每個頁面自己建 ViewModel，不從外面傳進來。

```swift
// 正確
struct POSView: View {
    @StateObject private var viewModel: ProductViewModel
    init(event: EventModel) {
        _viewModel = StateObject(wrappedValue: ProductViewModel(event: event))
    }
}

// 錯誤 — 不要從父層傳 ViewModel
struct POSView: View {
    @ObservedObject var viewModel: ProductViewModel  // 不要這樣
}
```

**例外 1：** 子元件（非獨立頁面）可以用 `@ObservedObject` 接收父層的 ViewModel。判斷標準：如果這個 View 有自己的 NavigationStack push（是獨立頁面），就用 `@StateObject`；如果只是頁面內的一個元件，就用 `@ObservedObject`。

**例外 2（場次工作區的共用資料源）：** 同一個場次底下的多個分頁（POS／庫存／報表）可以共用一個
`EventDataSource`（`ObservableObject`），由場次工作區建立後往下傳，各分頁的 ViewModel 從它取資料。

- **實作**：`Service/EventDataSource.swift`。由 `EventWorkspaceView.init` 建立一份，
  同時傳給 `InventoryViewModel` / `POSViewModel` / `ReportsViewModel`（三張報表子 VM 也共用同一份）；
  Repository 在容器的 `onAppear` 用 `attach(...)` 注入（`@EnvironmentObject` 在 `init` 取不到）。
- **ViewModel 從它取資料的方式**：在自己的 `load*()` 裡呼叫 `dataSource.reload()` 再複製快照，
  **不要**用 Combine 訂閱 `dataSource` 回推 —— 那會踩到下面「禁止 pattern」表的第一條。
  `event`／`categories`／`products` 一定**一起**更新，這是 A3 的修正重點。
- **切換篩選條件不要重載**：`ReportsViewModel` 分成 `reloadAllData(timeRange:)`（進頁面用，會查 DB）
  與 `loadAllData(timeRange:)`（只重算，純記憶體篩選）。timeRange 改變時資料沒變，不該查 DB。
- **適用範圍僅限場次工作區內**，其他頁面一律遵守規則 1 與規則 2。
- **理由**：這些分頁看的是同一份資料，各自 `onAppear` 重載會造成三個實際問題 ——
  ① 商品每次現查、類別卻來自傳入的 `event` 快照，一新一舊；
  ② 報表三個方法各自查一次 DB；
  ③ `event` 的新鮮度機制不一致（POS 用 `@Binding`、庫存用值複製 + View 層 `onChange` 補救）。
- 詳見 `FEATURE_PLAN_V1.md` §1.1（A2／A3／A5）與 §2.2。

#### 規則 2：跨頁面資料同步一律走 `onAppear` + Repository 重新載入

```swift
.onAppear {
    viewModel.updateDataManagers(
        productRepository: productRepository,
        transactionDataManager: transactionDataManager
    )
    viewModel.loadData()
}
```

**不要用的 pattern：**

| 禁止 pattern | 原因 | 替代方式 |
|-------------|------|---------|
| Combine `objectWillChange.sink` 轉發子 VM | 複雜、要管理 cancellables | 頁面各自有 VM，不需轉發 |
| `@State refreshID = UUID()` 強制刷新 | hack，不直覺，難維護 | `onAppear` 重新載入 |
| `@Binding` 跨頁面層層傳遞 | 多入口時容易斷、Calendar 用 `.constant` 不會回寫 | `let event` + Repository 直接更新 |
| `onChange(of: repository.updateTrigger)` | 手動觸發器，容易遺漏 | `onAppear` 重新載入 |

#### 規則 3：Repository 層用 `@EnvironmentObject` 注入，ViewModel 在 `updateDataManagers()` 接收

Repository（`EventRepository`、`ProductRepository`、`TransactionRepository`、`InventoryChangeRepository`）在 `TilliApp.swift` 建立，透過 `.environmentObject()` 注入。

View 層在 `onAppear` 呼叫 `viewModel.updateDataManagers(...)` 把 Repository 傳給 ViewModel。

```swift
struct POSView: View {
    @EnvironmentObject var productRepository: ProductRepository
    @EnvironmentObject var transactionDataManager: TransactionRepository
    @StateObject private var viewModel: ProductViewModel

    var body: some View {
        content
            .onAppear {
                viewModel.updateDataManagers(
                    transactionDataManager: transactionDataManager,
                    productRepository: productRepository
                )
                viewModel.loadProducts()
            }
    }
}
```

#### 規則 4：頁面內即時反應用 `@Published`，跨頁面用 `onAppear` 重新載入

| 場景 | 機制 | 範例 |
|------|------|------|
| POS 加減數量 | `@Published quantities` → UI 即時更新 | 同一頁，不涉及跨頁 |
| POS 結帳完成 | `.onChange(of: checkoutCompleted)` → `loadProducts()` | 同一頁，sheet 關閉後重新載入 |
| Inventory 新增商品後回 POS | POS 的 `onAppear` → `loadProducts()` | 跨頁，NavigationStack pop 回來時觸發 |
| WorkspaceView 顯示今日營收 | `onAppear` → 從 Repository 計算 | 跨頁，pop 回來時觸發 |

### 同步流程圖

```
用戶操作 → ViewModel 方法 → Repository 寫入（CoreData）
                                    ↓
                              資料已持久化
                                    ↓
用戶導航到另一頁 → onAppear → loadData() → 從 Repository 讀取最新資料
                                    ↓
                            @Published 更新 → UI 刷新
```

### 已知取捨

- **放棄即時跨頁同步：** 例如在 POS 結帳後，WorkspaceView header 的營收數字不會即時更新，要等 pop 回去 `onAppear` 才更新。但因為 NavigationStack 一次只看一頁，用戶感知不到差異。
- **每次進頁面都會重新載入：** 效能影響極小，因為都是 CoreData 本地查詢（毫秒級）。

---

## 共用計算元件：不要再各自實作

以下計算各自只有**一份實作**，新程式碼一律呼叫它們，不要在 ViewModel／View 裡重寫。
（2026-09-12 第 1 批建立，來源見 `FEATURE_PLAN_V1.md` §2）

| 元件 | 位置 | 取代了什麼 | 不准再出現 |
|------|------|-----------|-----------|
| `TransactionIndex` | `Service/` | 5 個各自全表掃描的 `hasTransaction` | 自己寫迴圈找 `transaction.items` 判斷有沒有賣過 |
| `EventDataSource` | `Service/` | 各分頁自己 fetch products/transactions | 場次工作區內另外呼叫 Repository 讀資料 |
| `DiscountCalculator` | `Service/` | 8 處 `switch discountType` | `switch` 折扣型別；自己算 `value / 100` |
| `CSVExporter` | `Service/` | 9 處建檔樣板 + 假逸出 | `FileManager.default.temporaryDirectory`；`replacingOccurrences(of: ",", with: "，")` |
| `ProductModel.isAvailableForSale(in:)` | `Service/ProductAvailability.swift` | POS 的兩層停用判斷 | `categories.first(where:)?.isDisabled == false`（找不到時會靜默隱藏） |
| `[CategoryModel].active` / `.disabled` | 同上 | 5 處 `filter { !$0.isDisabled }.sorted { ... }` | 自己過濾＋排序類別 |
| `NSManagedObject.markPendingSync(at:)` | `Data/CoreData/PendingSyncStamp.swift` | 25 處 `syncStatus = "pending"` | 直接賦值 `syncStatus`／單獨設 `updatedAt` |
| `[TransactionModel].summary` / `.total` | `Service/EventDataSource.swift` | 2 種不同的加總寫法 | `reduce { $0 + $1.totalAmount }`（原生 `+` 捨入可能不同） |
| `[SummaryItemModel].subtotal` | `Model/Domain/SummaryItemModel.swift` | 3 處重複 reduce | 自己 reduce 算小計 |
| `RevenueAllocator` | `Service/` | 報表端 3 處各自按比例攤提折扣（2026-10-08 第 4 批） | 報表裡用 `item.total / subtotal` 算比例；報表讀 `appliedDiscounts` 重算每項折扣 —— 一律讀 `item.actualRevenue`／`item.allocatedDiscount` |

### 三條原則

1. **金額一律走 `MoneyHelper`**，不要用原生 `+ - * /`（捨入行為不同）。
2. **保護要放在寫入邊界，不能依賴呼叫端記得呼叫。**
   實例：折扣的 clamp 原本只在 `POSView` 呼叫 `effectiveDiscount()` 時發生，
   換個入口（補記帳、測試資料、未來的匯入）就會把超過小計的折扣寫進流水帳，
   報表攤提算出**負營收**。現在 clamp 在兩個付款 VM 建立 `TransactionModel` 前一定執行。
3. **守衛只准拒絕，不准偷偷做別的事。**
   `deleteProduct` 原本在有交易時靜默改成「停用」並回報成功，呼叫端以為刪掉了。
   現在一律回 `.failed(...)`；`ProductDeletionResult.disabledInstead` 已移除。

### 歷史快照 vs 冗餘欄位

寫入流水帳的欄位分兩類，處理方式相反 —— 判斷錯會造成更新風暴或本機雲端不一致：

| 類型 | 例子 | 規則 |
|------|------|------|
| **歷史快照** | `Transaction.eventTitle`、`SummaryItem.name` / `.price` / `.category` | **永不回頭更新**。它記錄「交易當下」的事實，場次改名不該改變舊交易 |
| **冗餘欄位** | 原 `Product.categoryName`（已刪除） | **不該存在**。顯示時從 relationship 現查；留著就得維護，改一次類別名會讓該類別所有商品重新標記 pending |

「這個類別曾經賣過東西嗎」一律用 `SummaryItem.categoryId` **快照**判斷
（`TransactionIndex.hasTransaction(categoryId:)`），不要用「該類別目前的商品清單」推算 ——
商品被搬到別的類別後，後者的答案會反過來，UI 與 repository 就會意見不合。

---

## 測試規範

`TilliTests` 是 file-system-synchronized group —— **新檔案丟進 `TilliTests/` 就會自動納入測試目標**，
不需要改 `project.pbxproj`。測試目標有 `TEST_HOST`，所以 `Bundle.main` 是 App 本體，
CoreData model 與 `Localizable.xcstrings` 都可正常載入。

### 什麼該寫單元測試

| 對象 | 寫不寫 | 理由 |
|------|--------|------|
| `Service/` 底下的純函式（折扣、索引、攤提、逸出） | ✅ **一定要** | 無相依、跑得快、是金額正確性的護欄 |
| Model 的計算屬性與陣列 extension | ✅ 要 | 同上 |
| Repository 的**守衛邏輯**（能不能刪、會不會誠實失敗） | ✅ 要 | 用 in-memory container，見下 |
| Repository 的一般 CRUD | 🤔 視情況 | 多半是 CoreData 本身的行為 |
| ViewModel 的 `@Published` 狀態流轉 | 🤔 視情況 | 需要 `@MainActor`，成本較高 |
| View 的排版 | ❌ 不寫 | 用手動測試與 `DESIGN.md` 對照 |

### 三個踩過的坑

1. **CoreData 測試要用共用的 `NSManagedObjectModel`。**
   `NSPersistentContainer(name:)` 每次都重新解析一份 model，同時存在兩份時
   `+[CDxxxEntity entity]` 會報 `Failed to find a unique match for an NSEntityDescription`。
   `PersistenceController` 已改成整個 process 共用一份，測試直接用
   `TestStore.makeInMemoryContainer()` 即可。
2. **`assertionFailure` 會讓 Debug 測試直接 trap。**
   所以「fail-closed 但留下痕跡」這種寫法要拆兩層：純判斷的函式（測試測這個）
   ＋ 外層負責 assertion 與 log。範例：`ProductModel.saleAvailability(in:)`
   與 `isAvailableForSale(in:)`。
3. **避開 `Auth.auth()`。**
   測試沒有 `FirebaseApp.configure()`，碰到 `Auth.auth().currentUser` 會出事。
   建 fixture 時直接建 `CDxxxEntity`，不要走 Repository 的 `addXxx`。

### 寫法

- 測試檔命名 `<被測型別>Tests.swift`，`final class ... : XCTestCase`
- 共用的 mock 放 `TilliTests/TestHelpers.swift`，一律用 `static func mock(...)` 帶預設值
- 一個 `func test...` 只驗一件事，名字要說出**預期行為**而不是方法名
  （`testPercentageAppliedBeforeFixedAmount` 好過 `testTotal`）
- 針對「曾經出過的 bug」的測試，在註解寫清楚**原本錯在哪**，否則之後的人會覺得多餘而刪掉

---

## UI 極簡風格規範

UI 視覺規範已統一以 [`DESIGN.md`](./DESIGN.md) 為唯一依據（single source of truth），本文件不再重複維護 token 表、元件樣式或禁止事項，避免兩份文件對同一規則寫出不同版本而互相衝突。

新建頁面／重構頁面一律對照 `DESIGN.md` 實作；舊頁面（`AddNewProductView`、`CheckoutFlowView`、`InventoryChangeView` 等）暫不改動，處理原則見 `DESIGN.md` 開頭「總覽」段落與 `RESTRUCTURE_PLAN.md`。

---

## MVVM 規則

### 核心原則

**View 只做「顯示」與「使用者輸入轉發」，所有跟商業邏輯相關的程式碼一律拆進 ViewModel。**

判斷標準很簡單：這段程式碼如果拿掉 SwiftUI，還有沒有意義？如果答案是「有」（例如金額計算、庫存是否足夠、折扣規則），就不該寫在 View 裡。

### 歸屬判斷表

| 情境 | 歸屬 | 範例 |
|------|------|------|
| 純版面／樣式 | View | `.padding(16)`、`.cornerRadius(24)`、`VStack`/`HStack` 排版 |
| 顯示已算好的狀態 | View 讀，邏輯在 VM 算 | `Text(viewModel.totalAmountText)` |
| 資料計算、加總、篩選、排序 | ViewModel | `totalAmount()`、篩選庫存 > 0 的商品 |
| 驗證規則（必填、數值上限） | ViewModel | 商品名稱不可為空、數量不可超過庫存 |
| 呼叫 Repository / API | ViewModel | `productRepository.save(...)` |
| 狀態轉換邏輯（if/switch 決定下一步行為） | ViewModel | 折扣計算、結帳流程狀態機 |
| 純 UI 狀態（跟資料/商業規則無關） | View 的 `@State` | sheet 開關、選中的 tab index |
| 純顯示格式（不含商業規則） | 可留在 View | SwiftUI 原生 `Text(date, style: .date)` |

### 規則

1. **View 裡不寫 if/switch 判斷商業規則**：像「這個折扣是否可疊加」「庫存是否足夠」這類判斷，一律是 ViewModel 的方法，View 只呼叫並顯示結果。
2. **View 不直接持有或呼叫 Repository**：Repository 一律經由 ViewModel 的 `updateDataManagers()` 注入（見「資料同步規範」規則 3），View 不可跳過 ViewModel 直接操作資料層。
3. **`@State` 只放純 UI 狀態**：sheet 開關、選中的 tab index、動畫觸發旗標這類跟商業邏輯無關的狀態，可以留在 View 的 `@State`；一旦這個狀態會影響資料或觸發商業判斷，就該搬進 ViewModel 的 `@Published`。
4. **格式化字串盡量由 ViewModel 提供成品字串**：例如金額格式化、庫存不足文案，讓 ViewModel 暴露 `totalAmountText: String` 這類已經算好的欄位，View 直接顯示，避免商業規則（貨幣符號、四捨五入方式）散落在多個 View 裡。

### 例外

- 子元件（`@ObservedObject` 接收父層 VM，見「資料同步規範」規則 1 的例外）同樣遵守以上標準：子元件內不寫商業邏輯，只轉發父層 VM 已經算好的狀態。

---

## 多語言規範

### 核心原則

**使用者看得到的文字一律走 `Localizable.xcstrings`，不直接寫中文字串。**

### Key 命名格式

lowerCamelCase，以「畫面 + 元件 + 語境」組成：

```
eventsTabTitle            → 場次
workspacePosButton        → 開始收銀
posCheckoutButton         → 結帳
inventoryEmptyMessage     → 尚未新增任何商品
```

### 中文備註規則

每個 localized key 上方必須加一行註解，標明對應的中文原文：

```swift
// 場次
Text("eventsTabTitle")

// 開始收銀
Text("workspacePosButton")

// 結帳
Text("posCheckoutButton")
```

### ViewModel 中的本地化

ViewModel 用 **`String.localized(_:)`** 回傳已本地化的成品字串，View 直接顯示：

```swift
// ViewModel
var totalAmountText: String {
    String.localized("posCheckoutTotal \(formattedAmount)")
}

// View
Text(viewModel.totalAmountText)
```

⚠️ **不要用原生的 `String(localized:)`**（少了那個點）。它走 `Bundle.main` + 系統語言，
會**繞過** `Bundle.appLocalized`，App 內切語言時那個字串不會跟著變。
正確的是 `Extensions/Bundle+AppLocalized.swift` 提供的 `String.localized(_:)`（全專案 204 處都用這個）。

純開發用文字（log、assert）不需要本地化，直接寫英文。

### 日期與數字格式：先確認吃哪一條通道

App 目前有**三條**本地化通道，各自的 locale 來源不同 —— 新增任何顯示格式前先確認你吃的是哪一條：

| 通道 | 入口 | locale 來源 | 用途 |
|------|------|------------|------|
| 1 | `.environment(\.locale, ...)`（`TilliApp:38`） | `selectedLanguage` | SwiftUI `Text(LocalizedStringKey)`、`.formatted()`、Charts 軸標籤 |
| 2 | `String.localized(_:)` | `selectedLanguage` | ViewModel 產出的字串 |
| 3 | `DateFormatter` / `Calendar` | **`Locale.current`（系統語言）** | 日期字串、星期與月份 symbols |

規則：

1. **日期字串一律走 `Extensions/DateFormatter.swift` 的 static**，不要在方法內 `DateFormatter()`
   —— 建立成本高，而且格式會散落。缺哪個格式就往那個檔案加一個 static。
2. **同一個畫面不要混用通道 1 和通道 3。** 兩者的 locale 來源不同，混用會在切語言時
   讓同一畫面出現兩種語言（實例：`SalesAnalyticsView:641` 的 Charts 軸 vs
   `SalesAnalyticsViewModel:21/25` 的日期標籤）。
3. **錢一律走 `MoneyHelper.format`**，不要用 SwiftUI 原生的 `format: .currency(...)`。
   通道 1 注入的是純語言碼 `Locale(identifier: "zh-Hant")`，`region` 與 `currency` 都是 `nil`，
   原生幣別格式會印出 `XXX 1,234.50`。
4. **機器可讀的欄位**（CSV 日期欄、匯出檔名）不該跟著顯示語言跑，用固定數字 pattern
   （`isoDate`、`fileTimestamp`）。

> ⚠️ 通道 3 不跟隨 App 語言是**已知未解問題**，登記在
> `FEATURE_PLAN_V1.md` §1.7（F1–F4）。修法取決於「App 內語言切換要留還是拿掉」這個
> 尚未決定的產品問題（§13 待確認第 8 項），**決定之前不要自己加 locale 抽象** —— 若決定拿掉
> 語言切換，`Locale.current` 就是正解，那層抽象是確定要刪的鷹架。

---

## ViewModel 命名規範

**規則：`XxxView` ↔ `XxxViewModel`，檔案與 View 放在同名的頁面資料夾。**

目前 15 個 View 與 15 個 ViewModel 完全一對一（2026-09-12 核對）：

| 頁面資料夾 | View | ViewModel |
|-----------|------|-----------|
| `EventsPage/` | EventsView、AddEventView、EventsCalendarView | EventsViewModel、AddEventViewModel、EventsCalendarViewModel |
| | EventWorkspaceView | 無（純導覽容器） |
| `POSPage/` | POSView、CashPaymentView、EPaymentView、CheckoutSummaryView | POSViewModel、CashPaymentViewModel、EPaymentViewModel、CheckoutSummaryViewModel |
| | CheckoutFlowView | 無（純流程容器） |
| `InventoryPage/` | InventoryView、AddNewProductView | InventoryViewModel、AddNewProductViewModel |
| `ReportsPage/` | ReportsView、ProductPerformanceView、SalesAnalyticsView、TransactionHistoryView | ReportsViewModel、ProductPerformanceViewModel、SalesAnalyticsViewModel、TransactionHistoryViewModel |
| | ReportTimeRangeSelector、ProductPerformanceComponents | 無（子元件） |
| `MyPage/` | ProfileEditView、QRCodeView | ProfileEditViewModel、QRCodeViewModel |
| | MyView、SignInView、TilliProSheetView | 無 |
| `Root/` | RootTabView | 無 |

---

## 檔案標頭規範

所有 `.swift` 檔案開頭都必須保留標準標頭註解，包含 Claude 建立的檔案：

```swift
//
//  EventsViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/16.
//
```

- `Created by` 一律寫 `Peiyun`，日期用建立當天的 `yyyy/M/d` 格式。
- 不加 `import` 以外的其他前綴內容。

---

## 檔案組織規範

> 2026-09-12 全面整理過，以下是**實際結構**，新建檔案請照這裡放。

```
Tilli/
├── TilliApp.swift
│
├── Data/                       資料層
│   ├── CoreData/               Persistence、SyncStatus
│   │   └── Entities/           CDxxxEntity+CoreDataClass / +CoreDataProperties
│   ├── Repositories/           單一 entity 的 CRUD（Event / Product / InventoryChange /
│   │                           Transaction / QRCode / User）
│   ├── Local/                  跨 entity 的本機批次操作（LocalDataManager）
│   └── Auth/                   AuthenticationManager
│
├── Model/
│   ├── Domain/                 業務模型（EventModel、ProductModel…）
│   └── Analytics/              報表的【輸出】結構（ProductPerformanceData…）
│
├── Service/                    無狀態的計算單元
│   └── Analytics/              報表的【計算】累加器（ProductSalesStats…）
│
├── Utilities/
│   ├── Helpers/                MoneyHelper、TextHelper、DateValidationHelper、
│   │                           ImageProcessor、NetworkMonitor
│   ├── DesignSystem.swift
│   └── TestDataGenerator.swift
│
├── Extensions/                 Bundle / DateFormatter / JSONEncoder / UIApplication
│
├── View/
│   ├── Root/                   RootTabView（App 根視圖）
│   ├── Components/             跨頁面可重用元件（EntityImageView、EmptyStateView、
│   │                           EventCardView、FloatingActionButton、CustomImagePicker、
│   │                           ActivityViewController）
│   ├── EventsPage/  POSPage/  InventoryPage/  ReportsPage/  MyPage/
│
└── ViewModel/                  ⭐ 比照 View 分組，同名資料夾
    └── EventsPage/  POSPage/  InventoryPage/  ReportsPage/  MyPage/
```

### 放置判斷

| 要放什麼 | 放哪 |
|---------|------|
| 某個 entity 的 CRUD | `Data/Repositories/` |
| 跨 entity 的本機操作（清除、歸戶） | `Data/Local/` |
| 無狀態的計算（折扣、攤提、索引） | `Service/` |
| 報表的輸入／輸出結構 | `Model/Analytics/` |
| 純函式工具（金額、文字、圖片、日期） | `Utilities/Helpers/` |
| 只有一個頁面用的 View | `View/<該頁>Page/` |
| 兩個以上頁面用的 View | `View/Components/` |
| ViewModel | `ViewModel/<對應頁>Page/` |

### 命名

- Repository 管單一 entity，命名 `XxxRepository`；跨 entity 或非 CRUD 的用 `XxxManager`，且**不要放在 `Repositories/`**
- View ↔ ViewModel 同名：`XxxView` ↔ `XxxViewModel`
- ⚠️ **不要用實作細節當名字。** 例：原 `SyncableImageView` 在同步層移除後名稱就失效了，已改名 `EntityImageView`

### ⚠️ 判斷「檔案是否可刪」的注意事項

不能只 grep 型別名稱 —— **一個檔案可能匯出不帶自己名字的 API**。

實例：`ActivityViewController.swift` 用型別名搜尋看起來零使用，但它同時定義了
`extension View { func shareSheet(...) }` 與 `extension UIActivity.ActivityType { defaultExcludedTypes }`，
`ReportsView` 正在用。刪掉會直接編譯失敗。

**刪檔前請列出該檔所有頂層宣告，逐一確認：**

```bash
grep -nE "^(struct|class|enum|extension|protocol|func|var|let) " <file>
```

---

## 版本記錄

| 日期 | 變更 |
|------|------|
| 2026-09-12 | 全面對照實際程式碼更新：<br>① 規則 1 新增「例外 2：場次工作區的共用資料源」（`EventDataSource`）<br>② 刪除「要移除的舊 pattern」表（4 個項目指向的檔案都已在 `_Deprecated/`）<br>③ ViewModel 命名規範改為實際的 15 組 View↔ViewModel 對應<br>④ 檔案組織規範改寫為實際結構，新增放置判斷表、命名規則、「判斷檔案是否可刪」的注意事項 |
| 2026-09-12 | 多語言規範修正與擴充：<br>① 修正文件漂移 —— 原本寫 `String(localized:)`，實際應為 `String.localized(_:)`（原生 init 會繞過 `Bundle.appLocalized`）<br>② 新增「日期與數字格式：先確認吃哪一條通道」一節（三通道對照表 + 4 條規則），並標注通道 3 不跟隨 App 語言是已知未解問題（`FEATURE_PLAN_V1.md` §1.7） |
| 2026-09-12 | 第 1 批落地後補規範：<br>① 規則 1 例外 2 補上 `EventDataSource` 的實際位置、注入方式、「用 `load*()` 複製快照而非 Combine 訂閱」、「切換篩選條件不重載」<br>② 新增「共用計算元件：不要再各自實作」一節（9 個元件對照表 + 三條原則 + 歷史快照 vs 冗餘欄位的判斷規則） |
| 2026-09-13 | 新增「測試規範」一節：`TilliTests` 是 synchronized group（丟檔即納入）、什麼該寫單元測試的判斷表、三個踩過的坑（共用 `NSManagedObjectModel`／`assertionFailure` 會 trap 測試／避開 `Auth.auth()`）、命名與寫法 |
| 2026-10-08 | 「共用計算元件」表新增 `RevenueAllocator`（第 4 批）：攤提在付款 VM 寫入流水帳前完成，報表只加總 |

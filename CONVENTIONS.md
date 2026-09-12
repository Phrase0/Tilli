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

ViewModel 用 `String(localized:)` 回傳已本地化的成品字串，View 直接顯示：

```swift
// ViewModel
var totalAmountText: String {
    String(localized: "posCheckoutTotal \(formattedAmount)")
}

// View
Text(viewModel.totalAmountText)
```

純開發用文字（log、assert）不需要本地化，直接寫英文。

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

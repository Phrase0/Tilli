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
    init(session: SessionModel) {
        _viewModel = StateObject(wrappedValue: ProductViewModel(session: session))
    }
}

// 錯誤 — 不要從父層傳 ViewModel
struct POSView: View {
    @ObservedObject var viewModel: ProductViewModel  // 不要這樣
}
```

**例外：** 子元件（非獨立頁面）可以用 `@ObservedObject` 接收父層的 ViewModel。判斷標準：如果這個 View 有自己的 NavigationStack push（是獨立頁面），就用 `@StateObject`；如果只是頁面內的一個元件，就用 `@ObservedObject`。

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
| `@Binding` 跨頁面層層傳遞 | 多入口時容易斷、Calendar 用 `.constant` 不會回寫 | `let session` + Repository 直接更新 |
| `onChange(of: repository.updateTrigger)` | 手動觸發器，容易遺漏 | `onAppear` 重新載入 |

#### 規則 3：Repository 層用 `@EnvironmentObject` 注入，ViewModel 在 `updateDataManagers()` 接收

Repository（`SessionRepository`、`ProductRepository`、`TransactionRepository`、`InventoryChangeRepository`）在 `TilliApp.swift` 建立，透過 `.environmentObject()` 注入。

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

## 要移除的舊 pattern（重構時處理）

| 舊 pattern | 所在檔案 | 替代方式 | 處理斷點 |
|-----------|---------|---------|---------|
| `SessionDetailViewModel` 的 Combine `sink` 轉發 | `SessionDetailViewModel.swift` | POSView/InventoryView 各自有獨立 VM | 斷點 6、7 |
| `CalendarView` 的 `refreshID = UUID()` | `CalendarView.swift` | `onAppear` 重新載入 | 斷點 4 |
| `@Binding var session` 層層傳遞 | `SessionDetailView`, `ProductViewModel` | `let session` + Repository 直接更新 | 斷點 5 |
| `onChange(of: transactionUpdateTrigger)` | `CalendarView.swift` | `onAppear` 重新載入 | 斷點 4 |

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

| 頁面 | ViewModel | 檔案名 |
|------|-----------|--------|
| EventsView | EventsViewModel | EventsViewModel.swift |
| POSView | ProductViewModel (沿用) | ProductDetailViewModel.swift (沿用) |
| InventoryView | ProductViewModel (沿用，獨立 instance) | ProductDetailViewModel.swift (沿用) |
| ReportsView | ReportsViewModel (新建) | ReportsViewModel.swift |
| WorkspaceView | 無 ViewModel | — |
| MyView | 無 ViewModel | — |

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

新建檔案放在以下目錄：

```
Tilli/View/
├── EventsPage/
│   ├── EventsView.swift
│   └── WorkspaceView.swift
├── POSPage/
│   └── POSView.swift
├── InventoryPage/          ← 沿用現有目錄
│   ├── InventoryView.swift ← 新建
│   ├── InventoryChangeView.swift  ← 沿用
│   └── InventoryChangeViewModel.swift
├── ReportsPage/
│   └── ReportsView.swift
├── MyPage/
│   └── MyView.swift
├── SessionPage/            ← 保留，斷點 9 確認後可清理
├── CalendarPage/           ← 保留，斷點 9 確認後可清理
└── ...

Tilli/ViewModel/
├── EventsViewModel.swift   ← 新建
├── ReportsViewModel.swift  ← 新建
└── ...                     ← 其他沿用
```

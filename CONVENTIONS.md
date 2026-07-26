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

### 設計 Token

| Token | 值 | 說明 |
|-------|---|------|
| 圓角 | 24px | 卡片、按鈕、圖片 |
| 小圓角 | 12px | 標籤、小按鈕 |
| 間距 | 8 / 12 / 16 / 24 | 固定四級間距，不使用其他值 |
| 字型 Title 1 | `.system(size: 28, weight: .bold)` | 頁面標題 |
| 字型 Title 2 | `.system(size: 22, weight: .semibold)` | 區塊標題 |
| 字型 Body | `.system(size: 16, weight: .regular)` | 正文 |
| 字型 Caption | `.system(size: 12, weight: .regular)` | 輔助說明 |
| 圖標 | SF Symbols (Outline style) | 不用 `.fill` 變體，除非表示選中狀態 |
| 主色 | `.primary` / `.secondary` | 黑白灰為主 |
| 強調色 | `.blue` | 可互動元素、選中狀態 |
| 背景 | `Color(.systemGroupedBackground)` | 頁面底色 |
| 卡片背景 | `Color(.systemBackground)` | 白色卡片 |

### 卡片樣式

```swift
// 標準卡片
.padding(16)
.background(Color(.systemBackground))
.cornerRadius(24)
.shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
```

### 按鈕樣式

```swift
// 主要按鈕（CTA）
Text("結帳")
    .font(.system(size: 16, weight: .semibold))
    .foregroundColor(.white)
    .frame(maxWidth: .infinity)
    .padding(.vertical, 16)
    .background(Color.primary)  // 黑色
    .cornerRadius(24)

// 次要按鈕
Text("取消")
    .font(.system(size: 16, weight: .medium))
    .foregroundColor(.primary)
    .frame(maxWidth: .infinity)
    .padding(.vertical, 16)
    .background(Color(.systemGray6))
    .cornerRadius(24)
```

### WorkspaceView 大按鈕樣式

```swift
// 參考圖 2 的 dashboard 按鈕風格
VStack(spacing: 8) {
    Image(systemName: "cart")
        .font(.system(size: 28))
        .foregroundColor(.primary)
    Text("開始收銀")
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(.primary)
    Text("(POS)")
        .font(.system(size: 12))
        .foregroundColor(.secondary)
}
.frame(maxWidth: .infinity)
.padding(.vertical, 24)
.background(Color(.systemBackground))
.cornerRadius(24)
.shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
```

### 禁止事項

| 禁止 | 替代 |
|------|------|
| 使用 `.blue` 作為按鈕背景 | 用 `Color.primary`（黑色）或 `Color(.systemGray6)`（灰色） |
| 彩色圖標（除狀態指示外） | SF Symbols Outline，顏色用 `.primary` 或 `.secondary` |
| 分隔線 `Divider()` 大量使用 | 用間距和背景色區分區塊 |
| 陰影 > `opacity(0.1)` | 保持 `opacity(0.05)`，極淡 |
| 自定義字型大小（不在 token 表中） | 只用 28 / 22 / 16 / 12 四種 |
| 圓角不在 24 / 12 兩種之內 | 只用這兩種 |

### 適用範圍

- **本次重構新建的頁面**：`RootTabView`、`EventsView`、`WorkspaceView`、`POSView`、`InventoryView`、`ReportsView`、`MyView` → 直接套用
- **沿用的舊頁面**：`AddNewProductView`、`CheckoutFlowView`、`InventoryChangeView` 等 → 暫不改動，之後獨立處理
- **新建頁面中嵌入的舊元件**：如 `TransactionHistoryView` 嵌入 `ReportsView` → 暫時保持舊樣式，不影響功能

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

# Tilli 架構重構計畫

## 目標架構

```
RootTabView (2 tabs)
│
├── Tab 0: EventsView (場次)
│   ├── Segmented Control: List / Calendar
│   ├── List 模式 → 場次卡片列表 (原 EventsView 邏輯)
│   ├── Calendar 模式 → 日曆格子 + 當日場次列表 (原 CalendarView 邏輯)
│   ├── toolbar [+] → EventEditorSheet (原 AddEventView，用 sheet 呈現)
│   └── 點擊場次卡片 → NavigationLink →
│       WorkspaceView (原 EventDetailView 改造)
│       ├── Header: 場次名稱 + 日期 + 今日營收 + 訂單數
│       ├── 三個按鈕 (NavigationLink):
│       │   ├── 開始收銀 (POS) → POSView (原 ProductDetailView，移除編輯/新增功能)
│       │   ├── 管理商品 (Inventory) → InventoryView (新頁面，含商品列表+新增+編輯+庫存調整)
│       │   └── 查看報表 (Reports) → ReportsView (整合交易明細+產品績效+銷售分析)
│       └── Action Sheet: 編輯場次 / 複製場次 / 刪除場次
│
└── Tab 1: MyView (我的)
    ├── 用戶資訊卡片 (未登入 → 登入按鈕 / 已登入 → 顯示資訊)
    ├── 會員方案 → TilliProSheetView
    ├── QRCode 設定 → MerchantQRCodeView
    ├── 設定 (語言/計算機/深色模式/通知) → 直接在頁面內顯示
    └── 登出 / 登入按鈕
```

---

## 設計決策紀錄

### Q1: EventsView 的 List / Calendar 共用 ViewModel

**決策：建立新的 `EventsViewModel`，內部組合兩個子 ViewModel。**

理由：
- `EventViewModel` 管理場次列表的搜尋、排序、選取、刪除、複製
- `CalendarViewModel` 管理日曆的月份切換、日期選擇、場次指示器
- 兩者的資料來源都是同一個 `EventRepository.events`，不需要各自 fetch
- 但各自的 UI 狀態（搜尋文字、選中日期、月份等）完全不同，不應混在一起

實作方式：
```swift
class EventsViewModel: ObservableObject {
    @Published var displayMode: DisplayMode = .list  // .list / .calendar
    @Published var eventViewModel = EventViewModel()
    @Published var calendarViewModel = CalendarViewModel()
    // 不轉發子 ViewModel 的 objectWillChange：SwiftUI 對 @Published 持有的
    // ObservableObject 屬性，子物件變化本來就會觸發父物件的畫面更新，
    // 同 EventDetailFromCalendarViewModel 的組合方式。
    // 不要用 EventDetailViewModel 的 Combine sink 轉發（見 CONVENTIONS.md
    // 「要移除的舊 pattern」），那是要淘汰的做法，不該複製進新 ViewModel。
}
```

### Q6: 資料同步機制統一

**決策：全面統一為 `onAppear` + Repository 重新載入。**

移除的舊 pattern：Combine sink 轉發、refreshID hack、Binding 跨頁回寫、onChange trigger。

詳細規則見 → [`CONVENTIONS.md`](./CONVENTIONS.md) 的「資料同步規範」章節。

### Q2: WorkspaceView 用三個按鈕，各自 NavigationLink 到下一頁

**決策：WorkspaceView 是一個靜態 dashboard 頁，三個大按鈕用 NavigationLink 推進下一頁。**

不用 TabView、不用 SegmentedControl。

### Q3: POS 保留分類篩選，移除所有編輯功能

**決策：POSView = 現有 ProductDetailView 減去以下功能：**
- 移除 `editingProduct` binding 和相關 Menu 項目（編輯按鈕）
- 移除 `showAddProduct` binding 和 toolbar 的 + 按鈕
- 移除 `productActionContent`（下架/刪除 menu）
- 保留：分類展開/收起、list/grid 切換、清空按鈕、數量 +/-、結帳按鈕、折扣選擇

### Q4: InventoryView 沿用現有元件，POS 和 Inventory 各自獨立 ViewModel

**決策：InventoryView 組合以下現有元件：**
- 商品列表 → 從 ProductDetailView 的商品卡片提取（但不含數量 +/- 按鈕）
- 新增商品 → `AddNewProductView`
- 編輯商品 → `AddNewProductView(productToEdit:)`
- 庫存調整 → 原 `InventoryChangeView` 的邏輯
- 下架/刪除 → 原 `productActionContent`

**ViewModel 拆分決策：POSView 和 InventoryView 各自擁有獨立的 `@StateObject ProductViewModel` instance。**

理由：
- 共用 instance 在 NavigationStack push/pop 間容易出現生命週期問題（從 Inventory 返回 WorkspaceView 再進 POS 時，狀態殘留）
- 兩頁不會同時顯示（NavigationStack 是 push/pop 一次只看一頁）
- 同步方式：進入任一頁面時 `onAppear` → `loadProducts()` 從 Repository 拿最新資料即可
- 這和現有的 `InventoryChangeView` / `CalendarView` 等頁面的同步方式一致

### Q5: My 頁暫不加同步狀態，只加 QRCode 設定

**決策：MyView = 原 ProfileView + QRCode 入口。** 不新建 SyncStatusView、SettingsView、AboutView。

---

## 難點及解法

### 難點 1: EventDetailView 的 Binding<EventModel> 傳遞

**現狀：** `EventsView` 用 `$eventDataManager.events[index]` 把 Binding 傳給 `EventDetailView`，編輯後自動回寫。

**問題：** 新架構中 EventsView 有兩個入口（List / Calendar），Calendar 模式目前用 `.constant(event)` 傳給 `EventDetailFromCalendarView`，這不會回寫。

**解法：** WorkspaceView 統一接收 `EventModel`（非 Binding），內部用 `@State` 持有副本。需要回寫時透過 `EventRepository` 的方法直接更新，而非依賴 Binding。這樣兩個入口都用同一套邏輯。

具體改法：
```swift
// WorkspaceView
struct WorkspaceView: View {
    let event: EventModel  // 用 let，不用 Binding
    @EnvironmentObject var eventDataManager: EventRepository
    // 需要最新資料時從 eventDataManager.events 中查
}
```

**風險：** `ProductViewModel` 和 `EventDetailViewModel` 目前都用 `@Binding var event`。改成非 Binding 後，需要確認所有寫入 event 的地方（如結帳後更新營收）改用 Repository 方法。

**驗證方式：** 在 POSView 結帳後，回到 WorkspaceView 檢查營收數字是否更新。

### 難點 2: ProductViewModel — POS 和 Inventory 各自獨立 instance

**現狀：** `ProductViewModel` 同時負責：
1. POS 功能：數量管理 (`quantities`)、結帳計算 (`totalAmount()`)、折扣
2. 商品管理：新增/編輯/下架/刪除/復原

**問題：** POS 和 Inventory 分頁後，共用 instance 會有 NavigationStack push/pop 生命週期問題。

**解法：** 拆成獨立 instance。各自 `@StateObject` 持有自己的 `ProductViewModel`。

同步方式：
- 兩頁不會同時顯示（NavigationStack 一次只看一頁）
- 進入頁面時 `onAppear` → `loadProducts()` 從 `ProductRepository` 拿最新資料
- 結帳完成 / 商品新增編輯刪除 → 都會寫入 Repository → 下次進入另一頁時 `onAppear` 自動載入最新

具體做法：
```swift
// POSView
struct POSView: View {
    @StateObject private var productViewModel: ProductViewModel
    init(event: EventModel) {
        _productViewModel = StateObject(wrappedValue: ProductViewModel(event: .constant(event)))
    }
    var body: some View { ... }
        .onAppear { productViewModel.loadProducts() }
}

// InventoryView — 同理
struct InventoryView: View {
    @StateObject private var productViewModel: ProductViewModel
    init(event: EventModel) {
        _productViewModel = StateObject(wrappedValue: ProductViewModel(event: .constant(event)))
    }
    var body: some View { ... }
        .onAppear { productViewModel.loadProducts() }
}
```

**注意：** `ProductViewModel` 目前用 `@Binding var event`。拆開後可改為 `let event: EventModel`（配合難點 1 的 Binding 移除）。如改動範圍太大，可暫時用 `.constant(event)` 包裝。

### 難點 3: CheckoutFlowView 的 EnvironmentKey 關閉機制

**現狀：** `CheckoutFlowView` 用 `$showCheckoutSheet` 和 `$checkoutCompleted` 兩個 Binding 控制。

**問題：** 從 `EventDetailView` 搬到 `POSView` 後，這些 State 的持有者改變。

**解法：** 風險其實不大。`showCheckoutSheet` 和 `checkoutCompleted` 原本就定義在 `EventDetailView` 裡（現在會在 POSView 或其父層），sheet 的呈現邏輯不變。只要確保 `.sheet(isPresented:)` 和 `.onChange(of: checkoutCompleted)` 在同一個 View 層級即可。

**做法：** 把這兩個 `@State` 和相關 `.sheet` / `.onChange` 從 EventDetailView 搬到 POSView 內。

### 難點 4: CalendarView 場次列表的導航目標改變

**現狀：** CalendarView 的場次列表用 `NavigationLink` → `EventDetailFromCalendarView`（報表頁）。

**問題：** 新架構中，Calendar 點場次應該進 WorkspaceView（和 List 模式一樣）。

**解法：** CalendarView 的 `NavigationLink` 目標改為 `WorkspaceView`。`EventDetailFromCalendarView` 的報表功能搬到 `ReportsView`。

**注意：** `EventDetailFromCalendarView` 和 `EventDetailFromCalendarViewModel` 在重構完成後可以刪除（或保留作為 ReportsView 的參考）。

### 難點 5: InventoryTabView 廢棄後，庫存入口改變

**現狀：** `InventoryTabView` 是獨立 tab，先選場次 → 再進 `InventoryChangeView`。

**問題：** 新架構中庫存功能在 WorkspaceView > InventoryView 裡，已經在場次 context 內。

**解法：** InventoryView 直接拿到場次資訊，不需要再選場次。庫存調整入口放在 InventoryView 內（例如商品卡片的 Menu 裡加「調整庫存」，或在商品詳情頁內）。`InventoryChangeView` 的邏輯可以內嵌到 InventoryView，或保留為子頁面。

---

## 測試策略

### 專案目前沒有測試 target

在 Xcode 中需要先建立 `TilliTests` target（Unit Test Bundle），才能寫測試。

### 每個斷點需要的測試

由於是 SwiftUI + MVVM 架構，測試主要針對 **ViewModel 層** 和 **Repository 層**（UI 層用手動驗證）。

#### 應先建立的測試基礎設施

1. **建立 `TilliTests` target**（Xcode > File > New > Target > Unit Testing Bundle）
2. **建立 Mock Repository**：因為 ViewModel 依賴 `EventRepository`、`ProductRepository` 等，測試時需要 mock
3. **建立測試用 EventModel / ProductModel 工廠方法**

```swift
// TestHelpers.swift
extension EventModel {
    static func mock(
        title: String = "測試場次",
        startDate: Date = Date(),
        currency: String = "TWD"
    ) -> EventModel {
        EventModel(id: UUID(), title: title, startDate: startDate, ...)
    }
}
```

---

## 實作步驟與斷點

每個斷點都是一個可獨立編譯、可手動測試的穩定狀態。

---

### ✅ 斷點 0：建立測試基礎設施
**目標：** 能跑第一個空測試

**步驟：**
- [x] Xcode 建立 `TilliTests` target
- [x] 建立 `TestHelpers.swift`，加入 `EventModel.mock()` 和 `ProductModel.mock()` 工廠方法
- [x] 寫一個 smoke test 確認 target 能跑（`TilliSmokeTests.swift`）

**測試：**
```swift
func testSmokeTest() {
    let event = EventModel.mock()
    XCTAssertFalse(event.title.isEmpty)
}
```

**手動驗證：** Cmd+U 跑測試，全部通過。

---

### ✅ 斷點 1：建立 RootTabView（2 tabs 骨架）+ Design System + i18n 基礎
**目標：** App 啟動後顯示 2 個 tab（Events / My），各顯示 placeholder 文字；建立 Design System 常數與多語言基礎設施，讓斷點 2 之後的新頁面直接用 token 和 localized key，不寫 magic number 也不寫硬編碼中文

**步驟：**
- [x] 新建 `RootTabView.swift`
- [x] Tab 0：暫時放 `Text("Events")`
- [x] Tab 1：暫時放 `Text("My")`
- [x] 保留 `ContentView.swift` 的 auth loading 邏輯，搬到 `RootTabView`
- [x] 修改 `TilliApp.swift`：`ContentView()` → `RootTabView()`
- [x] **不刪除** `ContentView.swift`（保留備用）
- [x] **建立多語言字串目錄**：`Localizable.xcstrings`，加入 `zh-Hant`（基底語言）和 `en` 兩個 locale。斷點 2 之後所有新建頁面的使用者看得到的文字一律用 localized key，不直接寫中文字串。舊頁面暫不動。多語言命名規範見 [`CONVENTIONS.md`](./CONVENTIONS.md) 的「多語言規範」章節。
- [x] **新建 `Tilli/Utilities/DesignSystem.swift`**，把 [`DESIGN.md`](./DESIGN.md) 的 token 轉成 Swift 常數，供斷點 2 之後所有新建頁面直接引用（不再各自寫 `24`、`#8E8E93` 這種 magic number）：
   ```swift
   enum DesignSystem {
       enum Spacing {
           static let xs: CGFloat = 8
           static let sm: CGFloat = 12
           static let md: CGFloat = 16
           static let lg: CGFloat = 24
       }
       enum Radius {
           static let sm: CGFloat = 12   // 小按鈕、標籤、輸入框
           static let md: CGFloat = 24   // 卡片、主要/次要按鈕、彈出視窗
           static let pill: CGFloat = 999
       }
       enum ColorToken {
           static let ink = Color.primary            // #000000
           static let paper = Color(.systemGroupedBackground)
           static let cardSurface = Color(.systemBackground)
           static let muted = Color.secondary        // #8E8E93
           static let quietFill = Color(.systemGray6) // #E5E5EA
           static let marketGreen = Color(red: 0x34/255, green: 0xC7/255, blue: 0x59/255)
           static let alertRed = Color(.systemRed)
       }
       enum Typography {
           static let display = Font.system(size: 34, weight: .bold)
           static let title1 = Font.system(size: 28, weight: .bold)
           static let title2 = Font.system(size: 22, weight: .semibold)
           static let body = Font.system(size: 16, weight: .regular)
           static let caption = Font.system(size: 12, weight: .regular)
       }
       static let cardShadow = (color: Color.black.opacity(0.05), radius: CGFloat(2), x: CGFloat(0), y: CGFloat(1))
   }
   ```
   **禁藍原則落地**：`ColorToken` 裡刻意沒有 accent/blue 這個 case——互動與選中狀態一律用 `ColorToken.ink`，避免之後有人手滑加回 `.blue`（呼應 DESIGN.md 的 No-Blue Rule）。

**測試（手動）：**
- [x] App 啟動，看到 2 個 tab：Events / My
- [x] tab 切換正常
- [ ] auth loading spinner 仍然正常顯示
- [x] `DesignSystem` 編譯通過，可在任一 View 引用（例如暫時在 placeholder Text 上套用 `.font(DesignSystem.Typography.title1)` 驗證）
- [x] 切換裝置語言為英文，Tab 文字正確顯示 English 版本

**測試（自動）：**
```swift
func testRootTabViewHasTwoTabs() {
    // 驗證 RootTabView 能被初始化（編譯通過即可）
    let _ = RootTabView()
}
```

---

### ✅ 斷點 2：MyView 取代 Tab 1 placeholder
**目標：** Tab 1 (My) 顯示原 ProfileView 的所有功能 + QRCode 入口

**步驟：**
- [x] 新建 `MyView.swift`（`Tilli/View/MyPage/MyView.swift`）
- [x] 從 `ProfileView.swift` 複製所有內容到 `MyView`
- [x] 在 `topSettingsCard` 區塊加入 QRCode 設定列（NavigationLink → `MerchantQRCodeView`）
- [x] 修改 `RootTabView`：Tab 1 用 `MyView()`

**測試（手動）：**
- [x] Tab My 顯示用戶資訊卡片
- [x] 未登入時可點擊進入登入頁
- [x] QRCode 設定列可點擊，進入 QRCode 頁面
- [x] Tilli Pro、語言、計算機、深色模式、通知 toggle 都正常
- [x] 登出按鈕正常

**測試（自動）：** 無（純 UI 重組，邏輯不變）

---

### ✅ 斷點 3：EventsView 骨架（List 模式）
**目標：** Tab 0 (Events) 顯示場次列表，功能等同原 EventsView

**步驟：**
1. 新建 `EventsView.swift`
2. 頂部加 `Picker("", selection: $displayMode)` segmented control（List / Calendar）
3. 先只實作 List 模式：直接嵌入原 `EventsView` 的列表邏輯
4. Calendar 模式暫時放 `Text("Calendar - TODO")`
5. 點擊場次暫時還是導航到 `EventDetailView`（下一個斷點才改）
6. 修改 `RootTabView`：Tab 0 用 `EventsView()`

**測試（手動）：**
- [x] Tab Events 顯示場次列表
- [x] 搜尋功能正常
- [x] 新增場次按鈕（+）正常
- [x] 點擊場次進入 EventDetailView（舊頁面，暫時保留）
- [x] 滑動操作（編輯/複製/刪除）正常
- [x] 選取模式正常
- [x] Segmented Control 可切換，Calendar 顯示 placeholder

---

### ✅ 斷點 4：EventsView 加入 Calendar 模式
**目標：** Calendar 模式正常顯示日曆和場次列表

**步驟：**
- [x] 在 `EventsView` 的 Calendar 模式嵌入原 `CalendarView` 的邏輯
- [x] Calendar 模式點擊場次，暫時還是導航到 `EventDetailView`
- [x] 建立 `EventsViewModel`，組合 `EventViewModel` + `CalendarViewModel`
- [x] 套用 Design System（移除所有藍/紫色，改用 ink/muted/marketGreen）
- [x] 所有使用者看得到的文字走 i18n（9 個新 localization keys）
- [x] 移動 `AddEventView.swift` 到 `EventsPage/` 資料夾
- [x] 移除舊 CalendarView 的 `refreshID` hack（改用 onAppear 同步）

**測試（手動）：**
- [x] 切換到 Calendar 模式，顯示日曆格子
- [x] 月份切換正常（左右箭頭 + 點擊月份標題選擇器）
- [x] 日期有場次圓點指示器
- [x] 點擊日期顯示當日場次列表
- [x] 點擊場次進入 EventDetailView
- [x] 切回 List 模式，列表狀態保持
- [x] 左右滑動切換月份正常

**測試（自動）：**
```swift
func testEventsViewModelDisplayModeToggle() {
    let vm = EventsViewModel()
    XCTAssertEqual(vm.displayMode, .list)
    vm.displayMode = .calendar
    XCTAssertEqual(vm.displayMode, .calendar)
}
```

---

### 斷點 5：WorkspaceView 骨架（三個按鈕）
**目標：** 點擊場次進入 WorkspaceView，看到場次資訊 + 三個按鈕

**步驟：**
1. 新建 `WorkspaceView.swift`
2. Header：場次名稱、日期範圍、今日營收、訂單數
3. 三個大按鈕（NavigationLink，暫時指向 placeholder）：
   - 開始收銀 (POS) → `Text("POS - TODO")`
   - 管理商品 → `Text("Inventory - TODO")`
   - 查看報表 (Reports) → `Text("Reports - TODO")`
4. 修改 `EventsView`：場次點擊導航目標從 `EventDetailView` 改為 `WorkspaceView`
5. WorkspaceView 接收 `EventModel`（非 Binding）

**測試（手動）：**
- [x] List 模式點擊場次 → 進入 WorkspaceView
- [x] Calendar 模式點擊場次 → 進入 WorkspaceView
- [x] WorkspaceView 顯示正確的場次名稱和日期
- [x] 三個按鈕可點擊，各自進入 placeholder 頁
- [x] 返回按鈕正常

**測試（自動）：**
```swift
func testWorkspaceViewInitWithEvent() {
    let event = EventModel.mock()
    let _ = WorkspaceView(event: event)
    // 編譯通過即可
}
```

---

### 斷點 6：POSView（純結帳）
**目標：** WorkspaceView > POS 按鈕進入 POSView，可正常結帳

**步驟：**
1. 新建 `POSView.swift`
2. 從 `ProductDetailView.swift` 複製商品顯示和結帳邏輯
3. 移除以下功能：
   - `editingProduct` / `showAddProduct` 相關的所有 Binding 和 State
   - 商品卡片的 Menu（編輯/下架/刪除按鈕）
   - 空狀態的「新增產品」按鈕
   - toolbar 的 + 按鈕
4. 保留以下功能：
   - 分類展開/收起
   - list/grid 布局切換
   - 數量 +/- 按鈕
   - 折扣選擇
   - 結帳按鈕 → CheckoutFlowView (sheet)
   - 結帳完成後刷新庫存
5. POSView 內部建立 `@StateObject ProductViewModel`（獨立 instance）
6. `onAppear` 呼叫 `loadProducts()` 載入最新商品資料
7. 修改 WorkspaceView 的 POS 按鈕：NavigationLink → `POSView(event: event)`

**測試（手動）：**
- [x] POS 頁面顯示商品列表（按分類分組）
- [x] 分類可展開/收起
- [x] 布局可切換 list/grid
- [x] 數量 +/- 正常，庫存上限正確
- [x] 無庫存商品灰色顯示，不可加入
- [x] 折扣選擇器正常
- [x] 結帳按鈕 → 結帳流程 → 現金/電子支付 → 完成
- [x] 結帳完成後庫存數量更新
- [x] **確認沒有** 編輯/新增/下架/刪除商品的入口
- [x] 空狀態（無商品）顯示提示文字，**沒有**「新增產品」按鈕

**測試（自動）：**
```swift
func testPOSViewHasNoEditCapability() {
    // 確認 POSView 的 init 不需要 editingProduct 或 showAddProduct
    // 編譯通過即代表這些依賴已移除
}
```

---

### 斷點 7：InventoryView（商品管理 + 庫存）
**目標：** WorkspaceView > 管理商品按鈕進入 InventoryView，可管理商品和調整庫存

**步驟：**
1. 新建 `InventoryView.swift`
2. 內部建立 `@StateObject ProductViewModel`（獨立 instance，與 POSView 各自獨立）
3. `onAppear` 呼叫 `loadProducts()` 載入最新商品資料
4. 商品列表（顯示名稱、圖片、價格、庫存數量，不含數量 +/- 按鈕）
5. toolbar + 按鈕 → NavigationLink → `AddNewProductView`（新增）
6. 商品卡片 Menu：編輯 / 調整庫存 / 下架 / 刪除
7. 編輯 → NavigationLink → `AddNewProductView(productToEdit:)`
8. 調整庫存 → NavigationLink → `InventoryChangeView`（或 sheet）
9. 下架/刪除 → 沿用原 `productActionContent` 邏輯
10. 下架商品區（可展開，含「復原」操作）
11. 修改 WorkspaceView 的管理商品按鈕：NavigationLink → `InventoryView(event: event)`

**測試（手動）：**
- [x] InventoryView 頁顯示所有商品（按分類分組）
- [x] toolbar + 按鈕可進入新增商品頁
- [x] 新增商品後回到列表，新商品出現
- [x] 商品 Menu > 編輯 → 進入編輯頁，修改後回到列表資料更新
- [x] 商品 Menu > 下架 → 商品移到下架區
- [x] 下架區 > 復原 → 商品回到正常列表
- [x] 商品 Menu > 刪除 → 確認對話框 → 刪除
- [x] 庫存調整功能正常
- [x] 在 InventoryView 新增商品後，返回 WorkspaceView 再進 POS，新商品出現在 POS 列表中（因 POS 的 onAppear 會重新 loadProducts）

---

### ✅ 斷點 8：ReportsView（報表整合）
**目標：** WorkspaceView > Reports 按鈕進入 ReportsView，顯示交易/產品/銷售報表

**步驟：**
- [x] 新建 `ReportsView.swift`（`View/ReportsPage/`）
- [x] 頂部：`ReportTimeRangeSelector`（時間範圍選擇）
- [x] 用 segmented control 切換三個子頁：交易明細 / 產品績效 / 銷售分析
- [x] 直接重用：
   - `TransactionHistoryView`
   - `ProductPerformanceView`
   - `SalesAnalyticsView`
- [x] 建立 `ReportsViewModel`（參考 `SessionDetailFromCalendarViewModel` 的組合方式）
- [x] 修改 WorkspaceView 的 Reports 按鈕：NavigationLink → `ReportsView`
- [x] 報表子頁面移至 `View/ReportsPage/` 資料夾
- [x] Design System tokens + i18n（14 個新 localization keys）
- [x] 匯出功能（CSV share sheet）完整移植

**測試（手動）：**
- [ ] Reports 頁顯示時間範圍選擇器
- [ ] 交易明細 tab：顯示交易列表，展開/收起正常
- [ ] 產品績效 tab：顯示產品銷售數據
- [ ] 銷售分析 tab：顯示圖表和數據
- [ ] 時間範圍切換後三個 tab 資料同步更新
- [ ] 導出功能正常（如有）

---

### 斷點 9：清理舊程式碼
**目標：** 移除不再使用的舊檔案和導航路徑

**步驟：**
1. 確認所有功能在新架構下正常運作
2. 從 Xcode project 移除以下檔案（不刪除檔案，先移出 target）：
   - `ContentView.swift`（已被 `RootTabView` 取代）
   - `InventoryTabView.swift`（功能已移至 `InventoryView`）
   - `InventoryTabViewModel.swift`
   - `EventDetailFromCalendarView.swift`（功能已移至 `ReportsView`）
   - `EventDetailFromCalendarViewModel.swift`
3. 確認 `EventDetailView.swift` 是否還有引用，若無也移除
4. 確認編譯通過，無 warning

**測試（手動）：**
- [ ] 編譯通過，無錯誤
- [ ] 全 app 功能走一遍：
  - Events List → 新增場次 → 進入 WorkspaceView → POS 結帳 → 返回
  - Events Calendar → 點場次 → WorkspaceView → Reports 查看
  - WorkspaceView → InventoryView → 新增/編輯/庫存調整
  - My → 登入/登出 → QRCode 設定

---

## 檔案對照表

| 新檔案 | 基於 / 來源 | 說明 |
|--------|------------|------|
| `RootTabView.swift` | `ContentView.swift` | 2 tabs，含 auth 邏輯 |
| `EventsView.swift` | `EventsView.swift` + `CalendarView.swift` | List/Calendar 合併 |
| `EventsViewModel.swift` | `EventViewModel` + `CalendarViewModel` | 組合兩個子 VM |
| `WorkspaceView.swift` | `EventDetailView.swift` | 場次 dashboard + 三按鈕 |
| `POSView.swift` | `ProductDetailView.swift` | 精簡版，純結帳 |
| `InventoryView.swift` | 新建 + 部分 `ProductDetailView` + `InventoryChangeView` | 商品管理 |
| `ReportsView.swift` | `EventDetailFromCalendarView.swift` | 報表整合 |
| `ReportsViewModel.swift` | `EventDetailFromCalendarViewModel.swift` | 報表 VM |
| `MyView.swift` | `ProfileView.swift` + QRCode 入口 | 我的頁面 |

## ViewModel 生命週期

```
RootTabView
├── EventsView
│   └── @StateObject EventsViewModel
│       ├── eventViewModel: EventViewModel (管理列表)
│       └── calendarViewModel: CalendarViewModel (管理日曆)
│
│   └── WorkspaceView (NavigationStack push)
│       ├── 無 ViewModel（只是三個按鈕的 dashboard）
│       │
│       ├── POSView (NavigationStack push)
│       │   └── @StateObject ProductViewModel (獨立 instance)
│       │       onAppear → loadProducts()
│       │
│       ├── InventoryView (NavigationStack push)
│       │   └── @StateObject ProductViewModel (獨立 instance)
│       │       onAppear → loadProducts()
│       │
│       └── ReportsView (NavigationStack push)
│           └── @StateObject ReportsViewModel
│               ├── transactionViewModel: TransactionViewModel
│               ├── productPerformanceViewModel: ProductPerformanceViewModel
│               └── salesAnalyticsViewModel: SalesAnalyticsViewModel
│
└── MyView
    └── 無專屬 ViewModel（直接用 @EnvironmentObject AuthenticationManager）
```

**關鍵：** POSView 和 InventoryView 各自獨立 `ProductViewModel` instance。同步透過 `onAppear` → `loadProducts()` 從 Repository 載入最新資料。

---

## UI 極簡風格

**策略：新建的頁面直接套用極簡風，不回頭改沒動到的舊頁面。**

詳細規範見 → [`DESIGN.md`](./DESIGN.md)（唯一依據），token 的 Swift 實作見斷點 1 新建的 `DesignSystem.swift`。

每個斷點新建的 View 直接套用，不額外增加斷點。未動到的舊頁面（如 `AddNewProductView`、`CheckoutFlowView`）留到之後獨立處理。

---

## 不在本次重構範圍

- SyncStatusView → 等 SyncManager 開發完成
- AboutView → 暫不需要
- 場次名稱改為「Events」/「場次」→ 只改 tab 名稱，內部 Model 名稱不動
- 舊頁面的極簡風格改造（`AddNewProductView`、`CheckoutFlowView` 登入頁SignInView等）→ 架構穩定後獨立進行


---

## 待刪除頁面（斷點 9 清理用）

重構完成後需移除的舊檔案，先移出 target 確認編譯通過，再刪除檔案：

| 舊檔案 | 被取代為 | 可刪除時機 |
|--------|---------|-----------|
| `ContentView.swift` | `RootTabView.swift` | 斷點 9 |
| `EventsView.swift` | `EventsView.swift`（List 模式） | 斷點 3 完成後 |
| `CalendarView.swift` | `EventsView.swift`（Calendar 模式） | 斷點 4 完成後 |
| `EventDetailView.swift` | `WorkspaceView.swift` | 斷點 5 完成後 |
| `EventDetailViewModel.swift` | 不再需要 | 斷點 5 完成後 |
| `EventDetailFromCalendarView.swift` | `ReportsView.swift` | 斷點 8 完成後 |
| `EventDetailFromCalendarViewModel.swift` | `ReportsViewModel.swift` | 斷點 8 完成後 |
| `InventoryTabView.swift` | `InventoryView.swift` | 斷點 7 完成後 |
| `InventoryTabViewModel.swift` | 不再需要 | 斷點 7 完成後 |
| `ProductDetailView.swift` | `POSView.swift` + `InventoryView.swift` | 斷點 7 完成後 |

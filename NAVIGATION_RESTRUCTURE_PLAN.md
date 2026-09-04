# Tilli 導航結構調整計畫

承接 [`RESTRUCTURE_PLAN.md`](./RESTRUCTURE_PLAN.md)（斷點 0–8 已完成）。本次調整的核心是**壓平導航層級**：移除底部雙 tab、移除 WorkspaceView 中繼頁，讓場次成為唯一入口，場次內的三項工作改用 tab 並存。

---

## 目標架構

```
RootTabView（更名保留，不再是 TabView）
└── NavigationStack
    └── EventsView「場次」                      右上 ⚙️ → push MyView
        ├── segmented control（列表 / 日曆）
        ├── 列表模式：搜尋列 + 場次分區列表        ← 搜尋列常駐於列表模式內
        ├── 日曆模式：EventsCalendarView          ← 自然不出現搜尋列
        └── FAB「+」右下（選取模式時隱藏）
            │
            └── push → EventWorkspaceView(event)
                nav bar：← 返回 ＋ 場次名稱 ＋ 右上按鈕（隨 tab 變化）
                底部 TabView：
                ├── 管理商品 → InventoryView（FAB「+」右下；右上匯出）
                ├── 開始收銀 → POSView（右上 list/grid 切換）
                └── 查看分析 → ReportsView（右上匯出）
```

**與現況的差異：**

| | 現況 | 調整後 |
|---|---|---|
| 底部 tab | 場次 / 我的（2 個） | 無（設定移至右上角） |
| 場次 → 工作區 | push WorkspaceView → 再 push 三選一 | push EventWorkspaceView（三 tab 並存） |
| 導航深度 | 場次 → Workspace → POS（3 層） | 場次 → Workspace（2 層） |
| 三頁互相切換 | pop 回 Workspace 再 push | 直接切 tab |
| 新增按鈕 | toolbar「+」 | 右下 FAB |
| 場次搜尋 | toolbar 放大鏡 toggle | 列表模式常駐 |

---

## 設計決策紀錄

### D1: 三個工作頁用「真 TabView」，不用自訂 tab bar + switch

**決策：使用 SwiftUI 原生底部 `TabView`。**

理由：自訂 tab bar 搭配 `switch` 會在每次切換時銷毀並重建子 View，`@StateObject` 跟著重建 —— **POS 的購物車會被清空**。收銀到一半切去查個庫存就得重新點一遍，體驗不可接受。原生 TabView 會保留各 tab 的 View 與狀態，這正是需要的行為。

代價是必須自己處理庫存 clamp（見 D5）與 toolbar 歸屬（見 D2）。

### D2: nav bar 的 title 與 toolbar 統一由 EventWorkspaceView 持有

**決策：三個子頁不再各自宣告 `navigationTitle` / `toolbar`，改由容器依 `selectedTab` switch 決定。**

理由：`.toolbar` 會往上冒泡到最近的 `NavigationStack`。三個 tab 各自宣告時，iOS 17 切換 tab 常出現**舊按鈕殘留或新按鈕不出現**。收斂到容器一層宣告，行為才穩定。

三頁的右上按鈕：

| Tab | 右上內容 | 現在的位置 |
|---|---|---|
| 管理商品 | 匯出 Menu（全部 / 總覽 / 明細） | `InventoryView.swift:58` |
| 開始收銀 | list / grid 切換 | `POSView.swift:44` |
| 查看分析 | 匯出 Menu | `ReportsView.swift:63` |

子頁的動作透過各自的 ViewModel 或 binding 往上接。

### D3: 進入場次的預設 tab 依場次狀態自動判斷

**決策：**

| 條件 | 預設 tab |
|---|---|
| 場次尚未有任何商品（優先判斷） | 管理商品 |
| `.upcoming`（尚未開始） | 管理商品 |
| `.ongoing`（進行中） | 開始收銀 |
| `.completed`（已結束） | 查看分析 |

理由：擺攤前備貨、擺攤中收銀、收攤後看帳，落點就是當下最可能要做的事。但商品數為 0 時，不管場次狀態為何都沒東西可收銀、沒東西可分析，一律先進管理商品——這條判斷優先於狀態判斷。

「是否有商品」用 `ProductRepository.fetchProducts(forEventId:).isEmpty` 判斷，在 `EventWorkspaceView` 的 init 或 `onAppear` 早期算出，不依賴子頁的 `ProductViewModel`（三個 tab 各自的 VM 此時都還沒建立)。

### D4: 刪除 WorkspaceView 的營收 / 訂單數卡片

**決策：整頁刪除，不搬移。**

這兩個數字在「查看分析」內已有更完整的呈現。連同 `workspaceTotalRevenue`、`workspaceTotalOrders`、`workspacePosButton`、`workspaceInventoryButton`、`workspaceReportsButton` 等 localization key 一併清除。

### D5: `loadProducts()` 之後必須 clamp `quantities`

**決策：`POSViewModel.loadProducts()` 重抓商品後，把 `quantities` 每一項夾到新的 `product.stock` 上限。**

這是本次唯一非寫不可的新邏輯，理由見「難點 1」。

### D6: MyView 改用 push 呈現

**決策：從場次頁右上角 `NavigationLink` 推進，不用 sheet。**

設定是個有多層子頁（QRCode、個人資料編輯、登入、Tilli Pro）的區域，push 的層次感較符合。

### D7: 搜尋列放在列表模式內，不放在標題下方

**決策：搜尋列位於 segmented control 之下、場次列表之上，只在列表模式渲染。**

理由：搜尋目前只過濾列表（`EventsViewModel.sortedFilteredEvents`），日曆模式吃不到。若常駐於標題下方，切到日曆時會變成一個點了沒反應的死框。放進列表模式內，日曆模式自然不出現，不必額外寫隱藏邏輯，也不必為了對稱去改 `EventsCalendarViewModel`。

---

## 難點及解法

### 難點 1: TabView 保留狀態 → 購物車數量可能超過新庫存

**現狀：** `POSViewModel.loadProducts()`（`Tilli/ViewModel/POSViewModel.swift:155`）只重抓 `products`，不碰 `quantities`。

目前不會出事，因為 pop 回 WorkspaceView 再 push 進 POS 會重建 `@StateObject`，購物車自然清空。

**問題：** 改成 tab 後 View 不再重建，於是：

> 在 POS 把 A 商品加了 5 個 → 切到「管理商品」把 A 的庫存改成 2 → 切回 POS，`onAppear` 重抓到 stock=2，但 `quantities[A]` 還是 5。

`increaseQuantity`（`POSViewModel.swift:166`）有 `current < product.stock` 的守門，但那只擋「往上加」，擋不住既有數量被回頭改小的庫存拋在後面。結帳金額與扣庫存都會錯。

**解法：** 在 `loadProducts()` 尾端加 clamp：

```swift
func loadProducts() {
    guard let productRepo = productRepository else { return }
    products = productRepo.fetchProducts(forEventId: event.id)
    categories = event.categories

    if expandedCategories.isEmpty {
        expandAllCategories()
    }

    clampQuantitiesToStock()   // 新增
}
```

`clampQuantitiesToStock()` 逐項把 `quantities[id]` 夾到對應 `product.stock`（商品已被刪除則移除該項），並記錄被調整的商品名稱，透過既有的 alert 機制告知使用者。

**驗證方式：** 見斷點 3 的手動測試。

### 難點 2: 巢狀 TabView

**現狀：** `ReportsView`（`Tilli/View/ReportsPage/ReportsView.swift:35`）內部已用 `TabView` + `PageTabViewStyle` 做三個報表子頁的左右滑動。

**問題：** 外層再包一層底部 TabView 後，會形成巢狀 TabView。

**評估：** iOS 17 的底部 TabView 預設不接受橫向滑動手勢切換 tab，理論上與內層的 page 滑動不衝突。但這個組合需要實機驗證，不能只靠 preview。

**備案：** 若確實衝突，把 ReportsView 內層改為 segmented control + `switch`（報表子頁沒有需要保留的輸入狀態，重建無妨）。

### 難點 3: 切 tab 時 `onAppear` 是否穩定觸發

**現狀：** 整套跨頁同步都靠 `onAppear` + Repository 重新載入（[`CONVENTIONS.md`](./CONVENTIONS.md) 規則 2）。

**問題：** 原本三頁是 push/pop，`onAppear` 必然觸發。改成 tab 後，依賴的是「SwiftUI TabView 切換時對進入的 tab 重發 `onAppear`」這個行為。這在 iOS 17 通常成立，但並非契約。

**備案：** 若發現不穩定，在 `EventWorkspaceView` 加 `.onChange(of: selectedTab)`，由容器統一呼叫對應子 VM 的 load 方法。這不違反規則 2 的精神（仍是「切換頁面時從 Repository 重新載入」），只是觸發點從子頁上移到容器。

### 難點 4: FAB 與底部 tab bar / 選取動作列的重疊

**三處要處理：**

1. **InventoryView 的 FAB** 位於 TabView content 內。safe area 應會自動避開 tab bar，但商品 `ScrollView` 需補 bottom padding，否則最後一張商品卡被 FAB 蓋住。
2. **EventsView 的 FAB** 沒有 tab bar 問題（底部 tab 已移除），但**選取模式**下底部會出現 `selectionActionBar`（`EventsView.swift:296`），兩者會疊在一起 → 選取模式時隱藏 FAB。
3. **EventsView 的 `.toolbar(..., for: .tabBar)`**（`EventsView.swift:114`）已無 tab bar 可隱藏，直接刪除。

### 難點 5: MyView 自帶 NavigationStack

**現狀：** `MyView`（`Tilli/View/MyPage/MyView.swift:28`）包在自己的 `NavigationStack` 裡（因為原本是獨立 tab 的根）。

**問題：** 改成被 push 之後會形成巢狀 NavigationStack，內部的 QRCode / ProfileEdit / SignIn 等 `NavigationLink` 行為會錯亂。

**解法：** 移除 `MyView` 的 `NavigationStack`，同時把第 69 行的 `.preferredColorScheme(darkModeEnabled ? .dark : .light)` 上移到 `RootTabView` —— 深色模式必須套用到整個 App，不能掛在一個子頁上。（`_Deprecated/ProfileView.swift:75` 有同樣一行，該檔已棄用，不處理。）

---

## 要動的檔案

| 檔案 | 改動 |
|---|---|
| `View/EventsPage/RootTabView.swift` | 拆掉 `TabView`，body 改為 `NavigationStack { EventsView() }`；auth loading 與新用戶 `fullScreenCover` 邏輯原封不動；接手 `preferredColorScheme` |
| `View/EventsPage/EventsView.swift` | 移除自帶 `NavigationStack`（改由 RootTabView 持有）；搜尋列移入 `listContent` 常駐；移除 `isSearching` 與放大鏡按鈕；右上改為設定入口；「+」改 FAB；刪 `.toolbar(..., for: .tabBar)` |
| `View/MyPage/MyView.swift` | 移除 `NavigationStack`；`preferredColorScheme` 上移 |
| **新增** `View/EventsPage/EventWorkspaceView.swift` | 三 tab 容器；持有 `selectedTab`、`navigationTitle`、`toolbar` |
| `View/InventoryPage/InventoryView.swift` | 「+」改 FAB；移除自訂返回鍵與 `principal` 標題；匯出 Menu 上移至容器 |
| `View/POSPage/POSView.swift` | layout 切換按鈕上移至容器 |
| `View/ReportsPage/ReportsView.swift` | 匯出 Menu 上移至容器 |
| `ViewModel/POSViewModel.swift` | 新增 `clampQuantitiesToStock()`，於 `loadProducts()` 尾端呼叫 |
| **刪除** `View/EventsPage/WorkspaceView.swift` | 連同 5 個 `workspace*` localization key |

**命名說明：** `RootTabView` 已不是 TabView，但改名會牽動 `TilliApp.swift:30` 與測試，且會讓斷點 1 的 diff 混雜重新命名雜訊。本次先保留原名，待斷點 1–4 穩定後在斷點 5 統一更名為 `RootView`。

---

## 實作步驟與斷點

每個斷點都是可獨立編譯、可手動測試的穩定狀態。

---

### 斷點 1：RootTabView 去 TabView + EventsView 改版

**目標：** App 啟動直接進場次頁，無底部 tab；搜尋常駐、新增為 FAB、右上進設定。此時點場次仍進舊的 `WorkspaceView`。

**步驟：**

1. `RootTabView`：移除 `TabView`，`mainView` 改為 `NavigationStack { EventsView() }`
2. `RootTabView`：加上 `.preferredColorScheme(darkModeEnabled ? .dark : .light)` 與對應的 `@AppStorage`
3. `MyView`：移除 `NavigationStack` 與 `preferredColorScheme`
4. `EventsView`：移除自帶 `NavigationStack`
5. `EventsView`：移除 `isSearching` state 與 toolbar 放大鏡按鈕，`searchBar` 移入 `listContent` 頂部
6. `EventsView`：toolbar trailing 改為設定入口 → `NavigationLink { MyView() }`
7. `EventsView`：移除 toolbar 的「+」，改在 `listContent` / 日曆兩種模式共用的 `ZStack` 右下加 FAB
8. `EventsView`：FAB 在 `eventsVM.isSelectionMode` 時隱藏
9. `EventsView`：刪除 `.toolbar(eventsVM.isSelectionMode ? .hidden : .visible, for: .tabBar)`

**測試（手動）：**

- [X] App 啟動直接顯示場次頁，底部無 tab bar
- [X] 列表模式：搜尋列常駐於 segmented control 下方，輸入可過濾
- [X] 日曆模式：不顯示搜尋列；切回列表，搜尋文字保持
- [X] 右下 FAB 可新增場次，sheet 正常
- [X] 長按進選取模式：FAB 消失，底部動作列正常，不重疊
- [X] 取消選取模式：FAB 回來
- [X] 右上設定 → 進入 MyView，返回鍵回場次頁
- [X] MyView 內 QRCode / 個人資料編輯 / 登入 / Tilli Pro 全部可正常進出
- [X] 深色模式 toggle 仍套用到整個 App（切回場次頁確認）
- [X] 未登入 → 登入流程正常
- [X] 新用戶 `ProfileEditView` 的 `fullScreenCover` 仍正常觸發
- [X] auth loading spinner 正常
- [X] 點場次仍能進入 WorkspaceView（本斷點不動）

**測試（自動）：**

```swift
func testRootTabViewInit() {
    let _ = RootTabView()
}
```

---

### 斷點 2：EventWorkspaceView（三 tab 容器）

**目標：** 點場次直接進三 tab 頁，三頁功能等同現況，返回鍵回場次頁。

**步驟：**

1. 新建 `EventWorkspaceView.swift`，接收 `let event: EventModel`
2. `@State selectedTab`，初始值依「是否有商品」優先、其次 `event.status` 決定（D3）
3. body：`TabView(selection:)` 包三頁，tabItem 用 `shippingbox` / `dollarsign.circle` / `chart.bar`
4. 容器層宣告 `navigationTitle(event.title)` + `navigationBarTitleDisplayMode(.inline)`
5. 容器層宣告 `toolbar`，依 `selectedTab` switch 出三種右上內容（D2）
6. `InventoryView`：移除 `navigationBarBackButtonHidden` 與自訂返回鍵、`principal` 標題、匯出 Menu
7. `POSView`：移除 layout 切換 toolbar
8. `ReportsView`：移除匯出 toolbar
9. `EventsView`：`navigationDestination` 目標改為 `EventWorkspaceView`

**測試（手動）：**

- [ ] 列表模式點場次 → 進入三 tab 頁；日曆模式點場次 → 同上
- [ ] 進行中場次落在「開始收銀」；未開始落在「管理商品」；已結束落在「查看分析」
- [ ] **場次尚無任何商品時**，不論狀態為何（含進行中、已結束），一律落在「管理商品」
- [ ] nav bar 顯示場次名稱，返回鍵回場次頁
- [ ] 三個 tab 都能點，切換流暢
- [ ] 切到「管理商品」：右上是匯出 Menu，三種匯出都正常
- [ ] 切到「開始收銀」：右上是 list/grid 切換，切換正常
- [ ] 切到「查看分析」：右上是匯出 Menu
- [ ] **反覆快速切換三個 tab**，右上按鈕每次都正確更新，無殘留、無消失（難點 2 的核心驗證）
- [ ] 「查看分析」內左右滑動切換三個報表子頁正常，不會誤觸發外層 tab 切換（難點 2）
- [ ] 各頁原有功能全數正常：商品新增/編輯/下架/刪除/庫存調整、收銀結帳全流程、三張報表

---

### 斷點 3：資料同步與 clamp

**目標：** 三個 tab 互切時資料正確同步，購物車不會超賣。

**步驟：**

1. `POSViewModel` 新增 `clampQuantitiesToStock()`，於 `loadProducts()` 尾端呼叫（D5）
2. 被夾到數量時，收集商品名稱並透過既有 alert 機制提示
3. 確認三頁的 `onAppear` 在切 tab 時都有觸發；若否，改用容器層 `.onChange(of: selectedTab)`（難點 3 備案）

**測試（手動）：**

- [ ] 商品頁改庫存 → 切收銀，商品列表顯示新庫存
- [ ] 商品頁新增商品 → 切收銀，新商品出現
- [ ] 商品頁刪除商品 → 切收銀，該商品消失
- [ ] 收銀結帳 → 切分析，交易明細出現該筆
- [ ] 收銀結帳 → 切商品頁，庫存已扣減
- [ ] **clamp 核心情境**：收銀加 A 商品 5 個 → 切商品頁把 A 庫存改為 2 → 切回收銀 → 數量被夾為 2，且有提示
- [ ] **clamp 邊界**：收銀加 A 商品 3 個 → 商品頁刪除 A → 切回收銀，A 從購物車消失，總金額正確
- [ ] 切走再切回收銀，購物車其餘數量保持不變（不該被清空）
- [ ] 分析頁的時間範圍選擇，切走再切回時保持不重置

**測試（自動）：**

```swift
func testClampQuantitiesToStock() {
    // 購物車 5 個，庫存降為 2 → 夾為 2
    // 購物車 3 個，商品被刪除 → 該項移除
    // 購物車 1 個，庫存充足 → 不變
}
```

---

### 斷點 4：清理

**步驟：**

1. 刪除 `View/EventsPage/WorkspaceView.swift`
2. 從 `Localizable.xcstrings` 移除 5 個 `workspace*` key
3. 確認編譯無 warning
4. 全流程走一遍

**測試（手動）：**

- [ ] 場次頁 → 新增場次 → 進入 → 管理商品新增 → 切收銀結帳 → 切分析看帳 → 返回
- [ ] 日曆模式 → 點場次 → 三 tab 全走一遍 → 返回
- [ ] 設定頁 → 登入 / 登出 / QRCode
- [ ] 中英文切換，新增/調整過的文字都有正確翻譯

---

### 斷點 5：`RootTabView` 更名為 `RootView`

**目標：** 檔名與型別名稱反映現況——它已經不是 TabView。放在最後做，避免前面幾個斷點的 diff 混雜大量重新命名的雜訊。

**步驟：**

1. `View/EventsPage/RootTabView.swift` → 重新命名檔案為 `View/EventsPage/RootView.swift`
2. 型別 `RootTabView` → `RootView`
3. `TilliApp.swift:30` 的 `RootTabView()` → `RootView()`
4. 檢查測試檔（`TilliSmokeTests.swift` 等）與任何殘留引用一併更新
5. 確認編譯無錯誤、無 warning

**測試（手動）：**

- [ ] App 啟動、auth 流程、場次頁、三 tab 工作區全部正常（等同斷點 1–4 的回歸）

**測試（自動）：**

- [ ] 既有測試（如 `testRootTabViewInit`）改名為 `testRootViewInit`，跑通

---

## 後續（不在本次範圍）

- 舊頁面的極簡風格改造（`AddNewProductView`、`CheckoutFlowView`、`SignInView`）
- `_Deprecated/` 資料夾的實體刪除

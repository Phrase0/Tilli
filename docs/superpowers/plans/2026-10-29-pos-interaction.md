# 收銀頁互動調整 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 收銀頁與訂單摘要改用 Uber Eats 式增減元件、底部結帳鈕顯示折扣前後金額、訂單摘要每行可增減並改成「優惠明細」。

**Architecture:** 增減的規則（加／減／展開／收合／能不能再加）全部放在 `POSViewModel`，以 `CartItemID` 同時指商品與套餐；畫面只有一個共用元件 `QuantityStepper`（收銀頁列表／格狀、訂單摘要共用）。「優惠明細」從 `TransactionDetailView` 抽成共用元件 `DiscountBreakdownView`，交易明細與訂單摘要共用同一份版面。

**Tech Stack:** SwiftUI（iOS 17.6 起）、XCTest、`Localizable.xcstrings`

**Spec:** `docs/superpowers/specs/2026-10-27-bundles-design.md` §8（畫面稿 `.superpowers/brainstorm/59563-1793090532/content/cart-pos-v3.html`）

## Global Constraints

- 使用者可見文字一律走 `Localizable.xcstrings`（lowerCamelCase key，上方註解中文原文）；英文要有翻譯。
- 金額一律走 `MoneyHelper`／`Decimal.money(currency:)`，不用原生 `+ - * /`。
- 顏色、字級、圓角、間距只用 `DesignSystem`（`ColorToken`／`Typography`／`Radius`／`Spacing`）。DESIGN.md：只有 16px（主要按鈕、卡片、照片）與 12px（小元件）兩種圓角，標籤用膠囊；警示紅只用在破壞性文字／圖示；市集綠只表示正向狀態。
- 註解只描述目前行為；前後差別記在 `FEATURE_PLAN_V1.md`（第 5 批之後新增「收銀頁互動調整」小節：差異表＋變更紀錄）。
- 兩個以上頁面用的 View 放 `View/Components/`，並登記在 `CONVENTIONS.md`「共用計算元件」表。
- View 裡的 helper 不可命名為 `tag`。
- 每個 task 結束前跑全部測試；commit 要先經使用者同意（執行時每個 task 完成後問一次，或使用者事先授權整批）。

## 使用者決定（2026-10-29）

1. **點卡片本身不加入**（商品與套餐一致），只靠 `＋`。點卡片＝收合展開中的元件；商品缺貨／套餐不可賣時點卡片跳原因提醒。
2. **收合時機**：點別的元件（換它展開）、點卡片或空白處、開始捲動 → 收合。同一時間最多一個展開。
3. 套餐、商品在格狀版的元件**疊在圖片右下角**；列表版在卡片右下。

## Review Focus

1. 數量已達可賣上限（含被套餐佔用的庫存）時 `＋` 要變灰且點了不加 —— Task 1 `testCannotIncrementProductWhenStockReservedByBundle`。
2. 訂單摘要把最後一項刪掉 → 購物車空了，摘要要自動關閉，不能停在 0 元可按付款的畫面 —— Task 1 `testRemovingLastItemEmptiesCart` ＋ Task 5 手動。
3. 展開中的商品被減到 0 → 元件回到只有 `＋`，不能殘留展開狀態，之後再加要重新展開 —— Task 1 `testDecrementToZeroCollapses`。
4. 取消組合後總計、共省、百分比折扣要即時重算（`DiscountBreakdownView` 讀即時 `pricing`）—— Task 5 手動；計算本身已由 `CartPricingTests` 涵蓋。
5. 套餐已失效（被下架）時，訂單摘要的 `＋` 不可加 —— Task 1 `testCannotIncrementUnavailableBundle`。

---

### Task 1: `POSViewModel` 增減與展開狀態

**Files:**
- Modify: `Tilli/ViewModel/POSPage/POSViewModel.swift`
- Test: `TilliTests/POSQuantityControlTests.swift`（新檔；fixture 照 `POSBundleCartTests.setUp/seed`：大福 40 庫存 2、抹茶 60 庫存 5、套餐「大福＋抹茶」90）

**Interfaces:**
- Produces:
  ```swift
  enum CartItemID: Hashable { case product(UUID), bundle(UUID) }   // 放在 POSViewModel.swift 檔頭

  // POSViewModel
  @Published private(set) var expandedItem: CartItemID?
  func quantity(of item: CartItemID) -> Int
  func canIncrement(_ item: CartItemID) -> Bool     // 商品：可賣且 BundleAvailability.remainingStock > 0；套餐：availability 為 .success
  func increment(_ item: CartItemID, expand: Bool = true)   // 商品走 increaseQuantity、套餐走 addBundle（不可加時照原本跳原因）；expand 為 true 時 expandedItem = item
  func decrement(_ item: CartItemID)                // 商品走 decreaseQuantity、套餐走 removeBundle；減到 0 且是展開中的那一項 → expandedItem = nil
  func expand(_ item: CartItemID)
  func collapseControls()                           // expandedItem = nil
  var isCartEmpty: Bool { cart.isEmpty }
  ```
  套餐的 `BundleModel` 用 `event.bundles` 依 id 查；查不到時 `canIncrement` 為 false、`increment` 不做事。`clearAllQuantities()` 也要清 `expandedItem`。

- [ ] **Step 1: 寫失敗的測試**

  - `testIncrementAddsOneAndExpandsItem`：`increment(.product(daifukuId))` → `quantity(of:) == 1`、`expandedItem == .product(daifukuId)`
  - `testIncrementWithoutExpandDoesNotChangeExpandedItem`：先 `expand(.product(matchaId))`，`increment(.product(daifukuId), expand: false)` → `expandedItem == .product(matchaId)`
  - `testExpandingAnotherItemCollapsesThePrevious`：`increment(.product(daifukuId))` 後 `increment(.bundle(teaSetId))` → `expandedItem == .bundle(teaSetId)`
  - `testDecrementToZeroCollapses`：加 1 個大福再 `decrement` → 數量 0、`expandedItem == nil`；加 2 個再減 1 → 仍展開
  - `testCannotIncrementProductWhenStockReservedByBundle`：加 1 份套餐＋1 個大福（大福庫存 2 用完）→ `canIncrement(.product(daifukuId)) == false`；`increment` 後數量仍 1
  - `testCannotIncrementUnavailableBundle`：大福單點 2 個 → `canIncrement(.bundle(teaSetId)) == false`
  - `testRemovingLastItemEmptiesCart`：加 1 份套餐再 `decrement(.bundle(teaSetId))` → `isCartEmpty`
  - `testClearAllQuantitiesCollapses`

- [ ] **Step 2: 跑測試確認失敗**

  Run: `xcodebuild test -project Tilli.xcodeproj -scheme Tilli -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TilliTests/POSQuantityControlTests`
  Expected: 編譯失敗（`CartItemID` 不存在）

- [ ] **Step 3: 依 Interfaces 實作**

- [ ] **Step 4: 跑全部測試確認通過**（同上，去掉 `-only-testing`）

- [ ] **Step 5: Commit**（經使用者同意）`收銀頁互動：POSViewModel 增減與展開狀態（CartItemID）`

---

### Task 2: 共用元件 `QuantityStepper`

**Files:**
- Create: `Tilli/View/Components/QuantityStepper.swift`
- Test: `TilliTests/QuantityStepperLayoutTests.swift`（照 `ReportTimeRangeSelectorLayoutTests` 用 `UIHostingController` 量尺寸）
- Modify: `CONVENTIONS.md`「共用計算元件」表加一列

**Interfaces:**
- Produces:
  ```swift
  struct QuantityStepper: View {
      let quantity: Int
      let isExpanded: Bool
      let canIncrement: Bool
      var trashAtOne: Bool = false          // 訂單摘要：數量 1 時 − 顯示垃圾桶
      let onIncrement: () -> Void
      let onDecrement: () -> Void
      let onExpand: () -> Void
  }
  ```
- 三種外觀（畫面稿 ①）：
  - `quantity == 0`：只有一個 28pt 圓形 `＋`。
  - `quantity > 0 && !isExpanded`：28pt 圓形，只顯示數量；點了呼叫 `onExpand`。
  - `quantity > 0 && isExpanded`：膠囊（`quietFill` 底、高 28）內「−　數量　＋」，按鈕 22pt 圓。`trashAtOne && quantity == 1` 時 − 換成 `trash` 圖示（`alertRed`，破壞性）。
- 圓形底色 `ColorToken.buttonFilled`、圖示／數字 `onButtonFilled`（深色模式也看得到）；`canIncrement == false` 時 `＋` 用 `quietFill` 底、`muted` 圖示且 `.disabled`。
- 數字用 `Typography.body` 半粗體、`monospacedDigit()`。
- 整個元件 `.contentShape(Rectangle()).onTapGesture { }` 自己吃掉點擊（停用的按鈕不攔點擊，會穿透到卡片）。
- 每個按鈕加 `accessibilityLabel`（新 key：`quantityStepperIncrease`「增加」、`quantityStepperDecrease`「減少」、`quantityStepperRemove`「移除」）。

- [ ] **Step 1: 寫失敗的測試** `testStepperStaysCompactInEveryState`：三種狀態各渲染一次，`sizeThatFits` 高度 ≤ 32、展開狀態寬度 ≤ 120（格狀卡片三欄時圖片寬約 110pt，元件不能撐破）。
- [ ] **Step 2: 跑測試確認失敗**（`-only-testing:TilliTests/QuantityStepperLayoutTests`，編譯失敗）
- [ ] **Step 3: 實作元件與字串；`CONVENTIONS.md` 登記**（「不准再出現」欄：各卡片自己畫 `minus.circle.fill`／`plus.circle.fill` 的增減列）
- [ ] **Step 4: 跑全部測試確認通過**
- [ ] **Step 5: Commit** `收銀頁互動：共用增減元件 QuantityStepper`

---

### Task 3: 收銀頁卡片換成 `QuantityStepper`、點卡片不加入、收合規則

**Files:**
- Modify: `Tilli/View/POSPage/POSView.swift`（`posProductCard`、`posGridCard`、`productListSection`；刪除 `quantityControls`）
- Modify: `Tilli/View/POSPage/POSBundleSection.swift`（`listCard`、`gridCard`、`tapCard`；刪除 `quantityControls`）

**Interfaces:**
- Consumes: Task 1 全部 API；Task 2 `QuantityStepper`。

- [ ] **Step 1: 列表卡片**：元件放卡片右下（原 `quantityControls` 位置）。`onIncrement: { viewModel.increment(id) }`、`onDecrement: { viewModel.decrement(id) }`、`onExpand: { viewModel.expand(id) }`、`isExpanded: viewModel.expandedItem == id`、`canIncrement: viewModel.canIncrement(id)`。
- [ ] **Step 2: 格狀卡片**：元件改 `.overlay(alignment: .bottomTrailing)` 疊在圖片上，內距 `Spacing.xxs`；刪除文字下方那一列。
- [ ] **Step 3: 點卡片**：一律先 `viewModel.collapseControls()`；商品缺貨 → `showOutOfStockAlert`；套餐不可賣 → 跳 `availability` 的原因（改寫 `tapCard`，不再 `addBundle`）。
- [ ] **Step 4: 點空白處與捲動收合**：`productListSection` 的內容 `VStack` 加 `.contentShape(Rectangle()).onTapGesture { viewModel.collapseControls() }`；捲動：iOS 18 起 `.onScrollPhaseChange { _, phase in if phase != .idle { collapse } }`，iOS 17 用 `.simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { _ in collapse })`（`if #available` 分開，避免 iOS 18 上 DragGesture 吃掉捲動）。
- [ ] **Step 5: 跑全部測試**；在模擬器（iPhone 17，iOS 18 以上；有 iOS 17 模擬器的話也跑一次）手動確認：列表／格狀各操作一次加→展開→點別處收合成數字圓→點數字圓再展開→減到 0 回到 `＋`；格狀圖片上的元件不擋商品名稱；缺貨商品點卡片跳提醒、`＋` 灰；開始捲動即收合。
- [ ] **Step 6: Commit** `收銀頁互動：商品與套餐卡片改用 QuantityStepper，點卡片不加入`

---

### Task 4: 底部結帳鈕顯示金額

**Files:**
- Modify: `Tilli/View/POSPage/POSView.swift`（`checkoutFooter`）
- Modify: `Tilli/Localizable.xcstrings`（`posTotalLabel` 不再使用就刪除）

- [ ] **Step 1**：拿掉「總計」那一行。結帳按鈕改成一列：左邊金額（`pricing.savings > 0` 時先放劃線的 `pricing.subtotal`，`Typography.caption`、`onButtonFilled` 70% 不透明度），接著 `pricing.total`（body 粗體）；右邊 `posCheckoutButton`（「結帳」）＋ `Image(systemName: "arrow.right")`。底色 `buttonFilled`、圓角 `Radius.md`（DESIGN.md 主要按鈕 16px，不用畫面稿的膠囊）；購物車空時維持現有的 `muted` 底且停用。垃圾桶按鈕、折扣 chip、折扣超過上限提示不動。
- [ ] **Step 2: 跑全部測試**；手動：選 10% 與 -25 時按鈕顯示「~~NT$132~~ NT$94　結帳 →」，沒折扣時只顯示總計；英文語系不截斷。
- [ ] **Step 3: Commit** `收銀頁互動：結帳鈕顯示折扣前後金額`

---

### Task 5: 共用「優惠明細」＋訂單摘要每行可增減

**Files:**
- Create: `Tilli/View/Components/DiscountBreakdownView.swift`
- Modify: `Tilli/View/ReportsPage/TransactionDetailView.swift`（`discountSection`、`amountRow`、`totalRow`、`discountLabel` 移到共用元件）
- Modify: `Tilli/View/POSPage/CheckoutSummaryView.swift`
- Modify: `CONVENTIONS.md`（登記 `DiscountBreakdownView`）

**Interfaces:**
- Consumes: Task 1 `increment(_:expand:)`、`decrement(_:)`、`canIncrement(_:)`、`isCartEmpty`；Task 2 `QuantityStepper`。
- Produces:
  ```swift
  struct DiscountBreakdownView: View {
      struct ComboLine: Identifiable { let id: UUID; let name: String; let amount: Decimal; let isCancelled: Bool }
      let subtotal: Decimal
      let comboLines: [ComboLine]
      let discounts: [AppliedDiscount]
      let total: Decimal
      let savings: Decimal
      let currency: String
      var onToggleCombo: ((UUID) -> Void)? = nil   // nil：交易明細（唯讀）；非 nil：組合行右側顯示「取消」／「恢復」
  }
  ```
  內容與現在 `TransactionDetailView.discountSection` 的卡片內容相同（小計、每條「組合優惠 X」、百分比／減額折扣、`Divider`、大字總計＋劃線小計＋「共省」）；已取消的組合行名稱劃線、`muted`、不顯示金額、按鈕為「恢復」。字串沿用 `transactionDetail*`、`checkoutComboCancel`／`checkoutComboRestore`。區塊標題「優惠明細」與外層卡片留在各頁（交易明細有 `sectionTitle`＋`card`）。

- [ ] **Step 1: 抽出 `DiscountBreakdownView`，交易明細改用它**。`TransactionBreakdown.comboLines` 轉成 `ComboLine(isCancelled: false)`。跑 `TransactionDetailView` 既有的渲染測試 `testTransactionDetailRendersBundleAndComboTransaction` 確認仍通過，交易明細畫面不變。
- [ ] **Step 2: 訂單摘要的商品列**：`itemRow` 右側改成「`QuantityStepper`（`isExpanded: true`、`trashAtOne: true`）＋行小計」；名稱下方只留單價（刪除「數量: N」，數量在元件上；`checkoutItemQuantity` 不再使用就刪除）。套餐列 `CartItemID.bundle`、商品列 `.product`，呼叫 `increment(id, expand: false)`／`decrement(id)`。
- [ ] **Step 3: 訂單摘要的總計區**：刪除現在的組合折抵區與「總計＋折扣 chip」那一行，改成 `DiscountBreakdownView`（`pricing.combos` → 未取消行、`posViewModel.cancelledCombos` → 已取消行，`onToggleCombo: posViewModel.toggleComboCancelled`），放在補記帳列與付款方式之間。補記帳、現金付款、電子支付不動。
- [ ] **Step 4: 購物車清空自動關閉**：`.onChange(of: posViewModel.isCartEmpty) { _, empty in if empty { dismiss() } }`。
- [ ] **Step 5: 跑全部測試**；手動：摘要每行 ＋/−、數量 1 時垃圾桶、刪到最後一項自動關閉回收銀頁；6 個大福＋組合「大福三個 100」→ 優惠明細出現「組合優惠 大福三個 -40」與「取消」，取消後劃線＋「恢復」、總計與百分比折扣重算、共省更新；返回收銀頁數量與摘要一致；交易明細頁外觀不變；深色模式與英文語系各看一次。
- [ ] **Step 6: Commit** `收銀頁互動：訂單摘要每行可增減、總計區改優惠明細（與交易明細共用）`

---

### Task 6: 文件

**Files:**
- Modify: `FEATURE_PLAN_V1.md`（第 5 批之後新增「收銀頁互動調整」小節：完成狀態、差異表（點卡片不加入、收合時機、結帳鈕圓角依 DESIGN.md、`DiscountBreakdownView` 共用）、手動測試清單；版本記錄加一行）
- Modify: `docs/superpowers/specs/2026-10-27-bundles-design.md` §8 標記已實作

- [ ] **Step 1: 更新文件**；跑 `python3 scripts/check_field_classification.py`（本計畫不改 CoreData，預期通過）
- [ ] **Step 2: Commit** `收銀頁互動：文件更新`

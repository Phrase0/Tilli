# 收銀頁互動修正（驗收回饋）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修正收銀頁互動驗收時發現的跳動與外觀問題：庫存被購物車用完時卡片不變灰、只淡化 ＋；組合取消／恢復版面固定並顯示「× N 組」；結帳鈕金額不截斷；交易紀錄日期分組不跳動。

**Architecture:** 「本來就沒庫存」與「被購物車用完」分開判斷：前者灰卡片＋原因（`BundleAvailability.check` 用空購物車），後者只讓 `canIncrement` 為 false。組合列（含已取消）由 `POSViewModel.comboRows` 依建立時間排好，已取消的列帶「恢復可省多少」。組數寫進交易快照 `SummaryItemModel.bundleGroupCount`。

**Tech Stack:** SwiftUI（iOS 17.6 起）、XCTest

**Spec:** 使用者 2026-10-30 驗收回饋（本文件「使用者決定」）＋ `docs/superpowers/specs/2026-10-27-bundles-design.md` §8；設計稿 https://claude.ai/artifact/6Qu56RWVvQciUJCZZN3J9v（方案 A）

## Global Constraints

- 使用者可見文字走 `Localizable.xcstrings`（中英）；金額走 `MoneyHelper`；外觀只用 `DesignSystem`。
- 註解只寫目前行為；差別記在 `FEATURE_PLAN_V1.md`「收銀頁互動調整」差異表與版本記錄。
- `SummaryItemModel` 新欄位要登記在 `ARCHITECTURE.md` §5，解碼用 `decodeIfPresent`（舊交易可讀）。
- 使用者已授權計畫內的 commit。

## 使用者決定（2026-10-30）

1. 庫存上限採**方案 A**：被購物車用完時卡片外觀不變，展開膠囊的 ＋ 淡化不可按、點了不提醒；只有庫存本來就是 0 才灰卡片＋原因。
2. 展開膠囊改**卡片白底＋淡陰影**。
3. 「共省」那一行**刪掉**（訂單摘要與交易明細）。
4. 組合列訂單摘要與交易明細都顯示「× N 組」。
5. 交易紀錄日期分組改一般 `VStack`、**不要動畫**。
6. 結帳鈕金額放不下時先拿掉劃線原價，再縮字；不可出現「…」。
7. `productsById`／`bundlesById` 重新載入時建一次存起來。
8. 不做：按鈕點擊範圍放大、點折扣 chip／結帳列收合、程式捲動收合、查看分析頁 DESIGN.md 調整。

## Review Focus

1. 單點把套餐成員用完 → 套餐卡片不灰、＋ 淡化；購物車的套餐仍可 −（Task 1 `testBundleLimitedByCartIsNotGreyedButCannotIncrement`）。
2. 管理頁庫存改 0 → 套餐卡片仍灰並顯示「「大福」缺貨」（Task 1 `testBundleWithZeroStockMemberIsGreyedRegardlessOfCart`）。
3. 取消組合後列位置不變、恢復金額正確；取消的組合讓出單位給另一個組合時兩列都在原位（Task 3 `testComboRowsKeepCreationOrderAndShowRestorableAmount`）。
4. 舊交易（沒有組數）明細仍可開、不顯示「× 組」（Task 3 `testOldComboItemsWithoutGroupCountDecode`）。
5. 結帳鈕在 320pt 寬與大金額時不截斷（Task 4 版面測試）。

---

### Task 1: 「本來就沒庫存」與「被購物車用完」分開；字典快取

**Files:** Modify `Tilli/ViewModel/POSPage/POSViewModel.swift`、`Tilli/View/POSPage/POSBundleSection.swift`；Test `TilliTests/POSQuantityControlTests.swift`

**Interfaces — Produces:**
- `func soldOutReason(of bundle: BundleModel) -> BundleUnavailableReason?`：用空 `Cart()` 跑 `BundleAvailability.check`；只有成員庫存本來就不足時非 nil（收銀頁灰卡片與原因用這個）。
- `showUnavailableAlert(for:)` 改用 `soldOutReason`。
- `productsById`／`bundlesById` 改成 `private(set) var`，在 `loadProducts()` 設定 `products`／`event` 時一起重建；行為不變。

- [ ] 寫測試 `testBundleLimitedByCartIsNotGreyedButCannotIncrement`（大福單點 2 → `soldOutReason(teaSet) == nil`、`canIncrement(.bundle) == false`）、`testBundleWithZeroStockMemberIsGreyedRegardlessOfCart`（大福庫存改 0 後 `loadProducts` → `soldOutReason == .memberOutOfStock("大福")`）、改寫 `testUnavailableBundleAlertShowsReasonOnlyWhenUnavailable` 為只在本來就缺貨時提醒；跑測試確認失敗
- [ ] 實作；`POSBundleSection.unavailableText` 改用 `soldOutReason`
- [ ] 全部測試通過 → commit

### Task 2: `QuantityStepper` 淡化 ＋、白底膠囊

**Files:** Modify `Tilli/View/Components/QuantityStepper.swift`；Test `TilliTests/QuantityStepperLayoutTests.swift`

- `canIncrement == false` 時 ＋（圓形與膠囊內）用 `quietFill` 底、`muted` 圖示、`opacity(0.55)`，`.disabled`；點了不提醒。
- 展開膠囊底色 `cardSurface`，陰影 `DesignSystem.Shadow` 的顏色、半徑 4、y 1。
- [ ] 版面測試加 `canIncrement: false` 狀態仍 ≤ 120×32；跑測試（現有元件應已通過 → 視為迴歸測試，記 ledger）
- [ ] 實作 → 全部測試 → commit

### Task 3: 組合列固定位置、「× N 組」、刪除「共省」

**Files:** Modify `Tilli/Model/Domain/SummaryItemModel.swift`、`Tilli/Service/CartPricing.swift`（`summaryItems` 寫入組數）、`Tilli/Service/TransactionBreakdown.swift`（`ComboLine.groupCount: Int?`）、`Tilli/ViewModel/POSPage/POSViewModel.swift`、`Tilli/View/Components/DiscountBreakdownView.swift`、`Tilli/View/POSPage/CheckoutSummaryView.swift`、`Tilli/View/ReportsPage/TransactionDetailView.swift`、`ARCHITECTURE.md` §5、`Localizable.xcstrings`；Test `TilliTests/POSQuantityControlTests.swift`、`TilliTests/TransactionBreakdownTests.swift`、`TilliTests/CartPricingTests.swift`

**Interfaces — Produces:**
- `SummaryItemModel.bundleGroupCount: Int?`（組合列才有，= 該組合在這筆交易套用的組數）
- `TransactionBreakdown.ComboLine.groupCount: Int?`（取該組合任一列的 `bundleGroupCount`）
- `DiscountBreakdownView.ComboLine` 增加 `groupCount: Int?`；已取消列的 `amount` = 恢復後可省金額，以刪除線顯示；刪除 `savings` 參數與「共省」行
- `POSViewModel.comboRows: [DiscountBreakdownView.ComboLine]`：已套用＋已取消的 `.chooseAny` 組合，依 `createdAt`（同時間依 id）排序；已取消列的金額與組數 = 把該組合從 `cancelledComboIds` 拿掉後重算 `CartPricing` 時它的 `deduction`／`groupCount`
- 字串 `discountBreakdownComboGroups %@ %lld`「組合優惠 %1$@ × %2$lld 組」／"Combo %1$@ × %2$lld"；`groupCount == nil` 沿用 `transactionDetailComboLine`

- [ ] 寫測試：`testComboRowsKeepCreationOrderAndShowRestorableAmount`（抹茶 2 → 組合「任選兩個」-40 × 1；取消後 `comboRows` 仍一列、`isCancelled`、amount 40、groupCount 1）、`testSummaryItemsRecordComboGroupCount`（CartPricing）、`testBreakdownComboLineCarriesGroupCount`、`testOldComboItemsWithoutGroupCountDecode`；跑測試確認失敗
- [ ] 實作；訂單摘要改用 `posViewModel.comboRows`
- [ ] 全部測試 → commit

### Task 4: 結帳鈕金額不截斷

**Files:** Modify `Tilli/View/POSPage/POSView.swift`（`checkoutButtonLabel`）；Test `TilliTests/CheckoutButtonLayoutTests.swift`

- `ViewThatFits(in: .horizontal)`：完整版（劃線原價＋總計＋結帳 →）→ 只有總計＋結帳 → → 總計 `minimumScaleFactor(0.7)`。為了可測，`checkoutButtonLabel` 抽成 `struct CheckoutButtonLabel: View { subtotal, total, savings, currency }`（`POSPage`）。
- [ ] 測試：寬 220pt、小計 NT$123,456、總計 NT$111,111 時 `sizeThatFits` 寬度 ≤ 220；跑測試確認失敗（型別不存在）
- [ ] 實作 → 全部測試 → commit

### Task 5: 交易紀錄日期分組不跳動

**Files:** Modify `Tilli/View/ReportsPage/TransactionHistoryView.swift`（有資料的 `LazyVStack` → `VStack`）、`Tilli/ViewModel/ReportsPage/TransactionHistoryViewModel.swift`（`toggleDailyGroupExpansion` 拿掉 `withAnimation`）

- [ ] 純畫面修改（無可測邏輯，ledger 記 ruling）；全部測試 → commit

### Task 6: 文件

- [ ] `FEATURE_PLAN_V1.md`「收銀頁互動調整」差異表加本次各列、手動清單補項目、版本記錄；commit

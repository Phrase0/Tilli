# 類別 chip 列（第 6 批 6.1）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 收銀頁加上固定在最上方的類別 chip 列（點選跳轉、捲動連動高亮），管理商品頁改成同一套規則與同一個共用元件。

**Architecture:** 「有哪些區塊、順序」由各頁 ViewModel 的 `sectionIDs` 單一定義，chip 列與列表本體都從它產生。「目前高亮哪個」的判定是純函式 `SectionHighlight.active(...)`（可測），輸入各區塊標題相對列表頂端的位置、是否捲到底；View 用 preference key 收集位置、保留已捲出畫面的最後位置。點 chip 後鎖定高亮，直到手指捲動（共用的 `onUserScroll` modifier）。

**Tech Stack:** SwiftUI（iOS 17.6 起）、XCTest

**Spec:** `docs/superpowers/specs/2026-11-02-category-chip-row-design.md`

## Global Constraints

- 目前高亮哪個 chip、是否鎖定、各標題位置是純 UI 狀態，放 View 的 `@State`；區塊清單在 ViewModel（View 不自己過濾類別）。
- iOS 17 必須有可用實作；iOS 18 API 只能放在 `#available` 分支。
- 外觀只用 `DesignSystem`；字串走 `Localizable.xcstrings`，`inventoryChipAll` 刪除。
- 新共用元件登記 `CONVENTIONS.md`「共用計算元件」表；與 FEATURE_PLAN §11 第 6 批原規格的差異（拿掉「全部」、隱藏條件、底部與切回分頁規則）記在 FEATURE_PLAN 第 6 批差異表。
- 註解只寫目前行為。使用者已授權計畫內的 commit。

## Review Focus

1. 最後一個區塊很短：點它的 chip 後停在列表底部，高亮不可跳回前一個；手指捲到底時高亮最後一個（Task 1 `testAtBottomHighlightsLastSection`）。
2. 管理商品頁是 `List`（懶載入），捲出畫面的標題不再回報位置 → 高亮仍要正確（Task 1 `testUsesLastKnownPositionsOfTitlesScrolledAway` ＋ Task 4 手動）。
3. 管理商品頁長按拖曳排序時，用來偵測「手指捲動」的手勢不可擋住拖曳（Task 4 手動）。
4. 回到收銀頁後類別被停用 → 原本高亮的區塊消失要回到第一個（Task 1 `testFallsBackToFirstWhenSelectionDisappears`）。
5. 只有一個區塊時不顯示 chip 列，且不影響列表捲動（Task 2／4 `testSingleSectionHidesChips`）。

---

### Task 1: 高亮判定純函式＋共用 chip 列元件＋手指捲動 modifier

**Files:**
- Create: `Tilli/View/Components/SectionChipRow.swift`
- Modify: `Tilli/View/POSPage/POSView.swift`（把私有的 `collapsesControlsOnScroll` 改用共用 `onUserScroll`）
- Test: `TilliTests/SectionHighlightTests.swift`
- Modify: `CONVENTIONS.md`

**Interfaces — Produces:**
```swift
enum SectionHighlight {
    /// 佔據列表頂端的區塊：標題 minY（相對列表頂端）≤ threshold 的區塊中排在最後者；
    /// 沒有任何標題到頂時回傳第一個；isAtBottom 時回傳最後一個；ids 空時 nil
    static func active<ID: Hashable>(ids: [ID], titleOffsets: [ID: CGFloat], isAtBottom: Bool, threshold: CGFloat = 1) -> ID?
    /// 區塊清單改變後的高亮：原本的還在就保留，否則第一個
    static func reconcile<ID: Hashable>(_ current: ID?, ids: [ID]) -> ID?
}

struct SectionChipRow<ID: Hashable>: View {
    struct Item: Identifiable { let id: ID; let title: Text }
    let items: [Item]
    let selected: ID?
    let onSelect: (ID) -> Void
    // 選中黑底白字（ink／paper）、未選 quietFill／ink、膠囊、Typography.caption、內距 sm/xs、間距 xs（同管理商品頁現況）；
    // 橫向 ScrollView，selected 改變時以 ScrollViewReader 捲到可見；不截斷名稱；高度固定
}

/// 區塊標題回報 minY（在 coordinateSpace(name:) 內）；列表結尾用 sentinel 回報 maxY 判斷是否到底
struct SectionOffsetKey: PreferenceKey  // [AnyHashable: CGFloat]，reduce 合併
extension View {
    func reportsSectionOffset<ID: Hashable>(_ id: ID, in space: String) -> some View
    /// 使用者用手指捲動時呼叫（iOS 18 onScrollPhaseChange == .interacting；iOS 17 simultaneousGesture DragGesture(minimumDistance: 10)）
    func onUserScroll(_ action: @escaping () -> Void) -> some View
}
```
- 「保留已捲出畫面的最後位置」由使用端合併：`offsets.merge(new) { _, new in new }`（不移除沒回報的 id）。

- [ ] **Step 1: 寫失敗的測試** `SectionHighlightTests`：
  - `testNoTitleAtTopHighlightsFirst`：ids [a,b,c]，offsets a:40 b:300 c:600 → a
  - `testHighlightsLastTitlePastTop`：a:-500 b:-20 c:200 → b
  - `testTitleJustBelowTopDoesNotWin`：a:-300 b:30 → a
  - `testAtBottomHighlightsLastSection`：a:-800 b:-200 c:150, isAtBottom → c
  - `testUsesLastKnownPositionsOfTitlesScrolledAway`：只有 c 在 offsets（a,b 沒回報、視為未知）且 c:-10 → c；a 未知、b:-5 → b
  - `testFallsBackToFirstWhenSelectionDisappears`：`reconcile(.b, ids:[a,c]) == a`；`reconcile(.c, ids:[a,c]) == c`；`reconcile(nil, ids:[]) == nil`
- [ ] **Step 2:** `-only-testing:TilliTests/SectionHighlightTests` → 編譯失敗
- [ ] **Step 3:** 實作上述介面；`POSView` 的捲動收合改用 `.onUserScroll { viewModel.collapseControls() }`，刪除私有 extension；`CONVENTIONS.md` 登記 `SectionChipRow`／`SectionHighlight`（「不准再出現」：各頁自己畫 chip 列、自己算哪個區塊在頂端）
- [ ] **Step 4:** 全部測試通過 → commit `6.1：高亮判定、共用 chip 列元件與手指捲動 modifier`

### Task 2: 收銀頁區塊清單（ViewModel）

**Files:** Modify `Tilli/ViewModel/POSPage/POSViewModel.swift`；Test `TilliTests/POSSectionTests.swift`（fixture 同 `POSQuantityControlTests`）

**Interfaces — Produces:**
```swift
enum POSSectionID: Hashable { case bundles, category(UUID) }
var sectionIDs: [POSSectionID]      // fixedBundles 非空時 .bundles 第一；接著 activeCategories 中 getSortedProductsForCategory 非空者
var showsSectionChips: Bool { sectionIDs.count > 1 }
func sectionTitle(_ id: POSSectionID) -> String   // 套餐：posBundleSection；類別：名稱
```
- [ ] 測試：`testBundlesComeFirstThenCategoriesWithProducts`、`testCategoryWithoutSellableProductsHasNoSection`（類別內商品全下架）、`testSingleSectionHidesChips`（無套餐＋單一類別）；跑測試確認失敗
- [ ] 實作；`POSView.productListSection` 改成依 `sectionIDs` 產生區塊（不再自己判斷 `!items.isEmpty`、`!fixedBundles.isEmpty`）
- [ ] 全部測試 → commit `6.1：收銀頁區塊清單單一定義`

### Task 3: 收銀頁 chip 列

**Files:** Modify `Tilli/View/POSPage/POSView.swift`（`POSBundleSection` 的標題列也要回報位置，可在 `POSView` 包一層）

- 結構：`VStack(spacing: 0) { if showsSectionChips { SectionChipRow }; ScrollViewReader { ScrollView { 區塊…; sentinel } } ; checkoutFooter }`；`ScrollView` 設 `coordinateSpace(name: "posList")`，每個區塊標題 `.id(sectionID)` ＋ `.reportsSectionOffset`，結尾 sentinel 回報位置；用 `GeometryReader` 取列表可視高度判斷 `isAtBottom`（sentinel minY ≤ 可視高度 + 1）。
- `@State selected: POSSectionID?`、`@State pinned = false`、`@State offsets`。preference 改變時：未鎖定才 `selected = SectionHighlight.active(...)`。點 chip：`selected = id; pinned = true; collapseControls(); withAnimation { proxy.scrollTo(id, anchor: .top) }`。`.onUserScroll { pinned = false; collapseControls() }`。`onChange(of: sectionIDs)` → `selected = SectionHighlight.reconcile(selected, ids:)`；`onAppear` 只在 `selected == nil` 時設第一個（切回分頁保留）。
- [ ] 實作；跑全部測試
- [ ] 渲染測試截圖確認列表／格狀兩種版面 chip 列與高亮外觀（臨時測試，不 commit）
- [ ] commit `6.1：收銀頁類別 chip 列（點選跳轉、捲動連動高亮）`

### Task 4: 管理商品頁改用共用元件與同一套規則

**Files:** Modify `Tilli/View/InventoryPage/InventoryView.swift`、`Tilli/ViewModel/InventoryPage/InventoryViewModel.swift`、`Localizable.xcstrings`（刪 `inventoryChipAll`）；Test `TilliTests/InventorySectionTests.swift`

**Interfaces — Produces:**
```swift
enum InventorySectionID: Hashable { case fixedBundles, comboBundles, category(UUID) }  // 取代 View 私有的 InventorySectionAnchor（刪 .top）
var sectionIDs: [InventorySectionID]   // 搜尋結果有的區塊：fixedBundles、comboBundles 非空者，接著 sortedCategories 中 getItemsForCategory 非空者
var showsSectionChips: Bool { sectionIDs.count > 1 }
```
- [ ] 測試：`testSectionsFollowVisibleBlocks`（套餐、組合、有商品的類別；空類別不列）、`testSingleSectionHidesChips`；跑測試確認失敗
- [ ] 實作：刪 View 的 `visibleCategories`、`InventorySectionAnchor`、「全部」chip 與 `.top` 錨點；`List` 設 coordinateSpace，標題列回報位置、結尾 sentinel；同 Task 3 的鎖定／reconcile 規則
- [ ] 全部測試；手動確認長按拖曳排序仍可用（`onUserScroll` 的拖曳手勢不可擋住）——若擋住，管理頁改用標題列 `onAppear` 驅動 unpin，ledger 記 ruling
- [ ] commit `6.1：管理商品頁 chip 列改用共用元件，拿掉「全部」並捲動連動高亮`

### Task 5: 文件

- [ ] `FEATURE_PLAN_V1.md` 第 6 批：完成狀態、差異表（拿掉「全部」、單一區塊隱藏、點選鎖定直到手指捲動、到底高亮最後一個、切回分頁保留、管理商品頁一起改）、手動清單改為本批實際；版本記錄；commit `6.1：文件更新`

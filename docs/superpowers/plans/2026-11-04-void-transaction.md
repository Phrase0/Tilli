# 交易作廢 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交易明細可以整筆作廢交易（必選原因與庫存回流方式、二次確認），作廢後所有營收／筆數統計排除該筆，選回流時精確加回庫存。

**Architecture:** 作廢存成獨立的流水帳實體 `CDTransactionVoidEntity`，原交易不動。「是否作廢」只由 `TransactionVoidIndex` 回答；`EventDataSource.transactions` 改為**有效交易**（報表 VM 不用改就自動排除），另提供 `allTransactions` 給交易紀錄列表與 `TransactionIndex`。場次列表／日曆走 `TransactionRepository.effectiveSummary(forEventId:)`，同樣經 `TransactionVoidIndex`。寫入內容由純函式 `VoidRecorder` 組出，明細 VM 在寫入邊界檢查後呼叫 Repository。

**Tech Stack:** SwiftUI（iOS 17.6 起）、CoreData、XCTest

**Spec:** `docs/superpowers/specs/2026-11-04-void-transaction-design.md`

## Global Constraints

- 不改 `TransactionModel`／`CDTransactionEntity` 任何欄位；原交易快照永不修改。
- 金額一律 `MoneyHelper`（`add` 等），不用原生 `+ - * /`。
- 使用者可見文字一律 `Localizable.xcstrings`（lowerCamelCase key，上方註解中文原文）；交易編號一律 `TransactionModel.displayNumber`。
- 外觀只用 `DesignSystem` token；破壞性按鈕是 quietFill 底＋alertRed 字（紅色不當底色）。
- 守衛只准拒絕，不准靜默改做別的事；保護放在寫入邊界（明細 VM），不依賴 View 的 disabled。
- 測試沒有 `FirebaseApp.configure()`：fixture 直接建 `CDxxxEntity`，不呼叫 Repository 的 `add*`（內含 `Auth.auth()`）。`assertionFailure` 外層與純判斷拆開。
- 改 CoreData model 後跑 `python3 scripts/check_field_classification.py`。
- 註解只寫目前行為；前後差別記在 `FEATURE_PLAN_V1.md`。
- commit 前要使用者同意（執行前詢問是否授權本計畫內的 commit）。

建置／測試指令：
```bash
xcodebuild -project Tilli.xcodeproj -scheme Tilli -destination 'generic/platform=iOS Simulator' build
xcodebuild test -project Tilli.xcodeproj -scheme Tilli -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TilliTests/<Class>
```

## Review Focus

1. 同一商品同時以單點與套餐成員出現在一筆交易 → 回流各一筆異動、庫存累加加回總數（Task 4 `testRestockSumsSameProductAcrossRows`）。
2. 作廢後回到交易紀錄、場次列表、日曆 → 三處筆數與總額都已排除，與查看分析一致（Task 3 `testEventsSummaryMatchesDataSourceSummary`）。
3. 作廢紀錄寫入成功但庫存寫入失敗 → 使用者看到「作廢已完成但庫存回流失敗」提示，不是靜默（Task 5 手動＋`performVoid` 回傳值）。
4. 在明細頁作廢後不離開、再進一次作廢流程 → 按鈕已消失；就算 VM 被呼叫也拒絕（Task 4 `testRejectsAlreadyVoided`、Task 5 `VoidTransactionViewModelTests.testCannotSubmitWhenAlreadyVoided`）。
5. 作廢交易的商品仍維持鎖定（不可刪、不可改類別）（Task 3 `testTransactionIndexStillCountsVoidedTransactions`）。

---

### Task 1: 資料層 — 作廢紀錄實體、模型、原因；「作廢回流」庫存原因

**Files:**
- Modify: `Tilli/Data/CoreData/Tilli.xcdatamodeld/Tilli.xcdatamodel/contents`（新增實體，無 relationship，存 `eventId`；場次刪除後比照交易保留）
- Create: `Tilli/Data/CoreData/Entities/CDTransactionVoidEntity+CoreDataClass.swift`、`…+CoreDataProperties.swift`（比照 `CDInventoryChangeEntity` 手寫 `@NSManaged`、`update(from:)`、`toModel()`）
- Create: `Tilli/Model/Domain/TransactionVoidModel.swift`
- Modify: `Tilli/Model/Domain/InventoryChangeModel.swift`
- Modify: `Tilli/Localizable.xcstrings`
- Modify: `ARCHITECTURE.md` §4、`SYNC_ARCHITECTURE_V2.md`（流水帳列表 `Transaction`、`InventoryChange` 後加 `TransactionVoid`）
- Test: `TilliTests/TransactionVoidModelTests.swift`

**Interfaces — Produces:**
```swift
enum VoidReason: String, Codable, CaseIterable {
    case inputError, customerCancelled, returned, other
    var displayName: String   // voidReasonInputError 輸入錯誤 / voidReasonCustomerCancelled 客人取消 / voidReasonReturned 退貨 / voidReasonOther 其他
}

struct TransactionVoidModel: Identifiable, Equatable {
    let id: UUID
    let transactionId: UUID
    let eventId: UUID
    let voidedAt: Date
    let reason: VoidReason
    let note: String?        // 空字串存 nil
    let restocked: Bool
}
extension TransactionVoidModel { init(entity: CDTransactionVoidEntity) }  // 不認得的 reason → .other

// CDTransactionVoidEntity 屬性：id(UUID) transactionId(UUID) eventId(UUID) voidedAt(Date) reason(String)
// note(String?) restocked(Bool, default NO) updatedAt(Date?) userId(String?) syncStatus(String?, default "synced")

enum InventoryChangeReason { …; case voidRestock }   // 顯示名 inventoryReasonVoidRestock「作廢回流」
// isIncrease 含 .voidRestock；increaseReasons / decreaseReasons / availableReasons(for:) 都不含
```
ARCHITECTURE §4 新增 `### CDTransactionVoidEntity`（資料類型：流水帳；id/transactionId/eventId = R，voidedAt/reason/note/restocked = S，updatedAt/userId = M，syncStatus = M·X，狀態「現有」）；`CDInventoryChangeEntity.transactionId` 說明改「銷售出庫與作廢回流時有值」。

- [ ] **Step 1: 寫失敗的測試**
```swift
func testEntityRoundTripKeepsAllFields()          // 建 CDTransactionVoidEntity（in-memory），toModel() 欄位全等，note "" → nil
func testUnknownReasonFallsBackToOther()
func testVoidRestockIsIncreaseButNotManuallySelectable() {
    XCTAssertTrue(InventoryChangeReason.voidRestock.isIncrease)
    XCTAssertFalse(InventoryChangeReason.increaseReasons.contains(.voidRestock))
    XCTAssertFalse(InventoryChangeReason.availableReasons(for: 5).contains(.voidRestock))
    XCTAssertEqual(InventoryChangeReason.voidRestock.displayName, String.localized("inventoryReasonVoidRestock"))
}
```
- [ ] **Step 2: 跑 `-only-testing:TilliTests/TransactionVoidModelTests`，預期編譯失敗**
- [ ] **Step 3: 實作上述介面、model XML、字串、文件**
- [ ] **Step 4: 測試通過；`python3 scripts/check_field_classification.py` 無 ❌**
- [ ] **Step 5: Commit**（`交易作廢 1/7：作廢紀錄實體與作廢回流原因`）

---

### Task 2: `TransactionVoidIndex` 共用元件＋場次列表／日曆摘要

**Files:**
- Create: `Tilli/Service/TransactionVoidIndex.swift`
- Modify: `Tilli/Data/Repositories/TransactionRepository.swift`
- Modify: `Tilli/ViewModel/EventsPage/EventsViewModel.swift:53-56`、`Tilli/ViewModel/EventsPage/EventsCalendarViewModel.swift:125-130`
- Modify: `CONVENTIONS.md`「共用計算元件」表
- Test: `TilliTests/TransactionVoidIndexTests.swift`

**Interfaces:**
- Consumes: Task 1 `TransactionVoidModel`、`CDTransactionVoidEntity`
- Produces:
```swift
struct TransactionVoidIndex {
    static let empty: TransactionVoidIndex
    init(voids: [TransactionVoidModel])                       // 同一 transactionId 多筆時取 voidedAt 最早者
    func voidRecord(for transactionId: UUID) -> TransactionVoidModel?
    func isVoided(_ transactionId: UUID) -> Bool
    func effective(_ transactions: [TransactionModel]) -> [TransactionModel]   // 保留原順序
}
// TransactionRepository
func fetchVoids(forEventId eventId: UUID) -> [TransactionVoidModel]
func effectiveSummary(forEventId eventId: UUID) -> (count: Int, total: Decimal)   // = voidIndex.effective(fetchTransactions).summary
```
`EventsViewModel.transactionSummary` 與 `EventsCalendarViewModel.transactionSummary` 改為呼叫 `effectiveSummary`。CONVENTIONS 新增一列：`TransactionVoidIndex`——「交易是否作廢／有效交易」唯一來源；不准再出現：在 VM／View 自己比對 `transactionId` 或另查作廢紀錄過濾。

- [ ] **Step 1: 寫失敗的測試**
```swift
func testEffectiveExcludesVoidedAndKeepsOrder()
func testEarliestVoidWinsWhenDuplicated()          // 兩筆同 transactionId，voidRecord 回傳 voidedAt 較早那筆
func testEffectiveSummaryExcludesVoided()          // in-memory：3 筆交易（100/200/300），作廢 200 → (2, 400)
func testFetchVoidsOnlyReturnsThatEvent()
```
- [ ] **Step 2: 跑測試，預期失敗**
- [ ] **Step 3: 實作**
- [ ] **Step 4: 測試通過**
- [ ] **Step 5: Commit**（`交易作廢 2/7：TransactionVoidIndex 與場次摘要排除作廢`）

---

### Task 3: `EventDataSource` 改提供有效交易

**Files:**
- Modify: `Tilli/Service/EventDataSource.swift`
- Modify: `Tilli/ViewModel/ReportsPage/TransactionHistoryViewModel.swift:146`（改用 `allTransactions(in:)`）
- Test: `TilliTests/EventDataSourceVoidTests.swift`

**Interfaces:**
- Consumes: Task 2 `TransactionVoidIndex`、`TransactionRepository.fetchVoids`
- Produces（`EventDataSource`）:
```swift
@Published private(set) var allTransactions: [TransactionModel]   // 含作廢；交易紀錄列表用
@Published private(set) var transactions: [TransactionModel]      // 有效交易（= voidIndex.effective(allTransactions)）；報表用
@Published private(set) var voidIndex: TransactionVoidIndex
func allTransactions(in range: DateInterval?) -> [TransactionModel]
func transactions(in range: DateInterval?) -> [TransactionModel]  // 有效交易，篩選條件不變
// transactionIndex 改由 allTransactions 建立（作廢不解鎖）
// transactionSummary 無呼叫端 → 刪除
```
`SalesAnalyticsViewModel`、`ProductPerformanceViewModel` 不改（已呼叫 `transactions(in:)`，自動拿到有效交易）。`AddEventViewModel`（日期範圍、`TransactionIndex`）、`AddNewProductViewModel`、`ProductRepository` 的 `TransactionIndex` 都直接讀 Repository 的全部交易，**不改**（spec：鎖定與日期範圍不排除作廢）。

- [ ] **Step 1: 寫失敗的測試**（fixture 比照 `ReportRevenueConsistencyTests`：直接建 entity，含一筆 `CDTransactionVoidEntity`）
```swift
func testTransactionsExcludeVoidedButAllTransactionsKeepThem()
func testSalesAnalyticsRevenueExcludesVoided()             // 總營收 == 有效交易 total
func testProductPerformanceExcludesVoided()                // 被作廢交易獨有的商品銷量為 0
func testTransactionIndexStillCountsVoidedTransactions()   // 只出現在作廢交易的商品 hasTransaction == true
func testEventsSummaryMatchesDataSourceSummary()           // TransactionRepository.effectiveSummary == dataSource.transactions.summary
```
- [ ] **Step 2: 跑測試，預期失敗**
- [ ] **Step 3: 實作**
- [ ] **Step 4: 本測試＋`ReportRevenueConsistencyTests`、`EventDataSourceTransactionRangeTests`、`ProductPerformanceTests` 全過**
- [ ] **Step 5: Commit**（`交易作廢 3/7：EventDataSource 報表只用有效交易`）

---

### Task 4: `VoidRecorder` 純函式＋`EventRepository.addVoid`

**Files:**
- Create: `Tilli/Service/VoidRecorder.swift`
- Modify: `Tilli/Data/Repositories/EventRepository.swift`（在 `addTransaction` 旁，「僅允許新增」）
- Test: `TilliTests/VoidRecorderTests.swift`

**Interfaces:**
- Consumes: Task 1、Task 2
- Produces:
```swift
enum VoidRecorder {
    enum Rejection: Error, Equatable { case alreadyVoided, missingReason, missingRestockChoice }
    struct Record { let void: TransactionVoidModel; let inventoryChanges: [InventoryChangeModel] }

    /// 已作廢、原因或回流選擇為 nil → 拒絕
    static func makeRecord(
        transaction: TransactionModel,
        salesChanges: [InventoryChangeModel],     // 呼叫端傳該場次全部異動，函式自己篩 .salesOut && transactionId == transaction.id
        voidIndex: TransactionVoidIndex,
        reason: VoidReason?,
        note: String,
        restock: Bool?,
        now: Date
    ) -> Result<Record, Rejection>

    /// 回流後的庫存：同商品多列累加；currentStock 沒有的商品略過
    static func stockUpdates(for changes: [InventoryChangeModel], currentStock: [UUID: Int]) -> [UUID: Int]
}
// EventRepository
@discardableResult func addVoid(_ model: TransactionVoidModel) -> Bool
// 寫入前查同 transactionId 已存在 → 不寫、回傳 false；userId 同 addTransaction；markPendingSync()；成功後 notifyTransactionsChanged()
```
回流異動：每筆 salesOut 對應一筆，`change = -原change`、`reason = .voidRestock`、`transactionId`、`bundleId`／`bundleName` 照抄、`customReason = nil`、`timestamp = now`、`eventId` 同原異動。不回流時 `inventoryChanges` 為空。`note` 去頭尾空白後空字串 → nil。

- [ ] **Step 1: 寫失敗的測試**
```swift
func testRestockMirrorsEachSalesOutChange()         // 2 筆 salesOut（-2、-1）→ +2、+1，reason .voidRestock，transactionId 相同
func testRestockKeepsBundleIdAndName()              // 套餐成員各一筆、bundleId/bundleName 照抄
func testRestockSumsSameProductAcrossRows()         // 同商品單點 -1＋套餐 -1，stock 5 → stockUpdates 7
func testNoRestockWritesOnlyVoid()
func testIgnoresOtherTransactionsAndNonSalesChanges()
func testRejectsAlreadyVoided() { XCTAssertEqual(result.failure, .alreadyVoided) }
func testRejectsMissingReasonOrRestockChoice()
func testBlankNoteStoredAsNil()
```
- [ ] **Step 2: 跑測試，預期失敗**
- [ ] **Step 3: 實作**（`addVoid` 不寫測試：內含 `Auth.auth()`）
- [ ] **Step 4: 測試通過**
- [ ] **Step 5: Commit**（`交易作廢 4/7：VoidRecorder 與 addVoid`）

---

### Task 5: 交易明細 — 作廢按鈕、作廢視窗、確認框、已作廢卡片

**Files:**
- Modify: `Tilli/ViewModel/ReportsPage/TransactionDetailViewModel.swift`
- Modify: `Tilli/View/ReportsPage/TransactionDetailView.swift`
- Create: `Tilli/View/ReportsPage/VoidTransactionView.swift`、`Tilli/ViewModel/ReportsPage/VoidTransactionViewModel.swift`（彈出的獨立頁面，依 CONVENTIONS MVVM 規則 5 有自己的 VM；寫入後用 callback 通知明細頁重新讀取）
- Modify: `Tilli/View/EventsPage/EventWorkspaceView.swift:150-151`（傳入 `dataSource`）
- Modify: `Localizable.xcstrings`
- Test: `TilliTests/TransactionDetailViewModelTests.swift`（既有測試改用新 init）、`TilliTests/VoidTransactionViewModelTests.swift`

**Interfaces:**
- Consumes: Task 3 `dataSource.voidIndex`／`allTransactions`／`inventoryChanges`／`reload()`；Task 4 `VoidRecorder`、`addVoid`
- Produces:
```swift
// TransactionDetailViewModel
init(transaction: TransactionModel, dataSource: EventDataSource)
@Published private(set) var voidRecord: TransactionVoidModel?   // 從 dataSource.voidIndex 取
var isVoided: Bool
func refreshVoidState()                                          // 作廢視窗 callback 後呼叫

// VoidTransactionViewModel（視窗每次打開都新建，所以選項一律從 nil 開始）
init(transaction: TransactionModel, dataSource: EventDataSource)
@Published var selectedReason: VoidReason?
@Published var note: String
@Published var restockChoice: Bool?             // nil = 未選
var transactionNumber: String; var amountText: String
var canSubmit: Bool                             // 未作廢 && selectedReason != nil && restockChoice != nil
var confirmTitle: String                        // voidConfirmTitle「作廢 %@（%@）？」displayNumber＋金額
var confirmMessage: String                      // voidConfirmMessage「作廢後無法還原。」＋換行＋voidConfirmRestock「庫存：回流」/ voidConfirmNoRestock「庫存：不回流」
enum VoidOutcome { case done, rejected, voidFailed, restockFailed }
func performVoid(eventRepository: EventRepository, productRepository: ProductRepository,
                 inventoryChangeRepository: InventoryChangeRepository, now: Date = Date()) -> VoidOutcome
```
`performVoid` 順序：`VoidRecorder.makeRecord`（拒絕 → `.rejected`）→ `addVoid`（false → `.voidFailed`）→ 回流時 `inventoryChangeRepository.addChanges(_, eventId:)`＋`productRepository.batchUpdateProductStock(VoidRecorder.stockUpdates…)`（失敗 → `.restockFailed`）→ `dataSource.reload()`。Repository 由 View 從 `@EnvironmentObject` 傳入（比照 `CashPaymentView.completePayment`）。

View（照 spec §4／§6 與草圖 `void-flow.html`、`void-sheet-v2.html`）：
- 明細最下方「作廢交易」按鈕（`voidTransactionButton`），`isVoided` 時不顯示。
- Sheet：`NavigationStack` + `Form`；左上「取消」；標題 `voidSheetTitle`「作廢交易」；第一區編號（muted 小字）＋金額（大字）；「作廢原因」區 `Picker`（selection `VoidReason?`，未選顯示 `voidReasonPlaceholder`「請選擇」）＋`TextField`（`voidNotePlaceholder`「請輸入作廢原因」，一律顯示）；「庫存」區兩段式選擇「回流／不回流」（`voidRestockYes`／`voidRestockNo`，無預設；系統 segmented Picker 無法表示「都未選」時用兩個並排的自訂分段按鈕）＋說明 `voidRestockHint`「回流：把這筆交易的商品數量加回庫存」；底部「作廢」按鈕（`voidSubmitButton`）`canSubmit` 才可按。
- 明細頁以 `.sheet` 開 `VoidTransactionView`，`onFinished` callback 呼叫 `refreshVoidState()`。
- 按「作廢」→ `.alert`（`confirmTitle`／`confirmMessage`，「取消」＋destructive「作廢」）→ `performVoid`；`.done` 關 sheet；`.voidFailed` alert `voidFailedMessage`「作廢失敗，請再試一次」；`.restockFailed` 關 sheet 並 alert `voidRestockFailedMessage`「交易已作廢，但庫存回流失敗，請到管理商品手動調整庫存」。
- 已作廢卡片放最上方：左側 alertRed 細條、紅字 `voidedTitle`「已作廢」；列 `voidedAt`「作廢時間」、`voidedReason`「原因」、`voidedNote`「說明」（有才顯示）、`voidedRestock`「庫存」值 `voidedRestocked`「已回流」/`voidedNotRestocked`「未回流」。

- [ ] **Step 1: 寫失敗的測試**（dataSource 用 in-memory fixture）
```swift
// VoidTransactionViewModelTests
func testCanSubmitRequiresReasonAndRestockChoice()
func testCannotSubmitWhenAlreadyVoided()
func testConfirmTextUsesDisplayNumberAmountAndRestockChoice()
// TransactionDetailViewModelTests
func testVoidRecordLoadedFromDataSource()
```
- [ ] **Step 2: 跑測試，預期失敗**
- [ ] **Step 3: 實作 VM、View、字串**
- [ ] **Step 4: 測試通過；build 成功**
- [ ] **Step 5: Commit**（`交易作廢 5/7：交易明細作廢流程`）

---

### Task 6: 交易紀錄列表、交易 CSV、庫存 CSV

**Files:**
- Modify: `Tilli/ViewModel/ReportsPage/TransactionHistoryViewModel.swift`（`DailyTransactionGroup`、`eventTotalAmount`、`generateCSVContent`）
- Modify: `Tilli/View/ReportsPage/TransactionHistoryView.swift`（`transactionCard`、日期標題）
- Modify: `Tilli/ViewModel/InventoryPage/InventoryViewModel.swift:295`
- Test: `TilliTests/TransactionHistoryVoidTests.swift`

**Interfaces:**
- Consumes: Task 3 `allTransactions(in:)`、`voidIndex`
- Produces:
```swift
// TransactionHistoryViewModel
func isVoided(_ transaction: TransactionModel) -> Bool        // 經 dataSource.voidIndex
// DailyTransactionGroup 新增 let voidedIds: Set<UUID>；totalAmount／count 只算 id 不在 voidedIds 的交易
// eventTotalAmount = dataSource.transactions.total（有效）
// generateCSVContent 只輸出有效交易
```
列表卡片：作廢者整張降透明度（深色模式仍可讀）、金額 `.strikethrough()`、編號旁 `voidedTag`「已作廢」標籤（quietFill 底＋alertRed 字、caption）；位置與點擊不變。金額排序／付款篩選照常包含作廢卡片。庫存 CSV 交易編號欄：`reason == .salesOut || reason == .voidRestock` 且有 `transactionId` 時輸出 `displayNumber`。

- [ ] **Step 1: 寫失敗的測試**
```swift
func testDailyGroupTotalsExcludeVoided()        // 當天 100、200(作廢) → totalAmount 100、count 1，transactions.count 2
func testAllVoidedDayShowsZero()                // totalAmount 0、count 0，transactions 仍 1 筆
func testTransactionCSVExcludesVoided()         // CSV 不含作廢交易的 displayNumber
func testInventoryCSVShowsTransactionNumberForVoidRestock()
```
- [ ] **Step 2: 跑測試，預期失敗**
- [ ] **Step 3: 實作**
- [ ] **Step 4: 全部測試通過**（全測試指令）
- [ ] **Step 5: Commit**（`交易作廢 6/7：交易紀錄與 CSV`）

---

### Task 7: 文件與手動測試清單

**Files:**
- Modify: `FEATURE_PLAN_V1.md`：Backlog「交易作廢」草案改為一行指向 spec；§11 新增「第 7 批 — 交易作廢」（狀態、「實作與計畫的差異」表：資料改存獨立實體、回流原因改新增「作廢回流」、入口只在明細、原因改 Picker、無預設回流等）、手動測試清單（下方）。Backlog CSV 重新設計條目補「作廢狀態欄位」。
- Modify: `CONVENTIONS.md` 版本記錄一列。

手動測試清單（寫進 FEATURE_PLAN）：
1. 結帳一筆含單點＋套餐的交易 → 明細作廢、選「輸入錯誤」＋回流 → 確認框文字正確 → 明細出現已作廢卡片、按鈕消失。
2. 管理商品頁：該商品庫存加回、異動列表出現「作廢回流」（套餐成員各一筆、顯示來自〈套餐〉）。
3. 交易紀錄：卡片變淡＋刪除線＋標籤；當日總額與筆數排除；匯出交易 CSV 不含該筆；庫存 CSV 作廢回流列有交易編號。
4. 查看分析銷售／商品成效數字排除；回場次列表與日曆，筆數與總額一致。
5. 另一筆選「不回流」→ 庫存不變、無異動。
6. 作廢視窗未選原因或回流時作廢按鈕不可按；取消確認框不會作廢。
7. 已作廢交易的商品仍不能刪除；已結束場次的交易也能作廢。
8. 深色模式檢查卡片、標籤、已作廢卡片可讀。

- [ ] **Step 1: 更新文件**
- [ ] **Step 2: 全部測試＋`check_field_classification.py` 通過**
- [ ] **Step 3: Commit**（`交易作廢 7/7：文件與手動測試清單`）

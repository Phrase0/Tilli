# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Tilli 是給台灣市集攤商用的 iOS POS App（SwiftUI + CoreData + Firebase）。**尚未上架、沒有真實使用者**：不需資料遷移，CoreData 欄位可直接改，刪 App 重裝即可。

## 文件（先讀相關的，不必全讀）

衝突時依此優先順序：

| 文件 | 用途 |
|------|------|
| `ARCHITECTURE.md` | **資料結構唯一真相來源**。每個 CoreData 欄位都必須在 §4 分類表有一列 |
| `CONVENTIONS.md` | 開發規範：共用計算元件、MVVM、資料同步、測試、多語言、檔案放置 |
| `FEATURE_PLAN_V2.md` | 本輪功能規劃與**執行進度**（§3 各批次）。每批完成後要更新狀態與「實作與計畫的差異」表 |
| `FEATURE_PLAN_V1.md` | 上一輪（已完成）的規劃、差異表與測試紀錄 |
| `DESIGN.md` / `PRODUCT.md` | UI 設計系統 / 產品定位與使用者情境 |
| `SYNC_ARCHITECTURE_V2.md` | 雲端同步規劃（2026-11-05 決定暫緩，第一版只做本機；合併規則沿用於備份匯入） |
| `docs/architecture/` | 架構地圖（`index.html` 自動產生）：頁面說明 `pages.md`、循序圖 `sequences/*.md` 手動維護 |
| `CLOUD_FUNCTIONS.md` | `functions/` 的 Firebase Cloud Functions |

`_archive/` 是過時文件；`_Deprecated/` 是不參與編譯的舊程式碼（列在 `project.pbxproj` 的 `membershipExceptions`），不要更新它們。

## 指令

```bash
# 建置
xcodebuild -project Tilli.xcodeproj -scheme Tilli -destination 'generic/platform=iOS Simulator' build

# 全部測試
xcodebuild test -project Tilli.xcodeproj -scheme Tilli -destination 'platform=iOS Simulator,name=iPhone 17'

# 單一測試類別 / 方法
xcodebuild test -project Tilli.xcodeproj -scheme Tilli -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:TilliTests/DiscountCalculatorTests
#   -only-testing:TilliTests/DiscountCalculatorTests/testPercentageAppliedBeforeFixedAmount

# 改了 CoreData model 或 ARCHITECTURE.md §4 後必跑
python3 scripts/check_field_classification.py

# 架構地圖：產生 / 檢查（commit 前由 .githooks/pre-commit 自動執行）
python3 scripts/build_docs.py
python3 scripts/build_docs.py --check
# 新 clone 後啟用 hook
git config core.hooksPath .githooks
```

`TilliTests/` 是 file-system-synchronized group，新測試檔放進去即自動納入，不用改 `project.pbxproj`。

## 架構重點

- 分層：`Data/`（CoreData、Repositories）→ `Model/Domain`（業務模型）→ `Service/`（無狀態計算）→ `ViewModel/<Page>` ↔ `View/<Page>`（同名資料夾對應）。放置規則見 `CONVENTIONS.md`「檔案組織規範」。
- **交易是流水帳**：`TransactionModel.items` 是 `SummaryItemModel` 的快照（名稱、單價、類別 id 都是交易當下的值，永不回頭更新）；折扣存成 `[AppliedDiscount]`，`amount` 是已 clamp 的快照，不從設定重算。
- **共用計算元件只准一份實作**（`TransactionIndex`、`EventDataSource`、`DiscountCalculator`、`CSVExporter`、`ProductAvailability`、`PendingSyncStamp`…），完整清單與「不准再出現」的寫法見 `CONVENTIONS.md`「共用計算元件」。
- 金額一律走 `MoneyHelper`，不用原生 `+ - * /`。
- 保護（如 clamp）放在**寫入邊界**（付款 VM 建立交易前），不依賴 View 記得呼叫。守衛只准拒絕，不准靜默改做別的事。
- 場次工作區內的資料一律經 `EventDataSource`，不另外呼叫 Repository。頁面間同步走 `onAppear` + 重新載入。
- 使用者可見文字一律走 `Localizable.xcstrings`（lowerCamelCase key，上方註解中文原文）。

## 架構地圖（docs/architecture/）

- 架構圖、頁面地圖、資料結構圖從程式碼自動產生，不用手改。
- **新增、刪除、改名畫面**（`View/<頁>/` 底下以 `View` 結尾的檔案）→ 同一次修改更新 `docs/architecture/pages.md`。
- **改到循序圖畫的流程**（結帳、作廢、商品存檔、進入工作區、刪除場次、啟動）→ 同一次修改更新 `docs/architecture/sequences/` 對應的檔；新增主要流程就加一張。
- pre-commit hook 會擋下缺說明或循序圖引用不存在型別的 commit，但**流程內容是否正確要靠自己更新**。

## 測試陷阱

- CoreData 測試用 `TestStore.makeInMemoryContainer()`（共用同一份 `NSManagedObjectModel`）。
- `assertionFailure` 在 Debug 測試會 trap：純判斷函式與 assertion 外層拆開，測純函式。
- 測試沒有 `FirebaseApp.configure()`：建 fixture 時直接建 `CDxxxEntity`，不走 Repository 的 `addXxx`。
- Mock 放 `TilliTests/TestHelpers.swift`（`static func mock(...)`）；測試名說出預期行為。

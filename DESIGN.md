---
name: Tilli (Market POS)
description: A minimalist point-of-sale companion for market and pop-up vendors.
colors:
  ink: "#000000"
  paper: "#F2F2F7"
  card-surface: "#FFFFFF"  # secondarySystemGroupedBackground
  muted: "#8E8E93"
  market-green: "#34C759"
  market-green-light: "#D8F5DE"
  alert-red: "#FF3B30"
colors-dark:
  ink: "#FFFFFF"
  paper: "#000000"
  card-surface: "#1C1C1E"
  muted: "#8E8E93"
  market-green: "#30D158"
  market-green-light: "#13321C"
  alert-red: "#FF453A"
typography:
  display:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "34px"
    fontWeight: 700
    lineHeight: 1.1
    letterSpacing: "normal"
  title1:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "28px"
    fontWeight: 700
    lineHeight: 1.2
  title2:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "22px"
    fontWeight: 600
    lineHeight: 1.25
  body:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.4
  caption:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.3
rounded:
  sm: "12px"
  md: "16px"
  pill: "999px"
border:
  card-color-light: "rgba(0,0,0,0.06)"
  card-color-dark: "rgba(255,255,255,0.08)"
  card-width: "0.5px"
spacing:
  xs: "8px"
  sm: "12px"
  md: "16px"
  lg: "24px"
components:
  button-primary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.card-surface}"
    rounded: "{rounded.md}"
    padding: "16px 24px"
  button-secondary:
    backgroundColor: "#E5E5EA"
    textColor: "{colors.ink}"
    rounded: "{rounded.md}"
    padding: "16px 24px"
  button-destructive:
    backgroundColor: "#E5E5EA"
    textColor: "{colors.alert-red}"
    rounded: "{rounded.md}"
    padding: "16px 24px"
  status-pill-running:
    backgroundColor: "#D8F5DE"
    textColor: "{colors.market-green}"
    rounded: "{rounded.pill}"
    padding: "4px 8px"
  status-pill-neutral:
    backgroundColor: "#E5E5EA"
    textColor: "{colors.muted}"
    rounded: "{rounded.pill}"
    padding: "4px 8px"
  card:
    backgroundColor: "{colors.card-surface}"
    rounded: "{rounded.md}"
    padding: "16px"
---

> **語言版本：** 這份正體中文版是 canonical 版本——`.impeccable` 工具鏈只認 `DESIGN.md` 這個檔名，所有 token 定義（上面的 YAML frontmatter）都以這份文件為準。英文版見 [`DESIGN.en.md`](./DESIGN.en.md)，純粹給不看中文的人參考用，不吃任何自動化流程。之後如果要加其他語言，比照 `DESIGN.<語言代碼>.md` 命名（例如 `DESIGN.ja.md`），只翻內文，不要在裡面另外維護一份 frontmatter——token 數值改了只改這份中文版，其他語言版本手動同步過去就好，避免多處維護跑掉。

# 設計系統：Tilli（市集收銀 POS）

## 總覽

**設計核心理念：「攤商的隨手帳」**

Tilli 是攤商在客人交易空檔隨手打開的小工具，不是拿來給人瀏覽欣賞的門面。整套視覺語言就像攤商壓在收銀盒下的那本紙本帳簿：一眼就能看懂、帳篷裡光線再差也不會看錯字、完全不在乎好不好看。畫面不是純白就是淺灰，所有操作都用黑色文字表達；整個 App 唯一用到的顏色，只留給攤商真正在意的那件事——這場次現在是不是正在進行中。

這份文件寫的是「重構後的目標樣貌」，依照參考稿（`tilliStructure1–3.PNG`）訂出往後所有畫面該遵循的視覺規則，不是現有程式碼庫每個畫面的現況說明。`AddNewProductView`、`CheckoutFlowView`、`InventoryChangeView` 這幾個舊頁面，以及殘留的藍／橘／紫等舊配色，都是這套系統要取代掉的對象，不是要保留下來混搭的參考。

**幾個關鍵特徵：**
- 預設全單色：黑、白、兩階灰幾乎撐起整個畫面。
- 只留一個語意色：綠色，專門代表「進行中／正向」，不作裝飾用。
- 卡片扁平、陰影淡到幾乎看不見——深度靠色塊對比表現，不靠「浮起」的效果。
- 字級只留四級（28 / 22 / 16 / 12），間距也只留四級（8 / 12 / 16 / 24），沒有例外值。
- 滿版黑色主要按鈕搭配 16pt 圓角，是整個 App 唯一「搶眼」的元素——即使搶眼，也還是黑色。

## 色彩

整體配色幾乎是灰階，只留一個語意例外。顏色從來不拿來裝飾，只用在一個地方：回答「這件事現在正在發生嗎？」

### 主色
- **墨黑 Ink**（`#000000`）：所有主要 CTA、選中的分頁／分段、各種選中狀態（日曆日期、分類篩選、單選鈕）、標題文字都用這個顏色。這是 App 唯一的品牌色，沒有其他顏色可以取代它當強調色用。

### 次要色
- **市集綠 Market Green**（`#34C759`）：只用來表示「進行中」／正向狀態（進行中場次的標籤、結帳完成的成功勾勾）。不能用在按鈕、圖示或強調文字上。同一個畫面出現一個以上的綠色元素，就是設計錯誤。

### 中性色
- **紙灰 Paper**（`#F2F2F7`，`systemGroupedBackground`）：卡片背後的頁面底色。
- **卡片面 Card Surface**（`#FFFFFF`，`secondarySystemGroupedBackground`）：卡片、彈出視窗、列表列的填色。
- **靜音灰 Muted Gray**（`#8E8E93`，`.secondary`）：次要文字，例如日期、副標題、輔助說明、未選中的分頁標籤。
- **靜謐填色 Quiet Fill**（`#E5E5EA`，`systemGray6`）：次要按鈕背景、中性／已完成狀態標籤、未選中的分段軌道。
- **警示紅 Alert Red**（`#FF3B30`，`systemRed`）：只用在破壞性文字上（刪除場次、刪除商品、移除項目），不能當按鈕的底色。

### 深色模式配色
深色模式下，整體原則不變（單色為主、綠色只代表進行中、禁藍），色值會自動適配：

| Token | 淺色模式 | 深色模式 | 來源 |
|-------|---------|---------|------|
| Ink | `#000000` | `#FFFFFF` | `Color.primary`（系統自動） |
| Paper | `#F2F2F7` | `#1C1C1E` | `systemGroupedBackground`（系統自動） |
| Card Surface | `#FFFFFF` | `#1C1C1E` | `secondarySystemGroupedBackground`（系統自動） |
| Muted | `#8E8E93` | `#8E8E93` | `Color.secondary`（系統自動） |
| Quiet Fill | `#E5E5EA` | `#2C2C2E` | `systemGray5`（系統自動） |
| Market Green | `#34C759` | `#30D158` | 手動適配，深色稍微提亮 |
| Market Green Light | `#D8F5DE` | `#13321C` | 手動適配，深色改用低飽和暗綠 |
| Alert Red | `#FF3B30` | `#FF453A` | `systemRed`（系統自動） |
| 卡片陰影 | `black 5%` | `white 6%` | 手動適配 |

**深色模式規則：** 卡片靠背景色差分層（深灰卡片疊在更深的底色上），陰影改用微弱白光（6%），視覺邏輯和淺色模式完全相同。

### 命名規則
**唯一綠色原則。** 綠色只代表一件事：進行中。它不能當一般強調色、連結色、圖示色，也不能拿來裝飾——只要不是在標示進行中的場次或已完成的付款，就不該用綠色。

**禁藍原則。** 互動與選中狀態一律用實心墨黑表達，不用有色的強調色。整個介面完全不出現藍色；一個控制項要顯示「已啟用」，靠的是變黑，不是變藍。

## 字體

**顯示字體：** SF Pro（系統字體，沒有另外載入自訂字型——這是刻意的選擇，不是還沒做完。）

**風格：** 一套誠實的系統字體，四個尺寸，再加一個給金額數字專用的加大級距（今日營收、結帳金額）。沒有窄體、沒有斜體、沒有裝飾字重——這本帳簿沒有「品牌字型」，只有讓人看得清楚的數字。

### 字級層級
- **Display**（700，34px，行高 1.1）：只給重點金額用——儀表板的今日營收、結帳成功金額。只留給金額，不能拿來當標題。
- **Title 1**（700，28px，行高 1.2）：頁面標題（場次、收銀、庫存、分析、我的）。
- **Title 2**（600，22px，行高 1.25）：頁面內的區塊標題，例如「今天」「即將到來」，或彈出視窗裡的欄位分組標題。
- **Body**（400，16px，行高 1.4）：商品名稱、列表列、表單欄位值、按鈕文字。
- **Caption**（400，12px，行高 1.3）：時間戳記、輔助說明、狀態標籤文字、數量／庫存計數。

### 命名規則
**四級字體原則。** 每個畫面都只能用這四個尺寸，加上唯一的 Display 級距。出現第五種尺寸，代表版面該重新設計，不是該多加一個 token。

## 版面

單欄、滿版寬度的卡片堆疊——這是手機優先、單手在攤位上操作的工具，不是響應式網格。畫面開頭是 Title 1 標題（常搭配一個尾端的純圖示按鈕），接著垂直排列滿版卡片，卡片之間用 24pt 間距分開，不用 `Divider()` 分隔線。卡片內的列表列之間留 12pt，卡片內邊距是 16pt。底部導覽是常駐的 4–5 個項目分頁列（收銀／庫存／分析，或外層的場次／我的），用 SF Symbols 外框圖示搭配 Caption 大小的文字。彈出視窗（新增場次、編輯商品）由上到下堆疊欄位，每個輸入框上方放標籤，視窗底部固定一個滿版主要按鈕。

## 層次與深度

深度幾乎全靠扁平的色塊對比表現（灰底上的白卡片），不靠陰影。就算有陰影，也只是一個幾乎感覺不到的環境提示，用來說「這是一張卡片」而已——不是方向性的浮起效果，也不模擬 hover/press 回饋（這是純觸控介面，沒有 hover 這回事）。

### 陰影規範
- **卡片環境陰影**（`shadow: 0 1px 2px rgba(0,0,0,0.05)`）：系統裡唯一的陰影，套用在每張獨立卡片、場次方塊、列表列容器上。

### 命名規則
**耳語陰影原則。** 陰影不透明度不能超過 0.05。陰影只要明顯到能被具體描述出來，就是太重了——深度只該讓人感覺到「這是一張卡片」，僅此而已。

## 形狀

只用兩種圓角，徹底一致：**16px** 給拇指會直接點的主要目標——卡片、主／次要按鈕、商品照片、彈出視窗；**12px** 給比較小或輔助性的元件——小按鈕、列表列容器、輸入欄位。狀態標籤、標籤、List／Calendar 分段切換一律用滿膠囊（999px）。系統裡沒有直角，也沒有第三種圓角。

## 元件

### 按鈕
- **形狀：** 16px 圓角、滿版寬度、垂直內距 16px。
- **主要按鈕：** 墨黑（`#000000`）底、白色文字、16px 半粗體——App 唯一最搶眼的手勢（「建立場次」「結帳」「確認收款」「立即同步」）。
- **次要按鈕：** 靜謐填色（`#E5E5EA`）底、墨黑文字——用在「取消」和搭配主要按鈕的次要動作。
- **破壞性按鈕：** 底色跟次要按鈕一樣是靜謐填色，文字是紅色——用在「刪除場次」這類動作。破壞性動作不能用實心紅色底，紅色只出現在文字上。
- **純圖示按鈕：** 純 SF Symbol（外框樣式），色調用 `.primary` 或 `.secondary`，沒有背景——用在標頭動作（搜尋、新增、篩選、返回）。

### 狀態標籤（招牌元件）
- **進行中：** 淺綠底（`#D8F5DE`）配市集綠文字，膠囊形狀，Caption 大小文字（「進行中」/「Running」）。
- **中性／已完成：** 靜謐填色底配靜音灰文字，同樣是膠囊形狀。
- **規則：** 每張卡片最多一個狀態標籤，位置固定在卡片標頭的右上角／尾端。

### 卡片／容器
- **圓角：** 16px。
- **邊框：** 0.5px，淺色模式 `rgba(0,0,0,0.06)`、深色模式 `rgba(255,255,255,0.08)`。
- **底色：** 卡片面（`#FFFFFF`）疊在紙灰（`#F2F2F7`）頁面底色上——這兩色的對比就是整套系統的深度模型。
- **陰影：** 只用卡片環境耳語陰影（見「層次與深度」）。
- **邊框：** 沒有。卡片一律靠色塊對比和間距分隔，不用描邊。
- **內邊距：** 16px。

### 輸入／欄位
- **樣式：** 標籤（Caption／Body 字重）放在純底線或靜謐填色欄位上方，12px 圓角，不用粗重的描邊框。
- **焦點：** 用系統預設的鍵盤焦點外框，不做自訂光暈。
- **選填欄位：** 直接在標籤上標「(選填)」，不用星號標必填。

### 導覽
- **分頁列：** SF Symbols 外框圖示配 Caption 文字；選中項目切成 `.primary`（黑色）圖示＋文字，未選中維持 `.secondary` 灰。沒有彩色的選中指示器——圖示和文字變黑就是唯一的訊號。
- **分段控制（List／Calendar）：** 靜謐填色的膠囊軌道，選中的分段是實心墨黑膠囊配白字，在軌道裡滑動。

### 資料視覺化（單色原則的例外）
- **付款方式甜甜圈圖／圖例**（分析 → 銷售分析）：系統裡唯一允許用多色分類調色盤的地方（例如 LINE Pay／現金／街口支付／信用卡各用綠／藍／橘／灰），因為要區分三種以上分類非得靠顏色不可。這套調色盤只能用在圖表圖例，絕對不能流到按鈕、圖示或其他狀態標籤上。

## 該做 / 不該做

### 該做：
- **該** 每個主要 CTA、每個「選中」狀態（選中的分頁、分段、日曆日期、單選鈕）都用實心墨黑（`#000000`）。
- **該** 圓角只用 16px 或 12px、間距只用 8/12/16/24px、字級只用 28/22/16/12px（加上金額專用的 34px Display）。
- **該** 把綠色留給「進行中」狀態，不做其他用途。
- **該** 全面使用外框樣式的 SF Symbols，只有表示選中／啟用狀態時才切成 `.fill`，不做裝飾用。
- **該** 用間距和色塊對比分區塊，不用 `Divider()`。

### 不該做：
- **不該** 用藍色（或墨黑以外的任何顏色）當按鈕底色或選中狀態的填色。
- **不該** 讓陰影不透明度超過 0.05，也不用陰影模擬 hover——這是純觸控工具。
- **不該** 加第二個彩色狀態標籤，或讓綠色多一種意思。
- **不該** 延用舊有的藍／橘／紫強調色、非標準圓角（4/8/10/24/25/30px），或舊畫面上還留著的隨意字級——那些是這套系統要淘汰的技術債，不是可以參考的先例。
- **不該** 在資料視覺化例外之外用彩色圖示。

# 折扣系統重構方案

## 目標

將折扣從「商品級別固定選項 (5%, 10%, 20%)」改為「Session 級別自訂折扣」。

### 需求

1. 在新增/編輯 Session 時，可自訂折扣選項
2. 支援兩種折扣類型：
   - 百分比折扣：5%, 10% 等
   - 金額折扣：5 元, 10 元等
3. 數量不限，可新增多種折扣
4. 折扣不可疊加（每筆訂單只能套用一個）
5. 金額折扣是折「整筆訂單總額」（例如總額 300 - 5 = 295）
6. 在產品頁總計上方顯示折扣選擇器（可左右滑動）

---

## 架構設計

```
DiscountType (enum)              ← 共用
    │
    ├── DiscountModel            ← Session 用（需要 id 給 UI ForEach）
    │       ├── id: UUID
    │       ├── type: DiscountType
    │       └── value: Decimal
    │
    └── TransactionModel         ← 交易層級存折扣（整筆訂單一個折扣）
            ├── discountType: DiscountType?
            └── discountValue: Decimal?
```

**重點：折扣存在 TransactionModel 層級，不是 SummaryItemModel 層級**

---

## 檔案變動總覽

### 新增檔案（1 個）

| 檔案 | 說明 |
|------|------|
| `DiscountModel.swift` | 折扣模型（含 DiscountType enum） |

### 修改檔案

| 檔案 | 修改內容 |
|------|----------|
| `SessionModel.swift` | 新增 `discounts: [DiscountModel]` |
| `TransactionModel.swift` | 新增 `discountType: DiscountType?` + `discountValue: Decimal?` |
| `SummaryItemModel.swift` | 移除 `discount: Int`（不再需要） |
| `Tilli.xcdatamodeld` | CDSessionEntity 新增 `discountsData`，CDTransactionEntity 新增折扣欄位 |
| `CDSessionEntity` | 新增 `discountsData` 屬性和轉換邏輯 |
| `CDTransactionEntity` | 新增折扣欄位和轉換邏輯 |
| `AddSessionView.swift` | 新增折扣編輯 Section（在類別 Section 後面） |
| `AddSessionViewModel.swift` | 新增折扣相關狀態和方法 |
| `ProductDetailView.swift` | 移除舊折扣按鈕，新增折扣選擇器 |
| `ProductDetailViewModel.swift` | 改用新折扣結構 |
| `CheckoutSummaryView.swift` | 顯示訂單層級的折扣 |
| `TransactionHistoryViewModel.swift` | CSV 匯出改用新結構 |
| `ProductPerformanceService.swift` | 折扣統計計算改用新結構 |

---

## 一、新增檔案

### 1.1 DiscountModel.swift

**路徑：** `Tilli/Model/Domain/DiscountModel.swift`

```swift
import Foundation

// MARK: - DiscountType

enum DiscountType: String, Codable, CaseIterable {
    case percentage    // 百分比
    case amount        // 金額
}

// MARK: - DiscountModel

struct DiscountModel: Identifiable, Codable, Hashable {
    var id = UUID()
    var type: DiscountType
    var value: Decimal      // 5 = 5% 或 5元

    /// 顯示文字，例如 "5%" 或 "-5元"
    func displayText(currency: String = "") -> String {
        switch type {
        case .percentage:
            return "\(value)%"
        case .amount:
            let suffix = currency.isEmpty ? "元" : ""
            return "-\(value)\(suffix)"
        }
    }
}
```

---

## 二、修改 Model

### 2.1 SessionModel.swift

**新增屬性：**

```swift
struct SessionModel: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var startDate: Date
    var endDate: Date?
    var dateType: SessionDateType
    var categories: [CategoryModel]
    var createdAt: Date
    var currency: String = "TWD"
    var discounts: [DiscountModel] = []   // ← 新增

    // ... 其他現有屬性和方法
}
```

### 2.2 TransactionModel.swift

**新增屬性：**

```swift
struct TransactionModel: Identifiable, Codable, Hashable {
    var id = UUID()
    var sessionId: UUID
    var sessionTitle: String
    var currency: String
    var items: [SummaryItemModel]
    var totalAmount: Decimal
    var paymentMethod: PaymentMethod
    var timestamp: Date
    var discountType: DiscountType?     // ← 新增
    var discountValue: Decimal?         // ← 新增
}
```

### 2.3 SummaryItemModel.swift

**移除：**
```swift
var discount: Int  // 刪除這行
```

**修改 total 計算（不再計算折扣）：**
```swift
var total: Decimal {
    return MoneyHelper.multiply(price, Decimal(quantity))
}
```

---

## 三、修改 CoreData

### 3.1 Tilli.xcdatamodeld

**CDSessionEntity 新增屬性：**
- **Name:** `discountsData`
- **Type:** Binary Data
- **Optional:** Yes

**CDTransactionEntity 新增屬性：**
- **Name:** `discountType`
- **Type:** String
- **Optional:** Yes

- **Name:** `discountValue`
- **Type:** Decimal
- **Optional:** Yes

### 3.2 CDSessionEntity+CoreDataProperties.swift

**新增屬性：**
```swift
@NSManaged public var discountsData: Data?
```

### 3.3 CDSessionEntity 轉換方法

**修改 toModel()：**
```swift
func toModel() -> SessionModel {
    // 解碼 discounts
    let discounts: [DiscountModel] = {
        guard let data = discountsData else { return [] }
        return (try? JSONDecoder().decode([DiscountModel].self, from: data)) ?? []
    }()

    return SessionModel(
        id: id,
        title: title,
        startDate: startDate,
        endDate: endDate,
        dateType: SessionDateType(rawValue: dateType) ?? .single,
        categories: /* 現有邏輯 */,
        createdAt: createdAt,
        currency: currency,
        discounts: discounts   // ← 新增
    )
}
```

**修改 update(from:)：**
```swift
func update(from model: SessionModel, context: NSManagedObjectContext) {
    // ... 現有邏輯

    // 編碼 discounts
    discountsData = try? JSONEncoder().encode(model.discounts)
}
```

### 3.4 CDTransactionEntity 轉換方法

**修改 toModel()：**
```swift
func toModel() -> TransactionModel {
    // 解碼折扣類型
    let discountTypeEnum: DiscountType? = {
        guard let typeString = discountType else { return nil }
        return DiscountType(rawValue: typeString)
    }()

    return TransactionModel(
        // ... 現有屬性
        discountType: discountTypeEnum,
        discountValue: discountValue as Decimal?
    )
}
```

**修改 update(from:)：**
```swift
func update(from model: TransactionModel, context: NSManagedObjectContext) {
    // ... 現有邏輯

    // 存儲折扣
    discountType = model.discountType?.rawValue
    discountValue = model.discountValue as NSDecimalNumber?
}
```

---

## 四、修改 AddSessionView（折扣編輯）

### 4.1 UI 設計

```
┌─────────────────────────────────────────┐
│ 折扣                                    │
├─────────────────────────────────────────┤
│  5%                              ← 滑動刪除
│  10%                             ← 滑動刪除
│  -5元                            ← 滑動刪除
├─────────────────────────────────────────┤
│  [  5  ]  [ % | 元 ]        [+]        │
└─────────────────────────────────────────┘
```

### 4.2 AddSessionViewModel.swift 新增

```swift
// MARK: - 折扣相關狀態

@Published var discounts: [DiscountModel] = []
@Published var newDiscountValue: String = ""
@Published var newDiscountType: DiscountType = .percentage

/// 根據折扣類型和幣別決定鍵盤類型
var discountKeyboardType: UIKeyboardType {
    switch newDiscountType {
    case .percentage:
        // 百分比永遠是整數
        return .numberPad
    case .amount:
        // 金額根據幣別的小數位數決定
        let currency = Currency(rawValue: selectedCurrency) ?? .twd
        return currency.decimalPlaces > 0 ? .decimalPad : .numberPad
    }
}

/// 嘗試新增折扣
func tryAddDiscount() -> String? {
    let trimmed = newDiscountValue.trimmingCharacters(in: .whitespaces)

    guard !trimmed.isEmpty else {
        return "請輸入數值"
    }

    guard let value = Decimal(string: trimmed), value > 0 else {
        return "請輸入有效的數值"
    }

    // 百分比驗證：必須是整數且不超過 100
    if newDiscountType == .percentage {
        // 檢查是否為整數
        if value != value.rounded() {
            return "百分比必須是整數"
        }
        if value > 100 {
            return "百分比不可超過 100"
        }
    }

    // 檢查是否重複
    let isDuplicate = discounts.contains {
        $0.type == newDiscountType && $0.value == value
    }
    if isDuplicate {
        return "此折扣已存在"
    }

    let discount = DiscountModel(type: newDiscountType, value: value)
    discounts.append(discount)
    newDiscountValue = ""
    return nil
}

/// 刪除折扣
func deleteDiscount(_ discount: DiscountModel) {
    discounts.removeAll { $0.id == discount.id }
}
```

**修改 save() 方法：**
```swift
func save() -> SessionModel {
    return SessionModel(
        // ... 現有參數
        discounts: discounts   // ← 新增
    )
}
```

**編輯模式初始化：**
```swift
init(sessionToEdit: SessionModel? = nil) {
    if let session = sessionToEdit {
        // ... 現有邏輯
        self.discounts = session.discounts   // ← 新增
    }
}
```

### 4.3 AddSessionView.swift 新增 Section

**位置：在類別 Section 之後、已停用類別 Section 之前**

```swift
// MARK: - 折扣 Section

Section(header: Text("折扣")) {
    // 已有的折扣列表
    ForEach(viewModel.discounts) { discount in
        Text(discount.displayText(currency: viewModel.selectedCurrency))
    }
    .onDelete { indexSet in
        indexSet.forEach { index in
            viewModel.deleteDiscount(viewModel.discounts[index])
        }
    }

    // 新增折扣輸入區
    HStack(spacing: 12) {
        TextField("數值", text: $viewModel.newDiscountValue)
            .keyboardType(viewModel.discountKeyboardType)  // ← 動態鍵盤類型
            .frame(width: 80)
            .onChange(of: viewModel.newDiscountType) { _, _ in
                // 切換類型時清空輸入值（避免格式問題）
                viewModel.newDiscountValue = ""
            }

        Picker("類型", selection: $viewModel.newDiscountType) {
            Text("%").tag(DiscountType.percentage)
            Text("元").tag(DiscountType.amount)
        }
        .pickerStyle(.segmented)

        Button {
            if let error = viewModel.tryAddDiscount() {
                viewModel.alertMessage = error
                viewModel.showAlert = true
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .foregroundColor(
                    viewModel.newDiscountValue.isEmpty ? .gray : .blue
                )
        }
        .disabled(viewModel.newDiscountValue.isEmpty)
    }
}
```

**鍵盤類型邏輯：**
| 折扣類型 | 幣別 | 鍵盤類型 |
|---------|------|---------|
| 百分比 (%) | 任何 | `numberPad`（整數） |
| 金額 | TWD, JPY | `numberPad`（整數） |
| 金額 | USD, EUR, GBP | `decimalPad`（小數） |

---

## 五、修改 ProductDetailView（折扣選擇器）

### 5.1 UI 設計

```
┌─────────────────────────────────────────┐
│                                         │
│  商品列表...                            │
│                                         │
├─────────────────────────────────────────┤
│                                         │
│  套用折扣              ← 可左右滑動 →   │
│  ┌─────┐ ┌─────┐ ┌──────┐ ┌──────┐     │
│  │ 5%  │ │ 10% │ │ -5元 │ │-10元 │ ··· │
│  └─────┘ └─────┘ └──────┘ └──────┘     │
│                                         │
├─────────────────────────────────────────┤
│                                         │
│  總計                  5%    $1,234     │
│                                         │
│  ╔═════════════════════════════════╗    │
│  ║             結帳                ║    │
│  ╚═════════════════════════════════╝    │
│                                         │
└─────────────────────────────────────────┘
```

### 5.2 ProductDetailViewModel.swift 修改

**移除：**
```swift
@Published var selectedDiscounts: [UUID: Int] = [:]

func toggleDiscount(for product: ProductModel, percent: Int) { ... }
func isDiscountSelected(for product: ProductModel, percent: Int) -> Bool { ... }
```

**新增：**
```swift
/// 當前選擇的折扣 ID
@Published var selectedDiscountId: UUID?

/// 取得選中的折扣 Model
var selectedDiscount: DiscountModel? {
    guard let id = selectedDiscountId else { return nil }
    return session.discounts.first { $0.id == id }
}

/// 計算小計（未套用折扣）
func subtotal() -> Decimal {
    activeProducts.reduce(Decimal(0)) { result, product in
        let qty = quantities[product.id, default: 0]
        let itemTotal = MoneyHelper.multiply(product.price, Decimal(qty))
        return MoneyHelper.add(result, itemTotal)
    }
}

/// 計算總金額（套用折扣）
func totalAmount() -> Decimal {
    let sub = subtotal()

    guard let discount = selectedDiscount else {
        return sub
    }

    switch discount.type {
    case .percentage:
        let rate = MoneyHelper.subtract(Decimal(1), discount.value / 100)
        return MoneyHelper.multiply(sub, rate)
    case .amount:
        return max(MoneyHelper.subtract(sub, discount.value), 0)
    }
}

/// 產生 SummaryItemModel 列表（不含折扣，折扣存在 Transaction 層級）
func selectedProductsWithQuantity() -> [SummaryItemModel] {
    activeProducts.compactMap { product -> SummaryItemModel? in
        let qty = quantity(for: product)
        guard qty > 0 else { return nil }

        return SummaryItemModel(
            productId: product.id,
            name: product.name,
            price: product.price,
            categoryId: product.categoryId,
            category: product.categoryName,
            quantity: qty,
            timestamp: Date()
        )
    }
}
```

### 5.3 ProductDetailView.swift 修改

**移除：** 每個商品下方的折扣按鈕

```swift
// 刪除這段
HStack(spacing: 8) {
    ForEach([5, 10, 20], id: \.self) { percent in
        // ...
    }
}
```

**新增：** 折扣選擇器（寫在 View 內部）

```swift
// MARK: - 折扣選擇器

@ViewBuilder
private var discountSelector: some View {
    if !productViewModel.session.discounts.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
            Text("套用折扣")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(productViewModel.session.discounts) { discount in
                        let isSelected = productViewModel.selectedDiscountId == discount.id

                        Text(discount.displayText(currency: productViewModel.session.currency))
                            .font(.subheadline)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(isSelected ? Color.blue : Color(.systemGray5))
                            .foregroundColor(isSelected ? .white : .primary)
                            .cornerRadius(20)
                            .onTapGesture {
                                if isSelected {
                                    productViewModel.selectedDiscountId = nil
                                } else {
                                    productViewModel.selectedDiscountId = discount.id
                                }
                            }
                    }
                }
                .padding(.horizontal, 1)
            }
        }
        .padding(.horizontal)
    }
}
```

**修改 body 結構：**

```swift
var body: some View {
    VStack(spacing: 0) {
        // 商品列表 ScrollView
        ScrollView {
            // ... 現有商品列表
        }

        Divider()

        // ===== 折扣選擇器 =====
        discountSelector

        // 總計和結帳
        VStack(spacing: 12) {
            HStack {
                Text("總計")
                    .font(.headline)
                Spacer()

                // 顯示選中的折扣
                if let discount = productViewModel.selectedDiscount {
                    Text(discount.displayText(currency: productViewModel.session.currency))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                }

                Text(MoneyHelper.format(
                    productViewModel.totalAmount(),
                    currencyCode: productViewModel.session.currency
                ))
                .font(.headline)
                .bold()
            }

            Button {
                showCheckoutSheet = true
            } label: {
                Text("結帳")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(productViewModel.totalAmount() > 0 ? Color.blue : Color.gray)
                    .cornerRadius(30)
            }
            .disabled(productViewModel.totalAmount() <= 0)
        }
        .padding()
    }
}
```

---

## 六、修改 CheckoutSummaryView

**修改：接收折扣參數並顯示**

```swift
struct CheckoutSummaryView: View {
    let selectedItems: [SummaryItemModel]
    let totalAmount: Decimal
    let selectedDiscount: DiscountModel?  // ← 新增

    // ... 其他現有屬性
}
```

**在總計區域顯示折扣：**

```swift
// MARK: 總金額
HStack {
    Text("總計")
        .font(.headline)
    Spacer()

    // 顯示折扣標籤
    if let discount = selectedDiscount {
        Text(discount.displayText(currency: session.currency))
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.2))
            .cornerRadius(4)
    }

    Text(totalAmount.money(currency: session.currency))
        .font(.headline)
        .bold()
}
.padding()
```

---

## 七、刪除的程式碼

| 位置 | 刪除內容 |
|------|----------|
| `SummaryItemModel.swift` | `var discount: Int` |
| `SummaryItemModel.swift` | `total` 計算中的折扣邏輯 |
| `ProductDetailView.swift` | 5%, 10%, 20% 固定折扣按鈕（ForEach [5, 10, 20]） |
| `ProductDetailViewModel.swift` | `selectedDiscounts: [UUID: Int]` |
| `ProductDetailViewModel.swift` | `toggleDiscount()` 方法 |
| `ProductDetailViewModel.swift` | `isDiscountSelected()` 方法 |
| `CheckoutSummaryView.swift` | 商品列表中的 `item.discount` 顯示 |

---

## 八、實作順序

1. **Model 層**
   - [ ] 新增 `DiscountModel.swift`（含 DiscountType）
   - [ ] 修改 `SessionModel.swift`
   - [ ] 修改 `TransactionModel.swift`
   - [ ] 修改 `SummaryItemModel.swift`（移除 discount）

2. **CoreData 層**
   - [ ] 修改 `Tilli.xcdatamodeld`
   - [ ] 修改 `CDSessionEntity`
   - [ ] 修改 `CDTransactionEntity`

3. **Session 編輯**
   - [ ] 修改 `AddSessionViewModel.swift`
   - [ ] 修改 `AddSessionView.swift`

4. **產品頁面**
   - [ ] 修改 `ProductDetailViewModel.swift`
   - [ ] 修改 `ProductDetailView.swift`
   - [ ] 修改 `CheckoutSummaryView.swift`

5. **支付流程**
   - [ ] 修改 `CashPaymentView.swift`
   - [ ] 修改 `EPaymentView.swift`

6. **其他調整**
   - [ ] 修改 `TransactionHistoryViewModel.swift`
   - [ ] 修改 `ProductPerformanceService.swift`
   - [ ] 清理所有用到 `discount: Int` 的地方

---

## 九、注意事項

1. **精度計算**：使用 `MoneyHelper` 的方法，避免浮點數精度問題
2. **空狀態處理**：沒有設定折扣時，不顯示折扣選擇器
3. **折扣驗證**：
   - 百分比：必須是整數，不可超過 100%
   - 金額：根據幣別決定小數位數（TWD/JPY 整數，USD/EUR/GBP 兩位小數）
   - 數值必須大於 0
4. **鍵盤類型**：
   - 百分比：永遠使用 `numberPad`（整數鍵盤）
   - 金額：根據幣別的 `decimalPlaces` 決定（0 用 `numberPad`，>0 用 `decimalPad`）
5. **重複檢查**：同類型同數值的折扣不可重複新增
6. **UI 回饋**：選中的折扣要有明顯的視覺區分
7. **資料不遷移**：直接刪除舊的 discount 欄位，不做遷移
8. **類型切換**：切換折扣類型（%↔元）時清空輸入值，避免格式問題

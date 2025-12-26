//
//  AddNewProductViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/6/23.
//

import SwiftUI
import Foundation

class AddNewProductViewModel: ObservableObject {
    
    // MARK: - 輸入 Session
    let session: SessionModel
    let onSave: () -> Void
    let onCancel: (() -> Void)?
    
    // MARK: - 編輯欄位狀態綁定
    @Published var name: String = ""
    @Published var price: String = ""
    @Published var quantity: String = ""
    @Published var selectedCategoryID: UUID?
    @Published var description: String = ""
    
    // MARK: - 圖片選擇
    @Published var image: UIImage?
    @Published var showImagePicker = false
    
    // MARK: - UI 驗證狀態
    @Published var showValidationError = false
    @Published var showDuplicateNameAlert = false
    @Published var duplicateNameMessage = ""

    var editingProduct: ProductModel?
    
    // MARK: - 用於獲取最新狀態的 DataManager
    private var transactionDataManager: TransactionDataManager?
    
    // MARK: - 計算屬性
    var sortedCategories: [CategoryModel] {
        session.categories.filter { !$0.isDisabled }.sorted(by: { $0.sortOrder < $1.sortOrder })
    }

    var selectedCategory: CategoryModel? {
        guard let id = selectedCategoryID else { return nil }
        return sortedCategories.first(where: { $0.id == id })
    }

    var pricePlaceholder: String {
        let currency = Currency(rawValue: session.currency) ?? .twd
        return "\(currency.symbol) 0"
    }
    
    /// 當前幣別
    var currentCurrency: Currency {
        return Currency(rawValue: session.currency) ?? .twd
    }
    
    /// 當前幣別是否支持小數點
    var supportsDecimal: Bool {
        return currentCurrency.decimalPlaces > 0
    }
    
    /// 當前幣別的小數位數
    var maxDecimalPlaces: Int {
        return currentCurrency.decimalPlaces
    }
    
    /// 驗證並格式化價格輸入
    func validateAndFormatPrice(_ input: String) -> String {
        // 移除非數字和小數點的字符
        let filtered = input.filter { $0.isNumber || $0 == "." }
        
        // 如果不支持小數點，移除所有小數點
        if !supportsDecimal {
            return filtered.filter { $0 != "." }
        }
        
        // 處理小數點
        let components = filtered.components(separatedBy: ".")
        
        // 如果沒有小數點或只有一個小數點
        if components.count <= 1 {
            return filtered
        }
        
        // 如果有多個小數點，只保留第一個
        if components.count > 2 {
            return components[0] + "." + components[1]
        }
        
        // 限制小數位數
        let integerPart = components[0]
        let decimalPart = components[1]
        
        if decimalPart.count > maxDecimalPlaces {
            let limitedDecimal = String(decimalPart.prefix(maxDecimalPlaces))
            return integerPart + "." + limitedDecimal
        }
        
        return filtered
    }
    
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !price.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        Decimal(string: price) != nil &&
        !quantity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        Int(quantity) != nil &&
        selectedCategory != nil // 直接使用 selectedCategory 而不是 selectedCategoryID
    }
    
    /// 檢查編輯中的產品是否有交易記錄（限制編輯）
    var isEditingWithTransaction: Bool {
        guard let product = editingProduct else { return false }
        return hasTransaction(for: product.id)
    }
    
    // MARK: - 初始化
    init(session: SessionModel,
         productToEdit: ProductModel? = nil,
         onSave: @escaping () -> Void,
         onCancel: (() -> Void)? = nil) {
        
        self.session = session
        self.onSave = onSave
        self.onCancel = onCancel
        self.editingProduct = productToEdit
        
        // 設置預設選中第一個啟用的類別
        self.selectedCategoryID = sortedCategories.first?.id

        // 如果有編輯的產品，填入現有資料
        if let product = editingProduct {
            self.name = product.name
            // 使用新的轉換方法，避免精度丟失
            let currency = Currency(rawValue: session.currency) ?? .twd
            self.price = MoneyHelper.toEditableString(product.price, currency: currency)
            self.quantity = String(product.stock)
            self.selectedCategoryID = product.categoryId
            // optional 欄位
            self.description = product.note ?? ""   // description 先初始化成原有值或空字串
            self.image = product.image
        }
    }

    // MARK: - 更新 DataManager 引用
    /// 更新 DataManager 引用
    func updateDataManagers(transactionDataManager: TransactionDataManager) {
         self.transactionDataManager = transactionDataManager
     }
    
    // MARK: - 交易檢查邏輯
    /// 檢查產品是否有交易記錄
    func hasTransaction(for productId: UUID? = nil) -> Bool {
        guard let sessionId = session.id as UUID? else { 
            return false 
        }
        
        let transactions: [TransactionModel]
        if let transactionManager = transactionDataManager {
            transactions = transactionManager.fetchTransactions(forSessionId: sessionId)
        } else {
            transactions = []
        }
        
        // 如果沒有指定 productId，檢查是否有任何交易
        guard let productId = productId else {
            return !transactions.isEmpty
        }
        
        // 檢查特定產品的交易
        return transactions.contains { transaction in
            transaction.items.contains { $0.productId == productId }
        }
    }
    
    // MARK: - 確保選中的類別是有效的
    func ensureValidCategorySelection() {
        if selectedCategory == nil {
            selectedCategoryID = sortedCategories.first?.id
        }
    }
    
    // MARK: - 依表單建立 ProductModel
    func createProductIfValid() -> ProductModel? {
        ensureValidCategorySelection()
        
        guard let category = selectedCategory,
              let priceValue = Decimal(string: price),
              let quantityValue = Int(quantity),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        
        if let editing = editingProduct {
            // 編輯模式：檢查是否有交易記錄
            if hasTransaction(for: editing.id) {
                // 有交易記錄時，保持原有的名稱、價格和類別不變
                return ProductModel(
                    id: editing.id,                    // 保留原 ID
                    sessionId: editing.sessionId,      // 保留原 sessionId
                    name: editing.name,                // 保持原名稱
                    price: editing.price,              // 保持原價格
                    stock: quantityValue,              // 允許更新庫存
                    categoryId: editing.categoryId,    // 保持原類別 ID
                    categoryName: editing.categoryName, // 保持原類別名稱
                    note: description,                 // 允許更新描述
                    imageData: image?.jpegData(compressionQuality: 0.8),// 允許更新圖片
                    isDisabled: editing.isDisabled

                )
            } else {
                // 無交易記錄時，允許更新所有欄位
                return ProductModel(
                    id: editing.id,                    // 保留原 ID
                    sessionId: editing.sessionId,      // 保留原 sessionId
                    name: name,                        // 允許更新名稱
                    price: priceValue,                 // 允許更新價格
                    stock: quantityValue,              // 允許更新庫存
                    categoryId: category.id,           // 允許更新類別 ID
                    categoryName: category.name,       // 允許更新類別名稱
                    note: description,                 // 允許更新描述
                    imageData: image?.jpegData(compressionQuality: 0.8), // 允許更新圖片
                    isDisabled: editing.isDisabled
                )
            }
        } else {
            // 新增模式
            return ProductModel(
                sessionId: session.id,
                name: name,
                price: priceValue,
                stock: quantityValue,
                categoryId: category.id,
                categoryName: category.name,
                note: description,
                imageData: image?.jpegData(compressionQuality: 0.8),
                isDisabled: false
            )
        }
    }
    
    // MARK: - 檢查產品名稱重複
    func checkDuplicateName(using productRepository: ProductRepository) -> Bool {
        guard let selectedCategory = selectedCategory,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let excludingId = editingProduct?.id // 編輯模式時排除自己
        
        // 取得該 Session 下所有產品
        let allProducts = productRepository.fetchProducts(forSessionId: session.id)
        
        // 檢查同一個 Category 內是否有同名產品
        let isDuplicate = allProducts.contains { product in
            product.categoryId == selectedCategory.id &&
            product.name == trimmedName &&
            product.id != excludingId
        }
        
        if isDuplicate {
            duplicateNameMessage = "「\(selectedCategory.name)」分類已有相同名稱的商品「\(trimmedName)」，請更換名稱"
            showDuplicateNameAlert = true
        }
        
        return isDuplicate
    }
    
    // MARK: - 儲存動作
    func save(using productRepository: ProductRepository) -> Bool {
        // 先檢查名稱重複
        if checkDuplicateName(using: productRepository) {
            return false
        }
        
        guard let product = createProductIfValid() else {
            showValidationError = true
            return false
        }
        
        if editingProduct != nil {
            // 編輯模式 → 更新產品
            productRepository.updateProduct(product.id, productModel: product)
        } else {
            // 新增模式 → 新增產品
            productRepository.addProduct(to: product.categoryId, productModel: product)
        }
        return true
    }

    
    
    // MARK: - 處理圖片選擇
    func selectImage() {
        showImagePicker = true
    }

    /// 清除圖片暫存狀態，每次開啟頁面時重置
    func clearImageTempState() {
        // 永遠重置為原始狀態，不保留暫存
        if let editingProduct = editingProduct {
            // 編輯模式：重置為產品原始圖片
            image = editingProduct.image
        } else {
            // 新增模式：清除圖片
            image = nil
        }
    }
}

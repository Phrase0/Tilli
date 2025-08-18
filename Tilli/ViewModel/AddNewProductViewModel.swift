//
//  AddNewProductViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/6/23.
//

import SwiftUI
import PhotosUI

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
    @Published var selectedItem: PhotosPickerItem?
    
    // MARK: - UI 驗證狀態
    @Published var showValidationError = false

    var editingProduct: ProductModel?
    
    // MARK: - 計算屬性
    var sortedCategories: [CategoryModel] {
        session.categories.filter { !$0.isDisabled }.sorted(by: { $0.createdAt < $1.createdAt })
    }
    
    var selectedCategory: CategoryModel? {
        guard let id = selectedCategoryID else { return nil }
        return sortedCategories.first(where: { $0.id == id })
    }
    
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !price.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        Double(price) != nil &&
        !quantity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        Int(quantity) != nil &&
        selectedCategory != nil // 直接使用 selectedCategory 而不是 selectedCategoryID
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
            self.price = String(Int(product.price.rounded()))
            self.quantity = String(product.stock)
            self.selectedCategoryID = product.categoryId
            // optional 欄位
            self.description = product.note ?? ""   // description 先初始化成原有值或空字串
            self.image = product.image
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
              let priceValue = Double(price),
              let quantityValue = Int(quantity),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        
        if let editing = editingProduct {
            return ProductModel(
                id: editing.id,                    // 保留原 ID
                sessionId: editing.sessionId,      // 保留原 sessionId
                name: name,
                price: priceValue,
                stock: quantityValue,
                categoryId: editing.categoryId,    // 保留原類別 ID
                categoryName: editing.categoryName, // 保留原類別名稱
                note: description,
                imageData: image?.jpegData(compressionQuality: 0.8)
            )
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
                imageData: image?.jpegData(compressionQuality: 0.8)
            )
        }
    }
    
    // MARK: - 儲存動作
    func save(using productDataManager: ProductDataManager) -> Bool {
        guard let product = createProductIfValid() else {
            showValidationError = true
            return false
        }
        
        if editingProduct != nil {
            // 編輯模式 → 更新產品
            productDataManager.updateProduct(product)
        } else {
            // 新增模式 → 新增產品
            productDataManager.addProduct(product)
        }
        return true
    }

    
    
    // MARK: - 處理 PhotosPicker 圖片選擇
    func handleImageSelection() {
        guard let item = selectedItem else { return }
        
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                await MainActor.run {
                    self.image = uiImage
                }
            }
        }
    }
}

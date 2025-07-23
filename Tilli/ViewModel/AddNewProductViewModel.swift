//
//  ProductViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/6/23.
//

import SwiftUI
import PhotosUI

import SwiftUI
import PhotosUI

class AddNewProductViewModel: ObservableObject {
    // MARK: - 輸入 Session & 回調
    let session: SessionModel
    let onSave: (ProductModel) -> Void
    let onCancel: (() -> Void)?
    
    // MARK: - 編輯欄位狀態綁定
    @Published var name: String = ""
    @Published var price: String = ""
    @Published var quantity: String = ""
    @Published var selectedCategory: String = ""
    @Published var description: String = ""

    // MARK: - 圖片選擇
    @Published var image: UIImage?
    @Published var selectedItem: PhotosPickerItem?
    
    // MARK: - UI 驗證狀態
    @Published var showValidationError = false
    
    // MARK: - 表單驗證
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !price.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        Double(price) != nil &&
        !quantity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        Int(quantity) != nil &&
        !selectedCategory.isEmpty
    }
    
    // MARK: - 初始化
    init(session: SessionModel, onSave: @escaping (ProductModel) -> Void, onCancel: (() -> Void)? = nil) {
        self.session = session
        self.onSave = onSave
        self.onCancel = onCancel
        // 預設選擇 Session 第一個分類
        self.selectedCategory = session.categories.first ?? ""
    }
    
    // MARK: - 依表單建立 ProductModel
    func createProductIfValid() -> ProductModel? {
        // 驗證資料有效性
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let priceValue = Double(price),
              let quantityValue = Int(quantity),
              !selectedCategory.isEmpty else {
            return nil
        }
        
        // 建立 ProductModel 實例
        return ProductModel(
            sessionId: session.id,
            name: name,
            price: priceValue,
            stock: quantityValue,
            category: selectedCategory,
            description: description,
            imageData: image?.jpegData(compressionQuality: 0.8)  // 直接轉 Data 儲存
        )
    }
    
    // MARK: - 儲存動作
    func save() -> Bool {
        guard let product = createProductIfValid() else {
            showValidationError = true
            return false
        }
        onSave(product)
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

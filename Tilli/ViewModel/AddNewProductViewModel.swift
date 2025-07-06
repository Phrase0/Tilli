//
//  ProductViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/6/23.
//

import SwiftUI
import PhotosUI

class AddNewProductViewModel: ObservableObject {
    // MARK: - Input Session & Callbacks
    let session: SessionModel
    let onSave: (ProductModel) -> Void
    let onCancel: (() -> Void)?

    // MARK: - Input Fields
    @Published var name: String = ""
    @Published var price: String = ""
    @Published var quantity: String = ""
    @Published var selectedCategory: String = ""
    @Published var description: String = ""

    // MARK: - Image Handling
    @Published var image: UIImage?
    @Published var selectedItem: PhotosPickerItem?

    // MARK: - UI State
    @Published var showValidationError = false

    // MARK: - Init
    init(session: SessionModel, onSave: @escaping (ProductModel) -> Void, onCancel: (() -> Void)? = nil) {
        self.session = session
        self.onSave = onSave
        self.onCancel = onCancel
        self.selectedCategory = session.categories.first ?? ""
    }

    // MARK: - Build Product Model
    func createProductIfValid() -> ProductModel? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let priceValue = Double(price),
              let quantityValue = Int(quantity),
              !selectedCategory.isEmpty else {
            return nil
        }

        return ProductModel(
            name: name,
            price: priceValue,
            quantity: quantityValue,
            description: description,
            image: image,
            sessionId: session.id,
            category: selectedCategory
        )
    }

    // MARK: - Save Handler
    func save() -> Bool {
        guard let product = createProductIfValid() else {
            showValidationError = true
            return false
        }

        onSave(product)
        return true
    }

    // MARK: - Handle PhotosPicker Selection
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

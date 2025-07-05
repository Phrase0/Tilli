//
//  ProductViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/6/23.
//

import SwiftUI
import PhotosUI

class AddNewProductViewModel: ObservableObject {
    let session: SessionModel
    let onSave: (ProductModel) -> Void
    let onCancel: (() -> Void)?

    @Published var name: String = ""
    @Published var price: String = ""
    @Published var quantity: String = ""
    @Published var selectedCategory: String = ""
    @Published var description: String = ""
    @Published var image: UIImage?
    @Published var selectedItem: PhotosPickerItem?
    @Published var showValidationError = false

    init(session: SessionModel, onSave: @escaping (ProductModel) -> Void, onCancel: (() -> Void)? = nil) {
        self.session = session
        self.onSave = onSave
        self.onCancel = onCancel
        self.selectedCategory = session.categories.first ?? ""
    }

    func save() -> Bool {
        guard !name.isEmpty,
              let priceValue = Double(price),
              let quantityValue = Int(quantity) else {
            showValidationError = true
            return false
        }

        let newProduct = ProductModel(
            name: name,
            price: priceValue,
            quantity: quantityValue,
            description: description,
            image: image,
            sessionId: session.id
        )

        onSave(newProduct)
        return true
    }

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


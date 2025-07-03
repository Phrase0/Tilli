//
//  Untitled.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/3.
//
import SwiftUI
import PhotosUI

struct AddNewProductView: View {
    var session: SessionModel
    var onSave: (ProductModel) -> Void

    @Environment(\.presentationMode) private var presentationMode

    @State private var name: String = ""
    @State private var price: String = ""
    @State private var quantity: String = ""
    @State private var selectedCategory: String = ""
    @State private var description: String = ""
    @State private var image: UIImage?

    @State private var selectedItem: PhotosPickerItem?
    @State private var showValidationError = false

    var body: some View {
        Form {
            Section(header: Text("基本資訊")) {
                TextField("商品名稱 *", text: $name)
                TextField("價格 *", text: $price)
                    .keyboardType(.decimalPad)
                TextField("數量 *", text: $quantity)
                    .keyboardType(.numberPad)
            }

            Section(header: Text("分類")) {
                Picker("選擇分類", selection: $selectedCategory) {
                    ForEach(session.categories, id: \.self) {
                        Text($0)
                    }
                }
            }

            Section(header: Text("描述")) {
                TextEditor(text: $description)
                    .frame(height: 100)
            }

            Section(header: Text("圖片")) {
                PhotosPicker("選擇圖片", selection: $selectedItem, matching: .images)
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 150)
                }
            }

            Button("儲存") {
                guard !name.isEmpty,
                      let priceValue = Double(price),
                      let quantityValue = Int(quantity)
                else {
                    showValidationError = true
                    return
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
                presentationMode.wrappedValue.dismiss()
            }
            .disabled(name.isEmpty || quantity.isEmpty || price.isEmpty)
        }
        .navigationTitle("新增商品")
        .alert("請確認所有必填欄位已填寫", isPresented: $showValidationError) {
            Button("知道了", role: .cancel) { }
        }
        .onChange(of: selectedItem) { newItem in
            if let item = newItem {
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        image = uiImage
                    }
                }
            }
        }
    }
}

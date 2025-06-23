//
//  AddView.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/22.
//

import SwiftUI
import PhotosUI

struct AddProductView: View {
    @ObservedObject var productViewModel: ProductViewModel
    @ObservedObject var sessionViewModel: SessionViewModel

    @State var selectedSession: SessionModel

    @State private var productName = ""
    @State private var price: Double = 0.0
    @State private var quantity: Int = 1
    @State private var description = ""
    @State private var selectedImage: UIImage? = nil
    @State private var showImagePicker = false
    @State private var showSessionSelector = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Session")) {
                    Button(action: {
                        showSessionSelector = true
                    }) {
                        HStack {
                            Text("Selected Session")
                            Spacer()
                            Text(selectedSession.title)
                                .foregroundColor(.gray)
                        }
                    }
                }

                Section(header: Text("Product Info")) {
                    TextField("Product Name", text: $productName)
                    TextField("Price", value: $price, formatter: NumberFormatter.currency)
                        .keyboardType(.decimalPad)
                    TextField("Quantity", value: $quantity, formatter: NumberFormatter())
                        .keyboardType(.numberPad)
                }

                Section(header: Text("Product Image")) {
                    Button(action: {
                        showImagePicker = true
                    }) {
                        if let image = selectedImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 150)
                                .cornerRadius(8)
                        } else {
                            VStack {
                                Image(systemName: "camera")
                                Text("Upload Image")
                            }
                            .frame(maxWidth: .infinity, minHeight: 120)
                            .foregroundColor(.gray)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                                    .foregroundColor(.gray)
                            )
                        }
                    }
                }

                Section(header: Text("Description")) {
                    TextEditor(text: $description)
                        .frame(height: 120)
                }

                Section {
                    Button(action: {
                        let newProduct = ProductModel(
                            name: productName,
                            price: price,
                            quantity: quantity,
                            description: description,
                            image: selectedImage,
                            sessionId: selectedSession.id
                        )
                        productViewModel.addProduct(newProduct)
                    }) {
                        Text("Save Product")
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(8)
                    }
                    .disabled(productName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Add New Product")
            .sheet(isPresented: $showImagePicker) {
                ImagePickerView(selectedImage: $selectedImage)
            }
            .sheet(isPresented: $showSessionSelector) {
                NavigationView {
                    List(sessionViewModel.sessions) { session in
                        Button(action: {
                            selectedSession = session
                            showSessionSelector = false
                        }) {
                            HStack {
                                Text(session.title)
                                Spacer()
                                if selectedSession.id == session.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    .navigationTitle("Select Session")
                }
            }
        }
    }
}

extension NumberFormatter {
    static var currency: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$ "
        return formatter
    }
}

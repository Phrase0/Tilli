//
//  Untitled.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/3.
//
import SwiftUI
import PhotosUI

struct AddNewProductView: View {
    @ObservedObject private var viewModel: AddNewProductViewModel
    @Environment(\.presentationMode) private var presentationMode
    
    init(session: SessionModel,
         productDataManager: ProductDataManager,
         onSave: @escaping () -> Void,
         onCancel: (() -> Void)? = nil) {
        self._viewModel = ObservedObject(wrappedValue: AddNewProductViewModel(
            session: session,
            productDataManager: productDataManager,
            onSave: onSave,
            onCancel: onCancel
        ))
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        Text("Product Name")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        TextField("Enter product name", text: $viewModel.name)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Text("Price")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        TextField("$ 0.00", text: $viewModel.price)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Text("Stock Quantity")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        TextField("Enter quantity", text: $viewModel.quantity)
                            .keyboardType(.numberPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Text("Category")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Picker("Select category", selection: $viewModel.selectedCategory) {
                            ForEach(viewModel.session.categories, id: \.self) {
                                Text($0).tag($0)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(8)
                    }
                    
                    Text("Product Image")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                            .foregroundColor(.gray.opacity(0.4))
                            .frame(height: 140)
                        
                        VStack {
                            if let image = viewModel.image {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 140)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                PhotosPicker(selection: $viewModel.selectedItem, matching: .images) {
                                    VStack(spacing: 4) {
                                        Image(systemName: "camera")
                                            .font(.title2)
                                            .foregroundColor(.gray)
                                        Text("Upload Image")
                                            .foregroundColor(.gray)
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                    }
                    
                    Text("Description")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    TextEditor(text: $viewModel.description)
                        .frame(height: 100)
                        .padding(8)
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(8)
                }
                .padding()
                .contentShape(Rectangle())
                .onTapGesture {
                    UIApplication.shared.endEditing()
                }
            }
            .navigationTitle("Add New Product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                        viewModel.onCancel?()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if viewModel.save() {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                    .disabled(!viewModel.isValid)
                }
            }
            .alert("Please complete all required fields", isPresented: $viewModel.showValidationError) {
                Button("OK", role: .cancel) { }
            }
            .onChange(of: viewModel.selectedItem) { _ in
                viewModel.handleImageSelection()
            }
        }
    }
}

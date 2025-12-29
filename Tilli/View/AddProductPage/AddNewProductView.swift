//
//  AddNewProductView.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/3.
//
import SwiftUI

struct AddNewProductView: View {

    @EnvironmentObject var productRepository: ProductRepository
    @EnvironmentObject var transactionDataManager: TransactionDataManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: AddNewProductViewModel

    var onSave: (() -> Void)?

    init(session: SessionModel,
         productToEdit: ProductModel? = nil,
         onSave: (() -> Void)? = nil) {

        _viewModel = StateObject(wrappedValue: AddNewProductViewModel(
            session: session,
            productToEdit: productToEdit
        ))
        self.onSave = onSave
    }

    var body: some View {
        let _ = viewModel.updateDataManagers(
            transactionDataManager: transactionDataManager
        )

        Form {
                // MARK: - 產品名稱
                TextField("產品名稱", text: $viewModel.name)
                    .disabled(viewModel.isEditingWithTransaction)
                    .foregroundColor(viewModel.isEditingWithTransaction ? .gray : .primary)

                // MARK: - 價格
                Section(header: Text("價格")) {
                        TextField(viewModel.pricePlaceholder, text: $viewModel.price)
                            .keyboardType(viewModel.supportsDecimal ? .decimalPad : .numberPad)
                            .disabled(viewModel.isEditingWithTransaction)
                            .foregroundColor(viewModel.isEditingWithTransaction ? .gray : .primary)
                            .onChange(of: viewModel.price) {
                                let validatedPrice = viewModel.validateAndFormatPrice(viewModel.price)
                                if validatedPrice != viewModel.price {
                                    viewModel.price = validatedPrice
                                }
                            }
                }

                // MARK: - 庫存數量
                Section(header: Text("庫存數量")) {
                        TextField("請輸入庫存數量", text: $viewModel.quantity)
                            .keyboardType(.numberPad)
                }

                // MARK: - 類別
                Section(header: Text("類別")) {
                    Menu {
                        ForEach(viewModel.sortedCategories, id: \.id) { category in
                            Button {
                                viewModel.selectedCategoryID = category.id
                            } label: {
                                HStack {
                                    Text(category.name)
                                    if viewModel.selectedCategoryID == category.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                    label: {
                        HStack {
                            Text(viewModel.sortedCategories.first { $0.id == viewModel.selectedCategoryID }?.name ?? "選擇類別")
                                .foregroundColor(viewModel.isEditingWithTransaction ? .gray : .primary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .disabled(viewModel.isEditingWithTransaction)

                    // 顯示交易限制提示
                    if viewModel.isEditingWithTransaction {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.orange)
                            Text("此產品已有交易記錄，無法更改名稱、價格和類別")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }


                // MARK: - 產品圖片
                Section(header: Text("產品圖片")) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                            .foregroundColor(.gray.opacity(0.4))
                            .aspectRatio(1, contentMode: .fit)

                        if let image = viewModel.image {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .clipped()
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                                )
                                .overlay(
                                    VStack {
                                        Spacer()
                                        HStack {
                                            Spacer()
                                            Image(systemName: "camera.fill")
                                                .foregroundColor(.white)
                                                .background(Circle().fill(Color.blue))
                                                .font(.caption)
                                                .padding(4)
                                                .padding(.trailing, 8)
                                                .padding(.bottom, 8)
                                        }
                                    }
                                )
                        } else {
                            VStack(spacing: 4) {
                                Image(systemName: "camera")
                                    .font(.title2)
                                    .foregroundColor(.gray)
                                Text("上傳圖片")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectImage()
                    }
                }

                // MARK: - 產品描述
                Section(header: Text("產品描述")) {
                    TextEditor(text: $viewModel.description)
                        .frame(height: 100)
                        .scrollContentBackground(.hidden)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
        }
        .navigationTitle(viewModel.editingProduct != nil ? "編輯產品" : "新增產品")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {

            ToolbarItem(placement: .confirmationAction) {
                Button("儲存") {
                    if viewModel.save(using: productRepository) {
                        onSave?()
                        dismiss()
                    }
                }
                .disabled(!viewModel.isValid || viewModel.sortedCategories.isEmpty)
            }
        }
        .alert("請完成所有必填欄位", isPresented: $viewModel.showValidationError) {
            Button("確定", role: .cancel) { }
        }
        .alert("產品名稱重複", isPresented: $viewModel.showDuplicateNameAlert) {
            Button("確定", role: .cancel) { }
        } message: {
            Text(viewModel.duplicateNameMessage)
        }
        .sheet(isPresented: $viewModel.showImagePicker) {
            CustomImagePicker(image: $viewModel.image, isPresented: $viewModel.showImagePicker)
        }
        .onAppear {
            viewModel.ensureValidCategorySelection()

            // 清除圖片暫存狀態，確保每次開啟都是乾淨狀態
            viewModel.clearImageTempState()
        }
    }
}

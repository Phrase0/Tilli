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
    @StateObject private var viewModel: AddNewProductViewModel


    init(session: SessionModel,
         productToEdit: ProductModel? = nil,
         onSave: @escaping () -> Void,
         onCancel: (() -> Void)? = nil) {

        _viewModel = StateObject(wrappedValue: AddNewProductViewModel(
            session: session,
            productToEdit: productToEdit,
            onSave: onSave,
            onCancel: onCancel
        ))
    }
    
    var body: some View {
        let _ = viewModel.updateDataManagers(
            transactionDataManager: transactionDataManager
        )

        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        Text("產品名稱")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        TextField("請輸入產品名稱", text: $viewModel.name)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .disabled(viewModel.isEditingWithTransaction)
                            .foregroundColor(viewModel.isEditingWithTransaction ? .gray : .primary)
                            .submitLabel(.next)

                        Text("價格")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        TextField(viewModel.pricePlaceholder, text: $viewModel.price)
                            .keyboardType(viewModel.supportsDecimal ? .decimalPad : .numberPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .disabled(viewModel.isEditingWithTransaction)
                            .foregroundColor(viewModel.isEditingWithTransaction ? .gray : .primary)
                            .submitLabel(.next)
                            .onChange(of: viewModel.price) {
                                let validatedPrice = viewModel.validateAndFormatPrice(viewModel.price)
                                if validatedPrice != viewModel.price {
                                    viewModel.price = validatedPrice
                                }
                            }


                        Text("庫存數量")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        TextField("請輸入數量", text: $viewModel.quantity)
                            .keyboardType(.numberPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .submitLabel(.done)
                            .onSubmit {
                                UIApplication.shared.endEditing()
                            }
                        
                        Text("類別")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Picker("選擇類別", selection: $viewModel.selectedCategoryID) {
                            ForEach(viewModel.sortedCategories, id: \.id) { category in
                                Text(category.name).tag(category.id as UUID?)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(8)
                        .disabled(viewModel.isEditingWithTransaction)
                        .foregroundColor(viewModel.isEditingWithTransaction ? .gray : .primary)
                    }
                    
                    Text("產品圖片")
                        .font(.subheadline)
                        .fontWeight(.semibold)

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
                    
                    Text("產品描述")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    TextEditor(text: $viewModel.description)
                        .frame(height: 100)
                        .padding(3)
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(8)
                    
                    // 顯示交易限制提示
                    if viewModel.isEditingWithTransaction {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.orange)
                            Text("此產品已有交易記錄，無法更改名稱、價格和類別")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .padding()
                    }
                }
                .padding()
                .contentShape(Rectangle())
                .onTapGesture {
                    UIApplication.shared.endEditing()
                }
            }
            .navigationTitle(viewModel.editingProduct != nil ? "編輯產品" : "新增產品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        viewModel.onCancel?()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        if viewModel.save(using: productRepository) {
                            viewModel.onSave()
                        } else {
                            print("保存失敗")
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
}

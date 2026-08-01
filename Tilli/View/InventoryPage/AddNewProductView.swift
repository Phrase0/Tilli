//
//  AddNewProductView.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/3.
//
import SwiftUI

struct AddNewProductView: View {

    @EnvironmentObject var productRepository: ProductRepository
    @EnvironmentObject var inventoryChangeRepository: InventoryChangeRepository
    @EnvironmentObject var transactionDataManager: TransactionRepository
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: AddNewProductViewModel

    enum FocusField: Hashable {
        case name
        case description
        case price
        case quantity
    }

    @FocusState private var focusedField: FocusField?

    var onSave: (() -> Void)?

    init(event: EventModel,
         productToEdit: ProductModel? = nil,
         onSave: (() -> Void)? = nil) {

        _viewModel = StateObject(wrappedValue: AddNewProductViewModel(
            event: event,
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
            Section(header: Text("addProductSectionName")) {
                TextField("addProductNamePlaceholder", text: $viewModel.name)
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .description }
                    .disabled(viewModel.isEditingWithTransaction)
                    .foregroundColor(viewModel.isEditingWithTransaction ? DesignSystem.ColorToken.muted : DesignSystem.ColorToken.ink)
                    .onChange(of: viewModel.name) {
                        viewModel.enforceProductNameLimit()
                    }

                if !viewModel.isEditingWithTransaction {
                    HStack {
                        Text("\(viewModel.name.count)/\(viewModel.productNameMaxLength)")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(viewModel.productNameRemainingCharacters <= 5 ? DesignSystem.ColorToken.alertRed : DesignSystem.ColorToken.muted)
                    }
                }
            }

            // MARK: - 產品描述
            Section(header: Text("addProductSectionDescription")) {
                TextField("addProductDescriptionPlaceholder", text: $viewModel.description)
                    .focused($focusedField, equals: .description)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .price }
                    .onChange(of: viewModel.description) {
                        viewModel.enforceProductDescriptionLimit()
                    }

                HStack {
                    Text("\(viewModel.description.count)/\(viewModel.productDescriptionMaxLength)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(viewModel.productDescriptionRemainingCharacters <= 5 ? DesignSystem.ColorToken.alertRed : DesignSystem.ColorToken.muted)
                }
            }

            // MARK: - 價格
            Section(header: Text("addProductSectionPrice")) {
                TextField(viewModel.pricePlaceholder, text: $viewModel.price)
                    .keyboardType(viewModel.supportsDecimal ? .decimalPad : .numberPad)
                    .focused($focusedField, equals: .price)
                    .disabled(viewModel.isEditingWithTransaction)
                    .foregroundColor(viewModel.isEditingWithTransaction ? DesignSystem.ColorToken.muted : DesignSystem.ColorToken.ink)
                    .onChange(of: viewModel.price) {
                        let validatedPrice = viewModel.validateAndFormatPrice(viewModel.price)
                        if validatedPrice != viewModel.price {
                            viewModel.price = validatedPrice
                        }
                    }

                if viewModel.shouldShowPriceHint && !viewModel.isEditingWithTransaction {
                    Text(viewModel.priceHintText)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.alertRed)
                }
            }

            // MARK: - 庫存數量
            Section(header: Text("addProductSectionStock")) {
                TextField("addProductStockPlaceholder", text: $viewModel.quantity)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .quantity)
                    .onChange(of: viewModel.quantity) {
                        let validatedQuantity = viewModel.validateAndFormatQuantity(viewModel.quantity)
                        if validatedQuantity != viewModel.quantity {
                            viewModel.quantity = validatedQuantity
                        }
                        viewModel.updateDefaultReasonIfNeeded()
                    }

                if viewModel.shouldShowStockHint {
                    Text(viewModel.stockHintText)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.alertRed)
                }

                if viewModel.shouldShowReasonPicker {
                    Picker("addProductReasonLabel", selection: $viewModel.stockChangeReason) {
                        ForEach(viewModel.availableReasons, id: \.self) { reason in
                            Text(reason.displayName).tag(reason)
                        }
                    }

                    if viewModel.stockChangeReason == .adjustment {
                        TextField("addProductCustomReasonPlaceholder", text: $viewModel.customChangeReason)
                    }

                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(DesignSystem.ColorToken.muted)
                        Text("addProductStockChangeInfo \(viewModel.originalStock) \(Int(viewModel.quantity) ?? 0) \(viewModel.stockDeltaText)")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.ColorToken.muted)
                    }
                }
            }

            // MARK: - 類別
            Section(header: Text("addProductSectionCategory")) {
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
                        Text(viewModel.sortedCategories.first { $0.id == viewModel.selectedCategoryID }?.name ?? String(localized: "addProductCategoryPlaceholder"))
                            .foregroundColor(viewModel.isEditingWithTransaction ? DesignSystem.ColorToken.muted : DesignSystem.ColorToken.ink)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.ColorToken.muted)
                    }
                }
                .disabled(viewModel.isEditingWithTransaction)

                if viewModel.isEditingWithTransaction {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(DesignSystem.ColorToken.alertRed)
                        Text("addProductTransactionRestriction")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.ColorToken.alertRed)
                    }
                }
            }


            // MARK: - 產品圖片
            Section(header: Text("addProductSectionImage")) {
                ZStack {
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                        .foregroundColor(DesignSystem.ColorToken.muted.opacity(0.4))
                        .aspectRatio(1, contentMode: .fit)

                    if let image = viewModel.image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipped()
                            .cornerRadius(DesignSystem.Radius.sm)
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                                    .stroke(DesignSystem.Border.cardColor, lineWidth: DesignSystem.Border.cardWidth)
                            )
                            .overlay(
                                VStack {
                                    Spacer()
                                    HStack {
                                        Spacer()
                                        Image(systemName: "camera.fill")
                                            .foregroundColor(DesignSystem.ColorToken.onButtonFilled)
                                            .background(Circle().fill(DesignSystem.ColorToken.buttonFilled))
                                            .font(DesignSystem.Typography.caption)
                                            .padding(DesignSystem.Spacing.xxs)
                                            .padding(.trailing, DesignSystem.Spacing.xs)
                                            .padding(.bottom, DesignSystem.Spacing.xs)
                                    }
                                }
                            )
                    } else {
                        VStack(spacing: DesignSystem.Spacing.xxs) {
                            Image(systemName: "camera")
                                .font(.title2)
                                .foregroundColor(DesignSystem.ColorToken.muted)
                            Text("addProductUploadImage")
                                .foregroundColor(DesignSystem.ColorToken.muted)
                                .font(DesignSystem.Typography.caption)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.selectImage()
                }
            }
        }
        .navigationTitle(viewModel.editingProduct == nil
            ? String(localized: "addProductNavTitleNew")
            : String(localized: "addProductNavTitleEdit"))
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if focusedField == .price || focusedField == .quantity {
                    Spacer()
                    Button("commonDone") {
                        if focusedField == .price {
                            focusedField = .quantity
                        } else {
                            focusedField = nil
                        }
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("addProductSave") {
                    if viewModel.save(using: productRepository,
                                      inventoryChangeRepository: inventoryChangeRepository) {
                        onSave?()
                        dismiss()
                    }
                }
                .disabled(!viewModel.isValid || viewModel.sortedCategories.isEmpty)
            }
        }
        .alert("addProductValidationError", isPresented: $viewModel.showValidationError) {
            Button("commonConfirm", role: .cancel) { }
        }
        .alert("addProductDuplicateNameTitle", isPresented: $viewModel.showDuplicateNameAlert) {
            Button("commonConfirm", role: .cancel) { }
        } message: {
            Text(viewModel.duplicateNameMessage)
        }
        .sheet(isPresented: $viewModel.showImagePicker) {
            CustomImagePicker(image: $viewModel.image, isPresented: $viewModel.showImagePicker)
        }
        .onAppear {
            viewModel.ensureValidCategorySelection()
            viewModel.clearImageTempState()

            if viewModel.editingProduct == nil {
                focusedField = .name
            }
        }
    }
}

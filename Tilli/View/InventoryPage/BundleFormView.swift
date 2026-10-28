//
//  BundleFormView.swift
//  Tilli
//
//  新增／編輯套餐或組合（設計 §4.2）。表單內沒有停用開關與刪除鈕（在管理頁 ⋯ 選單）。
//

import SwiftUI

struct BundleFormView: View {

    @EnvironmentObject private var eventRepository: EventRepository
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: BundleFormViewModel

    @FocusState private var focusedField: Field?
    /// 按過一次儲存後才列出錯誤，避免剛打開表單就一片紅字
    @State private var attemptedSave = false

    private enum Field: Hashable { case name, price }

    var onSave: (() -> Void)?

    init(kind: BundleKind, editing: BundleModel? = nil, event: EventModel, products: [ProductModel], onSave: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: BundleFormViewModel(
            kind: kind, editing: editing, event: event, products: products
        ))
        self.onSave = onSave
    }

    private var isFixed: Bool { viewModel.kind == .fixed }

    var body: some View {
        Form {
            if isFixed {
                photoSection
            }

            // 名稱
            Section(header: Text("bundleFormSectionName")) {
                // 請輸入名稱
                TextField("bundleFormNamePlaceholder", text: $viewModel.name)
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .price }
            }

            priceSection

            if !isFixed {
                Section {
                    Stepper(value: $viewModel.count, in: BundleFormViewModel.countRange) {
                        // 任選 %lld 個
                        Text("bundleChooseCount \(viewModel.count)")
                    }
                }
            }

            productSection

            if attemptedSave && !viewModel.errorMessages.isEmpty {
                Section {
                    ForEach(viewModel.errorMessages, id: \.self) { message in
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.ColorToken.alertRed)
                    }
                }
            }

            Section {
                Button {
                    save()
                } label: {
                    // 儲存
                    Text("bundleFormSave")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(navigationTitle)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if focusedField == .price {
                    Spacer()
                    Button("commonDone") { focusedField = nil }
                }
            }
        }
        // 提醒 / 儲存失敗，請再試一次
        .alert("commonReminder", isPresented: $viewModel.showSaveFailedAlert) {
            Button("commonConfirm", role: .cancel) { }
        } message: {
            Text("bundleSaveFailed")
        }
        .sheet(isPresented: $viewModel.showImagePicker) {
            CustomImagePicker(image: $viewModel.image, isPresented: $viewModel.showImagePicker)
        }
        .onAppear {
            if viewModel.editing == nil { focusedField = .name }
        }
    }

    private var navigationTitle: String {
        switch (viewModel.kind, viewModel.editing == nil) {
        case (.fixed, true):
            // 新增套餐
            return String.localized("bundleAddMenuFixed")
        case (.chooseAny, true):
            // 新增組合
            return String.localized("bundleAddMenuCombo")
        case (.fixed, false):
            // 編輯套餐
            return String.localized("bundleFormTitleEditFixed")
        case (.chooseAny, false):
            // 編輯組合
            return String.localized("bundleFormTitleEditCombo")
        }
    }

    private func save() {
        attemptedSave = true
        focusedField = nil
        if viewModel.save(using: eventRepository) {
            onSave?()
            dismiss()
        }
    }

    // MARK: - 照片（僅套餐，選填；樣式同新增商品）

    private var photoSection: some View {
        // 照片（選填）
        Section(header: Text("bundleFormSectionPhoto")) {
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
                } else {
                    VStack(spacing: DesignSystem.Spacing.xxs) {
                        Image(systemName: "camera")
                            .font(.title2)
                            .foregroundColor(DesignSystem.ColorToken.muted)
                        // 上傳圖片
                        Text("addProductUploadImage")
                            .foregroundColor(DesignSystem.ColorToken.muted)
                            .font(DesignSystem.Typography.caption)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { viewModel.showImagePicker = true }

            if viewModel.image != nil {
                Button(role: .destructive) {
                    viewModel.image = nil
                } label: {
                    // 移除照片
                    Text("bundleRemovePhoto")
                }
            }
        }
    }

    // MARK: - 價格

    private var priceSection: some View {
        // 價格
        Section(header: Text("bundleFormSectionPrice")) {
            TextField(viewModel.pricePlaceholder, text: $viewModel.priceText)
                .keyboardType(viewModel.supportsDecimal ? .decimalPad : .numberPad)
                .focused($focusedField, equals: .price)
                .onChange(of: viewModel.priceText) {
                    viewModel.sanitizePrice()
                }

            if let hint = viewModel.originalTotalHint {
                Text(hint)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.ColorToken.muted)
            }

            if viewModel.showsNoDiscountHint {
                HStack(spacing: DesignSystem.Spacing.xxs) {
                    Image(systemName: "info.circle")
                    // 這個價格沒有優惠
                    Text("bundleNoDiscountHint")
                }
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.ColorToken.muted)
            }
        }
    }

    // MARK: - 成員／候選商品勾選

    private var productSection: some View {
        // 套餐成員（各 1 個）／候選商品
        Section(header: Text(isFixed ? "bundleFormSectionMembers" : "bundleFormSectionCandidates")) {
            ForEach(viewModel.selectableProducts) { product in
                productRow(product)
            }
        }
    }

    private func productRow(_ product: ProductModel) -> some View {
        let isSelected = viewModel.isSelected(product.id)
        let isUnavailable = viewModel.isUnavailable(product)
        return Button {
            viewModel.toggle(product.id)
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? DesignSystem.ColorToken.ink : DesignSystem.ColorToken.muted)

                Text(product.name)
                    .foregroundColor(isUnavailable ? DesignSystem.ColorToken.muted : DesignSystem.ColorToken.ink)
                    .lineLimit(1)

                if isUnavailable {
                    // 已下架
                    Text("bundleMemberDisabledTag")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.muted)
                        .padding(.horizontal, DesignSystem.Spacing.xs)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(DesignSystem.ColorToken.quietFill))
                }

                Spacer()

                Text(product.price.money(currency: viewModel.currency.rawValue))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.ColorToken.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

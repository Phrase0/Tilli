//
//  AddSessionView.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/23.
//

import SwiftUI

struct AddSessionView: View {

    @StateObject private var viewModel: AddSessionViewModel
    var onSave: (SessionModel) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var transactionDataManager: TransactionRepository
    @EnvironmentObject var productRepository: ProductRepository

    enum FocusField: Hashable {
        case sessionName
        case newCategory
        case editingCategory
        case newDiscount
    }

    @FocusState private var focusedField: FocusField?

    init(sessionToEdit: SessionModel? = nil, onSave: @escaping (SessionModel) -> Void) {
        self._viewModel = StateObject(wrappedValue: AddSessionViewModel(sessionToEdit: sessionToEdit))
        self.onSave = onSave
    }

    var body: some View {
        let _ = viewModel.updateDataManagers(
            transactionDataManager: transactionDataManager,
            productRepository: productRepository
        )

        Form {
            // 場次名稱
            Section(header: Text("addSessionNameHeader")) {
                // 請輸入場次名稱
                TextField("addSessionNamePlaceholder", text: $viewModel.sessionName)
                    .focused($focusedField, equals: .sessionName)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .newCategory }
                    .onChange(of: viewModel.sessionName) {
                        viewModel.enforceSessionNameLimit()
                    }

                HStack {
                    Text("\(viewModel.sessionName.count)/\(viewModel.sessionNameMaxLength)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(viewModel.sessionNameRemainingCharacters <= 5
                                         ? DesignSystem.ColorToken.alertRed : DesignSystem.ColorToken.muted)
                }
            }

            // 場次類型
            Section {
                // 場次類型
                Picker("addSessionDateTypeLabel", selection: $viewModel.dateType) {
                    // 單日
                    Text("eventsDateTypeSingle").tag(SessionDateType.single)
                    // 多日
                    Text("eventsDateTypeMulti").tag(SessionDateType.multi)
                    // 無限期
                    Text("eventsDateTypePermanent").tag(SessionDateType.permanent)
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.dateType) { _, newType in
                    if newType == .multi {
                        viewModel.endDate = Calendar.current.date(byAdding: .day, value: 1, to: viewModel.sessionDate) ?? viewModel.sessionDate
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

            // 日期
            Section {
                switch viewModel.dateType {
                case .single:
                    // 日期
                    DatePicker("eventsDuplicateDate", selection: $viewModel.sessionDate, displayedComponents: .date)

                case .multi:
                    // 開始日期
                    DatePicker("eventsDuplicateStartDate", selection: $viewModel.sessionDate, displayedComponents: .date)
                        .onChange(of: viewModel.sessionDate) { _, newStartDate in
                            if viewModel.endDate <= newStartDate {
                                viewModel.endDate = Calendar.current.date(byAdding: .day, value: 1, to: newStartDate) ?? newStartDate
                            }
                        }

                    // 結束日期
                    DatePicker(
                        "eventsDuplicateEndDate",
                        selection: $viewModel.endDate,
                        in: viewModel.endDateRange,
                        displayedComponents: .date
                    )

                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(DesignSystem.ColorToken.muted)
                            .font(DesignSystem.Typography.caption)
                        // 多日場次最多 31 天
                        Text("eventsDuplicateMultiDayLimit")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.ColorToken.muted)
                    }

                case .permanent:
                    // 開始日期
                    DatePicker("eventsDuplicateStartDate", selection: $viewModel.sessionDate, displayedComponents: .date)

                    HStack {
                        Image(systemName: "infinity")
                            .foregroundColor(DesignSystem.ColorToken.muted)
                        // 此場次無結束日期
                        Text("eventsDuplicatePermanentHint")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.ColorToken.muted)
                    }
                }

                if viewModel.editingSession != nil && viewModel.transactionCount > 0 {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(DesignSystem.ColorToken.muted)
                            // 此場次已有 N 筆交易
                            Text("addSessionTransactionCount \(viewModel.transactionCount)")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.ColorToken.muted)
                        }

                        let dateValidation = viewModel.validateDates()
                        if !dateValidation.isValid, let errorMessage = dateValidation.errorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(DesignSystem.ColorToken.alertRed)
                                    .font(DesignSystem.Typography.caption)

                                Text(errorMessage)
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.ColorToken.alertRed)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // 幣別
            Picker("addSessionCurrencyLabel", selection: $viewModel.selectedCurrency) {
                ForEach(Currency.allCases, id: \.self) { currency in
                    Text(currency.displayName)
                        .tag(currency.rawValue)
                }
            }
            .disabled(viewModel.isEditingWithTransaction)

            if viewModel.isEditingWithTransaction {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(DesignSystem.ColorToken.muted)
                    // 此場次已有交易記錄，無法更改幣別
                    Text("addSessionCurrencyLocked")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.muted)
                }
            }

            // 類別
            Section(header: Text("addSessionCategoryHeader")) {
                ForEach(viewModel.activeSortedCategories, id: \.id) { category in
                    categoryRow(for: category)
                        .id(category.id)
                        .swipeActions(edge: .trailing) {
                            swipeActionsContent(for: category)
                        }
                }
                .onMove { from, to in
                    viewModel.moveCategory(from: from, to: to)
                }

                HStack {
                    // 新增類別
                    TextField("addSessionNewCategoryPlaceholder", text: $viewModel.newCategory)
                        .focused($focusedField, equals: .newCategory)
                        .submitLabel(.done)
                        .onSubmit {
                            if viewModel.newCategory.trimmingCharacters(in: .whitespaces).isEmpty {
                                focusedField = nil
                            } else {
                                addCategoryAction()
                            }
                        }

                    if !viewModel.newCategory.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button {
                            addCategoryAction()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(DesignSystem.ColorToken.ink)
                        }
                    }
                }
                .frame(height: 36)

                if viewModel.showCategoryEditWarning {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(DesignSystem.ColorToken.muted)
                        // 此類別已有交易紀錄，無法更改名稱
                        Text("addSessionCategoryEditWarning")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.ColorToken.muted)
                    }
                }
            }

            // 折扣
            Section(header: Text("addSessionDiscountHeader")) {
                ForEach(viewModel.discounts) { discount in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(DesignSystem.ColorToken.muted)
                        Text(discount.displayText(currency: viewModel.selectedCurrency))
                    }
                }
                .onMove { from, to in
                    viewModel.moveDiscount(from: from, to: to)
                }
                .onDelete { indexSet in
                    indexSet.forEach { index in
                        viewModel.deleteDiscount(viewModel.discounts[index])
                    }
                }

                HStack(spacing: DesignSystem.Spacing.sm) {
                    // 數值
                    TextField("addSessionDiscountValuePlaceholder", text: $viewModel.newDiscountValue)
                        .keyboardType(.numberPad)
                        .frame(width: 80)
                        .focused($focusedField, equals: .newDiscount)
                        .submitLabel(.done)
                        .onSubmit {
                            addDiscountAction()
                        }

                    // 類型
                    Picker("addSessionDiscountTypeLabel", selection: $viewModel.newDiscountType) {
                        Text("%").tag(DiscountType.percentage)
                        Text(viewModel.currentCurrency.symbol).tag(DiscountType.amount)
                    }
                    .pickerStyle(.segmented)

                    if !viewModel.newDiscountValue.isEmpty {
                        Button {
                            addDiscountAction()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(DesignSystem.ColorToken.ink)
                        }
                    }
                }
                .frame(height: 36)
            }

            // 已停用類別
            Section(header: Text("addSessionDisabledCategoryHeader")) {
                ForEach(viewModel.disabledSortedCategories, id: \.id) { category in
                    Text(category.name)
                        .foregroundColor(DesignSystem.ColorToken.muted)
                        .swipeActions(edge: .trailing) {
                            // 復原
                            Button("addSessionRestore") {
                                viewModel.handleRestoreAction(for: category.id)
                            }
                            .tint(DesignSystem.ColorToken.marketGreen)
                        }
                }
            }
        }
        // 新增場次 / 編輯場次
        .navigationTitle(viewModel.editingSession == nil
                         ? String(localized: "addSessionTitle")
                         : String(localized: "addSessionEditTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if focusedField == .newDiscount {
                    Spacer()
                    // 完成
                    Button("commonDone") {
                        if viewModel.newDiscountValue.trimmingCharacters(in: .whitespaces).isEmpty {
                            focusedField = nil
                        } else {
                            addDiscountAction()
                        }
                    }
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                // 取消
                Button("commonCancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                // 儲存
                Button("addSessionSave") {
                    switch viewModel.validateSave() {
                    case .success:
                        let session = viewModel.save()
                        onSave(session)
                        dismiss()
                    case .failure(let error):
                        viewModel.alertMessage = error
                        viewModel.showAlert = true
                    }
                }
                .disabled(
                    viewModel.sessionName.trimmingCharacters(in: .whitespaces).isEmpty ||
                    !viewModel.validateDates().isValid
                )
            }
        }
        .alert(isPresented: $viewModel.showAlert) {
            viewModel.createAlert()
        }
        .onChange(of: focusedField) { oldValue, newValue in
            if oldValue == .editingCategory {
                if let error = viewModel.finishEditingCategory() {
                    viewModel.alertMessage = error
                    viewModel.showAlert = true
                }
            }
            if newValue == .newCategory {
                viewModel.showCategoryEditWarning = false
            }
        }
        .onAppear {
            if viewModel.editingSession == nil {
                focusedField = .sessionName
            }
        }
    }

    // MARK: - Helper Methods

    private func addCategoryAction() {
        if let error = viewModel.tryAddCategory() {
            viewModel.alertMessage = error
            viewModel.showAlert = true
        } else {
            focusedField = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = .newCategory
            }
        }
    }

    private func addDiscountAction() {
        if let error = viewModel.tryAddDiscount() {
            viewModel.alertMessage = error
            viewModel.showAlert = true
        } else {
            focusedField = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = .newDiscount
            }
        }
    }

    @ViewBuilder
    private func categoryRow(for category: CategoryModel) -> some View {
        let canEdit = viewModel.canEditCategoryName(for: category.id)
        if viewModel.editingCategoryID == category.id && canEdit {
            HStack {
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(DesignSystem.ColorToken.muted)
                // 類別名稱
                TextField("addSessionCategoryNamePlaceholder", text: Binding(
                    get: {
                        viewModel.categories.first(where: { $0.id == category.id })?.name ?? ""
                    },
                    set: { newValue in
                        viewModel.updateCategoryName(id: category.id, newName: newValue)
                    }
                ))
                .focused($focusedField, equals: .editingCategory)
                .onSubmit {
                    focusedField = nil
                }
            }
        } else {
            HStack {
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(DesignSystem.ColorToken.muted)
                Text(category.name)
                    .foregroundColor(canEdit ? DesignSystem.ColorToken.ink : DesignSystem.ColorToken.muted)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if canEdit {
                    viewModel.showCategoryEditWarning = false
                    if let error = viewModel.startEditingCategory(id: category.id) {
                        viewModel.alertMessage = error
                        viewModel.showAlert = true
                    }
                    focusedField = .editingCategory
                } else {
                    viewModel.showCategoryEditWarning = true
                }
            }
        }
    }

    @ViewBuilder
    private func swipeActionsContent(for category: CategoryModel) -> some View {
        switch viewModel.getSwipeAction(for: category) {
        case .disable:
            // 停用
            Button("addSessionDisable") {
                viewModel.handleDisableAction(for: category.id)
            }
            .tint(DesignSystem.ColorToken.muted)
        case .delete:
            // 刪除
            Button("commonDelete", role: .destructive) {
                viewModel.handleDeleteAction(for: category)
            }
        }
    }
}

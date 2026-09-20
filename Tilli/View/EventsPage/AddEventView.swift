//
//  AddEventView.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/23.
//

import SwiftUI

struct AddEventView: View {

    @StateObject private var viewModel: AddEventViewModel
    var onSave: (EventModel) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var transactionDataManager: TransactionRepository
    @EnvironmentObject var productRepository: ProductRepository

    enum FocusField: Hashable {
        case eventName
        case newCategory
        case editingCategory
        case newPercentageDiscount
        case newAmountDiscount
    }

    @FocusState private var focusedField: FocusField?

    init(eventToEdit: EventModel? = nil, onSave: @escaping (EventModel) -> Void) {
        self._viewModel = StateObject(wrappedValue: AddEventViewModel(eventToEdit: eventToEdit))
        self.onSave = onSave
    }

    var body: some View {
        let _ = viewModel.updateDataManagers(
            transactionDataManager: transactionDataManager,
            productRepository: productRepository
        )

        Form {
            // 場次名稱
            Section(header: Text("addEventNameHeader")) {
                // 請輸入場次名稱
                TextField("addEventNamePlaceholder", text: $viewModel.eventName)
                    .focused($focusedField, equals: .eventName)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .newCategory }
                    .onChange(of: viewModel.eventName) {
                        viewModel.enforceEventNameLimit()
                    }

                HStack {
                    Text("\(viewModel.eventName.count)/\(viewModel.eventNameMaxLength)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(viewModel.eventNameRemainingCharacters <= 5
                                         ? DesignSystem.ColorToken.alertRed : DesignSystem.ColorToken.muted)
                }
            }

            // 場次類型
            Section {
                // 場次類型
                Picker("addEventDateTypeLabel", selection: $viewModel.dateType) {
                    // 單日
                    Text("eventsDateTypeSingle").tag(EventDateType.single)
                    // 多日
                    Text("eventsDateTypeMulti").tag(EventDateType.multi)
                    // 無限期
                    Text("eventsDateTypePermanent").tag(EventDateType.permanent)
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.dateType) { _, newType in
                    if newType == .multi {
                        viewModel.endDate = Calendar.current.date(byAdding: .day, value: 1, to: viewModel.eventDate) ?? viewModel.eventDate
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
                    DatePicker("eventsDuplicateDate", selection: $viewModel.eventDate, displayedComponents: .date)

                case .multi:
                    // 開始日期
                    DatePicker("eventsDuplicateStartDate", selection: $viewModel.eventDate, displayedComponents: .date)
                        .onChange(of: viewModel.eventDate) { _, newStartDate in
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
                    DatePicker("eventsDuplicateStartDate", selection: $viewModel.eventDate, displayedComponents: .date)

                    HStack {
                        Image(systemName: "infinity")
                            .foregroundColor(DesignSystem.ColorToken.muted)
                        // 此場次無結束日期
                        Text("eventsDuplicatePermanentHint")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.ColorToken.muted)
                    }
                }

                if viewModel.editingEvent != nil && viewModel.transactionCount > 0 {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(DesignSystem.ColorToken.muted)
                            // 此場次已有 N 筆交易
                            Text("addEventTransactionCount \(viewModel.transactionCount)")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.ColorToken.muted)
                        }

                        let dateValidation = viewModel.validateDates()
                        if !dateValidation.isValid, let errorMessage = dateValidation.errorMessage {
                            HStack(spacing: DesignSystem.Spacing.xxs) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(DesignSystem.ColorToken.alertRed)
                                    .font(DesignSystem.Typography.caption)

                                Text(errorMessage)
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.ColorToken.alertRed)
                            }
                        }
                    }
                    .padding(.vertical, DesignSystem.Spacing.xxs)
                }
            }

            // 幣別
            Picker("addEventCurrencyLabel", selection: $viewModel.selectedCurrency) {
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
                    Text("addEventCurrencyLocked")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.muted)
                }
            }

            // 類別
            Section(header: Text("addEventCategoryHeader")) {
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
                    TextField("addEventNewCategoryPlaceholder", text: $viewModel.newCategory)
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
                        Text("addEventCategoryEditWarning")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.ColorToken.muted)
                    }
                }
            }

            // 已停用類別（接在類別下方；沒有停用類別時整個 Section 不顯示）
            if !viewModel.disabledSortedCategories.isEmpty {
                Section(header: Text("addEventDisabledCategoryHeader")) {
                    ForEach(viewModel.disabledSortedCategories, id: \.id) { category in
                        Text(category.name)
                            .foregroundColor(DesignSystem.ColorToken.muted)
                            .swipeActions(edge: .trailing) {
                                // 復原
                                Button("addEventRestore") {
                                    viewModel.handleRestoreAction(for: category.id)
                                }
                                .tint(DesignSystem.ColorToken.marketGreen)
                            }
                    }
                }
            }

            // 百分比折扣
            Section(header: Text("discountPercentageHeader")) {
                discountRows(viewModel.percentageDiscounts)
                discountInputRow(type: .percentage, focus: .newPercentageDiscount, unit: "%")
            }

            // 減額折扣
            Section(header: Text("discountAmountHeader")) {
                discountRows(viewModel.amountDiscounts)
                discountInputRow(type: .amount, focus: .newAmountDiscount)
            }
        }
        // 新增場次 / 編輯場次
        .navigationTitle(viewModel.editingEvent == nil
                         ? String.localized("addEventTitle")
                         : String.localized("addEventEditTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if focusedDiscountType != nil {
                    Spacer()
                    // 完成 —— 只收起鍵盤。要新增請按輸入列右邊的 +
                    //（沒按 + 的輸入會在儲存時自動補送，見 validateSave）
                    Button("commonDone") {
                        focusedField = nil
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
                Button("addEventSave") {
                    switch viewModel.validateSave() {
                    case .success:
                        let event = viewModel.save()
                        onSave(event)
                        dismiss()
                    case .failure(let error):
                        viewModel.alertMessage = error
                        viewModel.showAlert = true
                    }
                }
                .disabled(
                    viewModel.eventName.trimmingCharacters(in: .whitespaces).isEmpty ||
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
            if viewModel.editingEvent == nil {
                focusedField = .eventName
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

    /// 目前游標在哪一區的折扣輸入欄
    private var focusedDiscountType: DiscountType? {
        switch focusedField {
        case .newPercentageDiscount: return .percentage
        case .newAmountDiscount: return .amount
        default: return nil
        }
    }

    @ViewBuilder
    private func discountRows(_ discounts: [DiscountModel]) -> some View {
        ForEach(discounts) { discount in
            Text(discount.displayText(currency: viewModel.selectedCurrency))
        }
        .onDelete { indexSet in
            indexSet.forEach { viewModel.deleteDiscount(discounts[$0]) }
        }
    }

    /// 折扣輸入列。型別由「在哪一區輸入」決定，不需要再選。
    ///
    /// `unit` 只有百分比用得到（`%`）；減額折扣不顯示幣別尾段 ——
    /// Section 標題已經說了是減額，再掛一個 `NT$` 只是雜訊。
    private func discountInputRow(
        type: DiscountType,
        focus: FocusField,
        unit: String? = nil
    ) -> some View {
        let hasInput = !viewModel.newValue(for: type).trimmingCharacters(in: .whitespaces).isEmpty

        return HStack(spacing: DesignSystem.Spacing.sm) {
            // 數值
            TextField(
                "addEventDiscountValuePlaceholder",
                text: type == .percentage ? $viewModel.newPercentageValue : $viewModel.newAmountValue
            )
            .keyboardType(.numberPad)
            .frame(width: 80)
            .focused($focusedField, equals: focus)
            .submitLabel(.done)
            .onSubmit { addDiscountAction(type: type) }

            if let unit {
                Text(unit)
                    .foregroundColor(DesignSystem.ColorToken.muted)
            }

            Spacer()

            // + 固定在最右方，沒輸入時變灰且不可按 —— 讓「要按這裡新增」一直看得見
            Button {
                addDiscountAction(type: type)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(hasInput
                                     ? DesignSystem.ColorToken.ink
                                     : DesignSystem.ColorToken.muted)
            }
            .disabled(!hasInput)
        }
        .frame(height: 36)
    }

    private func addDiscountAction(type: DiscountType) {
        if let error = viewModel.tryAddDiscount(type: type) {
            viewModel.alertMessage = error
            viewModel.showAlert = true
        } else {
            // 新增成功後把游標留在同一區，方便連續輸入
            let field: FocusField = type == .percentage ? .newPercentageDiscount : .newAmountDiscount
            focusedField = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = field
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
                TextField("addEventCategoryNamePlaceholder", text: Binding(
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
            Button("addEventDisable") {
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

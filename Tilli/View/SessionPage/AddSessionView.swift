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
    
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject var transactionDataManager: TransactionDataManager
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
            Section(header: Text("場次名稱")) {
                TextField("請輸入場次名稱", text: $viewModel.sessionName)
                    .focused($focusedField, equals: .sessionName)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .newCategory }
                    .onChange(of: viewModel.sessionName) {
                        viewModel.enforceSessionNameLimit()
                    }

                // 剩餘字數提示
                HStack {
                    Text("\(viewModel.sessionName.count)/\(viewModel.sessionNameMaxLength)")
                        .font(.caption)
                        .foregroundColor(viewModel.sessionNameRemainingCharacters <= 5 ? .orange : .secondary)
                }
            }
            // 場次類型選擇器
            Section {
                Picker("場次類型", selection: $viewModel.dateType) {
                    Text("單日").tag(SessionDateType.single)
                    Text("多日").tag(SessionDateType.multi)
                    Text("無限期").tag(SessionDateType.permanent)
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.dateType) { _, newType in
                    // 切換到多日時，自動設定結束日期為開始日期 +1 天
                    if newType == .multi {
                        viewModel.endDate = Calendar.current.date(byAdding: .day, value: 1, to: viewModel.sessionDate) ?? viewModel.sessionDate
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0,bottom: 0, trailing: 0))
            // 動態日期選擇器
            Section {
                switch viewModel.dateType {
                case .single:
                    DatePicker("日期", selection: $viewModel.sessionDate, displayedComponents: .date)

                case .multi:
                    DatePicker(
                        "開始日期",
                        selection: $viewModel.sessionDate,
                        displayedComponents: .date
                    )
                    .onChange(of: viewModel.sessionDate) { _, newStartDate in
                        // 結束日期必須至少是開始日期的隔天
                        if viewModel.endDate <= newStartDate {
                            viewModel.endDate = Calendar.current.date(byAdding: .day, value: 1, to: newStartDate) ?? newStartDate
                        }
                    }

                    DatePicker(
                        "結束日期",
                        selection: $viewModel.endDate,
                        in: viewModel.endDateRange,
                        displayedComponents: .date
                    )

                    // 多日場次提示
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text("多日場次最多 31 天")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                case .permanent:
                    DatePicker("開始日期", selection: $viewModel.sessionDate, displayedComponents: .date)

                    HStack {
                        Image(systemName: "infinity")
                            .foregroundColor(.purple)
                        Text("此場次無結束日期")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // 編輯時顯示交易筆數和提示
                if viewModel.editingSession != nil && viewModel.transactionCount > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("此場次已有 \(viewModel.transactionCount) 筆交易")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // 顯示日期驗證錯誤
                        let dateValidation = viewModel.validateDates()
                        if !dateValidation.isValid, let errorMessage = dateValidation.errorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)

                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // 幣別選擇器
            Picker("幣別", selection: $viewModel.selectedCurrency) {
                ForEach(Currency.allCases, id: \.self) { currency in
                    Text(currency.displayName)
                        .tag(currency.rawValue)
                }
            }
            .disabled(viewModel.isEditingWithTransaction)
            
            // 有交易記錄時顯示提示
            if viewModel.isEditingWithTransaction {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.orange)
                    Text("此場次已有交易記錄，無法更改幣別")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            Section(header: Text("類別")) {
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
                    TextField("新增類別", text: $viewModel.newCategory)
                        .focused($focusedField, equals: .newCategory)
                        .submitLabel(.done)
                        .onSubmit {
                            // 驗證類別名稱是否合規
                            if let error = viewModel.validateCategoryValue() {
                                viewModel.alertMessage = error
                                viewModel.showAlert = true
                                focusedField = .newCategory
                            } else {
                                focusedField = nil
                            }
                        }

                    if !viewModel.newCategory.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button {
                            addCategoryAction()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .frame(height: 36)

                // 點擊不可編輯類別時顯示提示
                if viewModel.showCategoryEditWarning {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.orange)
                        Text("此類別已有交易紀錄，無法更改名稱")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

    // MARK: - 折扣 Section
            Section(header: Text("折扣")) {
                // 已有的折扣列表
                ForEach(viewModel.discounts) { discount in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(.gray)
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

                // 新增折扣輸入區
                HStack(spacing: 12) {
                    TextField("數值", text: $viewModel.newDiscountValue)
                        .keyboardType(.numberPad)
                        .frame(width: 80)
                        .focused($focusedField, equals: .newDiscount)
                        .submitLabel(.done)
                        .onSubmit {
                            addDiscountAction()
                        }

                    Picker("類型", selection: $viewModel.newDiscountType) {
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
                                .foregroundColor(.blue)
                        }
                    }
                }
                .frame(height: 36)
            }

            Section(header: Text("已停用類別")) {
                ForEach(viewModel.disabledSortedCategories, id: \.id) { category in
                    Text(category.name)
                        .foregroundColor(.gray)
                        .swipeActions(edge: .trailing) {
                            Button("復原") {
                                viewModel.handleRestoreAction(for: category.id)
                            }
                            .tint(.green)
                        }
                }
            }
        }
        .navigationTitle(viewModel.editingSession == nil ? "新增場次" : "編輯場次")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if focusedField == .newDiscount {
                    Spacer()
                    Button("完成") {
                        // 驗證折扣數值是否合規
                        if let error = viewModel.validateDiscountValue() {
                            viewModel.alertMessage = error
                            viewModel.showAlert = true
                        } else {
                            focusedField = nil
                        }
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("儲存") {
                    switch viewModel.validateSave() {
                    case .success:
                        let session = viewModel.save()
                        onSave(session)
                        presentationMode.wrappedValue.dismiss()
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
            // 當焦點從編輯類別移開時，檢查名稱是否有效
            if oldValue == .editingCategory {
                if let error = viewModel.finishEditingCategory() {
                    viewModel.alertMessage = error
                    viewModel.showAlert = true
                }
            }
            // 點擊新增類別時隱藏警告
            if newValue == .newCategory {
                viewModel.showCategoryEditWarning = false
            }
        }
        .onAppear {
            // 新增場次時自動聚焦到場次名稱欄位
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
            // 成功後重新聚焦，讓畫面滾動到輸入框
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
            // 成功後重新聚焦，讓畫面滾動到輸入框
            focusedField = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = .newDiscount
            }
        }
    }

    @ViewBuilder
    private func categoryRow(for category: CategoryModel) -> some View {
        // 1. 檢查這個類別是否可以編輯名稱
        let canEdit = viewModel.canEditCategoryName(for: category.id)
        // 2. 如果正在編輯這個類別 且 可以編輯
        if viewModel.editingCategoryID == category.id && canEdit {
            HStack {
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(.gray)
                TextField("類別名稱", text: Binding(
                    get: {
                        // 直接使用 category.id 查找，避免依賴 editingCategoryID
                        viewModel.categories.first(where: { $0.id == category.id })?.name ?? ""
                    },
                    set: { newValue in
                        viewModel.updateCategoryName(id: category.id, newName: newValue)
                    }
                ))
                .focused($focusedField, equals: .editingCategory)
                .onSubmit {
                    // 收起鍵盤，觸發 onChange(of: focusedField) 處理刪除邏輯
                    focusedField = nil
                }
            }
        } else {
            // 3. 否則只顯示文字
            HStack {
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(.gray)
                Text(category.name)
                    .foregroundColor(canEdit ? .primary : .gray)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if canEdit {
                    // 隱藏警告提示
                    viewModel.showCategoryEditWarning = false
                    // 點擊後進入編輯模式（先結束舊編輯，再開始新編輯）
                    if let error = viewModel.startEditingCategory(id: category.id) {
                        viewModel.alertMessage = error
                        viewModel.showAlert = true
                    }
                    focusedField = .editingCategory
                } else {
                    // 顯示不可編輯的提示
                    viewModel.showCategoryEditWarning = true
                }
            }
        }
    }
    
    @ViewBuilder
    private func swipeActionsContent(for category: CategoryModel) -> some View {
        switch viewModel.getSwipeAction(for: category) {
        case .disable:
            Button("停用") {
                viewModel.handleDisableAction(for: category.id)
            }
            .tint(.orange)
        case .delete:
            Button("刪除", role: .destructive) {
                viewModel.handleDeleteAction(for: category)
            }
        }
    }
}

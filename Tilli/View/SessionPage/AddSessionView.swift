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
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var categoryPendingDeletion: UUID?
    @State private var categoryPendingRestore: UUID?
    @State private var isDisableAction = false

    enum FocusField: Hashable {
        case sessionName
        case newCategory
    }

    @FocusState private var focusedField: FocusField?

    init(sessionToEdit: SessionModel? = nil, onSave: @escaping (SessionModel) -> Void) {
        self._viewModel = StateObject(wrappedValue: AddSessionViewModel(sessionToEdit: sessionToEdit))
        self.onSave = onSave
    }

    var body: some View {
        Form {
            TextField("Session Name", text: $viewModel.sessionName)
                .focused($focusedField, equals: .sessionName)
                .submitLabel(.next)
                .onSubmit {
                    focusedField = .newCategory
                }

            DatePicker("Date", selection: $viewModel.sessionDate, displayedComponents: .date)

            Section(header: Text("類別")) {
                ForEach(viewModel.sortedCategories.filter { !$0.isDisabled }, id: \.id) { category in
                    categoryRow(for: category)
                        .swipeActions(edge: .trailing) {
                            swipeActionsContent(for: category)
                        }
                }

                TextField("新增類別", text: $viewModel.newCategory)
                    .focused($focusedField, equals: .newCategory)
                    .submitLabel(.done)
                    .onSubmit {
                        if let error = viewModel.tryAddCategory() {
                            alertMessage = error
                            showAlert = true
                        } else {
                            focusedField = .newCategory
                        }
                    }
            }
            
            Section(header: Text("已停用類別")) {
                ForEach(viewModel.sortedCategories.filter { $0.isDisabled }, id: \.id) { category in
                    Text(category.name)
                        .foregroundColor(.gray)
                        .swipeActions(edge: .trailing) {
                            Button("復原") {
                                handleRestoreAction(for: category.id)
                            }
                            .tint(.green)
                        }
                }
            }
        }
        .navigationTitle(viewModel.editingSession == nil ? "Add Session" : "Edit Session")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    // 儲存前嘗試新增 newCategory
                    if let error = viewModel.tryAddCategory() {
                        alertMessage = error
                        showAlert = true
                        return
                    }

                    if viewModel.categories.filter({ !$0.isDisabled }).isEmpty {
                        alertMessage = "請至少輸入一個類別"
                        showAlert = true
                        return
                    }

                    let session = viewModel.save()
                    onSave(session)
                    presentationMode.wrappedValue.dismiss()
                }
                .disabled(viewModel.sessionName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .alert(isPresented: $showAlert) {
            if categoryPendingRestore != nil {
                // 復原操作的警告
                return Alert(
                    title: Text("確認復原"),
                    message: Text("確定要復原此類別嗎？"),
                    primaryButton: .default(Text("確認")) {
                        if let id = categoryPendingRestore {
                            viewModel.restoreCategory(byId: id)
                            categoryPendingRestore = nil
                        }
                    },
                    secondaryButton: .cancel {
                        categoryPendingRestore = nil
                    }
                )
            } else if categoryPendingDeletion != nil {
                if isDisableAction {
                    // 停用操作的警告
                    return Alert(
                        title: Text("確認停用"),
                        message: Text(alertMessage),
                        primaryButton: .default(Text("確認")) {
                            if let id = categoryPendingDeletion {
                                viewModel.disableCategory(byId: id)
                                categoryPendingDeletion = nil
                                isDisableAction = false
                            }
                        },
                        secondaryButton: .cancel {
                            categoryPendingDeletion = nil
                            isDisableAction = false
                        }
                    )
                } else {
                    // 刪除操作的警告
                    return Alert(
                        title: Text("確認刪除"),
                        message: Text(alertMessage),
                        primaryButton: .destructive(Text("刪除")) {
                            if let id = categoryPendingDeletion {
                                viewModel.removeCategory(byId: id)
                                categoryPendingDeletion = nil
                            }
                        },
                        secondaryButton: .cancel {
                            categoryPendingDeletion = nil
                        }
                    )
                }
            } else {
                return Alert(
                    title: Text("提醒"),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("好")) {
                        focusedField = .newCategory
                    }
                )
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.focusedField = .sessionName
            }
        }
    }
    
    // MARK: - Helper Methods
    @ViewBuilder
    private func categoryRow(for category: CategoryModel) -> some View {
        if viewModel.editingCategoryID == category.id {
            TextField("Category Name", text: Binding(
                get: {
                    viewModel.selectedCategory?.name ?? ""
                },
                set: { newValue in
                    viewModel.updateCategoryName(id: category.id, newName: newValue)
                }
            ))
            .focused($focusedField, equals: .newCategory)
            .onSubmit {
                viewModel.editingCategoryID = nil
            }
        } else {
            Text(category.name)
                .onTapGesture {
                    viewModel.editingCategoryID = category.id
                }
        }
    }
    
    @ViewBuilder
    private func swipeActionsContent(for category: CategoryModel) -> some View {
        if viewModel.hasTransaction(for: category.id) {
            // 有交易記錄 → 顯示「停用」按鈕
            Button("停用") {
                handleDisableAction(for: category.id)
            }
            .tint(.orange)
        } else {
            // 沒有交易記錄 → 顯示「刪除」按鈕
            Button("刪除", role: .destructive) {
                handleDeleteAction(for: category)
            }
        }
    }
    
    private func handleDisableAction(for categoryId: UUID) {
        alertMessage = "已有交易紀錄不可刪除，只能停用"
        categoryPendingDeletion = categoryId
        isDisableAction = true
        showAlert = true
    }
    
    private func handleDeleteAction(for category: CategoryModel) {
        if !category.products.isEmpty {
            // 有商品 → 警告後再刪除
            alertMessage = "此類別仍有產品，確定要刪除嗎？"
            categoryPendingDeletion = category.id
            isDisableAction = false
            showAlert = true
        } else {
            // 沒有商品 → 直接刪除
            viewModel.removeCategory(byId: category.id)
        }
    }
    
    private func handleRestoreAction(for categoryId: UUID) {
        categoryPendingRestore = categoryId
        showAlert = true
    }
}

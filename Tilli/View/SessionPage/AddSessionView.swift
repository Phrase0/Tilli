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
                ForEach(viewModel.sortedCategories, id: \.id) { category in
//                    Text(category.name)
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
                .onDelete { indexSet in
//                    let sortedCategories = viewModel.sortedCategories
//                    for index in indexSet {
//                        let categoryToDelete = sortedCategories[index]
//                        viewModel.removeCategory(byId: categoryToDelete.id)
//                    }
//                }
                    let sorted = viewModel.sortedCategories
                    for index in indexSet {
                        let category = sorted[index]

                        if viewModel.hasTransaction(for: category.id) {
                            // 有交易 → 停用
                            if let i = viewModel.categories.firstIndex(where: { $0.id == category.id }) {
                                viewModel.categories[i].isDisabled = true
                            }
                        } else if !category.products.isEmpty {
                            // ⚠️ 有商品 → 警告後再刪除
                            alertMessage = "此類別仍有產品，確定要刪除嗎？"
                            categoryPendingDeletion = category.id
                            showAlert = true
                        } else {
                            // ✅ 沒有商品與交易 → 直接刪除
                            viewModel.removeCategory(byId: category.id)
                        }
                    }
                }

                ///
                TextField("New Category", text: $viewModel.newCategory)
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

                    if viewModel.categories.isEmpty {
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
//        .alert(alertMessage, isPresented: $showAlert) {
//            Button("好") {
//                focusedField = .newCategory
//            }
//        }
        .alert(isPresented: $showAlert) {
            if categoryPendingDeletion != nil {
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
}

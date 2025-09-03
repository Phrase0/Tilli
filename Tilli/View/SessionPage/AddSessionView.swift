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
                ForEach(viewModel.activeSortedCategories, id: \.id) { category in
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
                            viewModel.alertMessage = error
                            viewModel.showAlert = true
                        } else {
                            focusedField = .newCategory
                        }
                    }
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
        .navigationTitle(viewModel.editingSession == nil ? "Add Session" : "Edit Session")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
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
                .disabled(viewModel.sessionName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .alert(isPresented: $viewModel.showAlert) {
            createAlert()
        }
        .onAppear {
            // 每次出現時更新資料管理器
            viewModel.updateDataManagers(
                transactionDataManager: transactionDataManager,
                productRepository: productRepository
            )
            
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
    
    private func createAlert() -> Alert {
        if viewModel.categoryPendingRestore != nil {
            // 復原操作的警告
            return Alert(
                title: Text("確認復原"),
                message: Text("確定要復原此類別嗎？"),
                primaryButton: .default(Text("確認")) {
                    viewModel.confirmRestoreAction()
                },
                secondaryButton: .cancel {
                    viewModel.cancelRestoreAction()
                }
            )
        } else if viewModel.categoryPendingDeletion != nil {
            if viewModel.isDisableAction {
                // 停用操作的警告
                return Alert(
                    title: Text("確認停用"),
                    message: Text(viewModel.alertMessage),
                    primaryButton: .default(Text("確認")) {
                        viewModel.confirmDeletionAction()
                    },
                    secondaryButton: .cancel {
                        viewModel.cancelDeletionAction()
                    }
                )
            } else {
                // 刪除操作的警告
                return Alert(
                    title: Text("確認刪除"),
                    message: Text(viewModel.alertMessage),
                    primaryButton: .destructive(Text("刪除")) {
                        viewModel.confirmDeletionAction()
                    },
                    secondaryButton: .cancel {
                        viewModel.cancelDeletionAction()
                    }
                )
            }
        } else {
            return Alert(
                title: Text("提醒"),
                message: Text(viewModel.alertMessage),
                dismissButton: .default(Text("好")) {
                    focusedField = .newCategory
                }
            )
        }
    }
}

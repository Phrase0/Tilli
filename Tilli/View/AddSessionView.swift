//
//  AddSessionView.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/23.
//

import SwiftUI

struct AddSessionView: View {
    @ObservedObject private var viewModel: AddSessionViewModel
    var onSave: (SessionModel) -> Void

    @Environment(\.presentationMode) private var presentationMode
    @State private var showAlert = false
    @State private var alertMessage = ""

    enum FocusField: Hashable {
        case sessionName
        case newCategory
    }

    @FocusState private var focusedField: FocusField?

    init(sessionToEdit: SessionModel? = nil, onSave: @escaping (SessionModel) -> Void) {
        self._viewModel = ObservedObject(wrappedValue: AddSessionViewModel(sessionToEdit: sessionToEdit))
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

            Section(header: Text("Categories")) {
                ForEach(viewModel.categories, id: \.self) { category in
                    Text(category)
                }
                .onDelete { indexSet in
                    indexSet.forEach { viewModel.removeCategory(at: $0) }
                }

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
                        alertMessage = "請至少輸入一個分類"
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
        .alert(alertMessage, isPresented: $showAlert) {
            Button("好") {
                focusedField = .newCategory
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.focusedField = .sessionName
            }
        }
    }
}

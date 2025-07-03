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

    init(sessionToEdit: SessionModel? = nil, onSave: @escaping (SessionModel) -> Void) {
        self._viewModel = ObservedObject(wrappedValue: AddSessionViewModel(sessionToEdit: sessionToEdit))
        self.onSave = onSave
    }

    var body: some View {
        Form {
            TextField("Session Name", text: $viewModel.sessionName)

            DatePicker("Date", selection: $viewModel.sessionDate, displayedComponents: .date)

            Section(header: Text("Categories")) {
                ForEach(viewModel.categories, id: \.self) { category in
                    Text(category)
                }
                .onDelete { indexSet in
                    indexSet.forEach { viewModel.removeCategory(at: $0) }
                }

                TextField("New Category", text: $viewModel.newCategory, onCommit: {
                    let trimmed = viewModel.newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty && !viewModel.categories.contains(trimmed) {
                        viewModel.categories.append(trimmed)
                    }

                    DispatchQueue.main.async {
                        viewModel.newCategory = ""
                    }
                })
            }
        }
        .navigationTitle(viewModel.editingSession == nil ? "Add Session" : "Edit Session")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    let trimmed = viewModel.newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty && !viewModel.categories.contains(trimmed) {
                        viewModel.categories.append(trimmed)
                    }
                    viewModel.newCategory = ""

                    let session = viewModel.save()
                    onSave(session)
                    presentationMode.wrappedValue.dismiss()
                }
                .disabled(viewModel.sessionName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}


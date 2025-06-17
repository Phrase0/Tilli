//
//  AddSessionView.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/23.
//

import SwiftUI

struct AddSessionView: View {
    var onAdd: ((SessionModel) -> Void)? // 回傳 closure
    
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = AddSessionViewModel()
    
    var body: some View {
        Form {
            Section(header: Text("Session Name")) {
                TextField("Enter session name", text: $viewModel.sessionName)
            }

            Section(header: Text("Session Time")) {
                DatePicker("Select session time", selection: $viewModel.sessionDate, displayedComponents: [.date])
                    .datePickerStyle(.compact)
            }

            Section(header: Text("Product Categories")) {
                ForEach(viewModel.categories.indices, id: \.self) { index in
                    HStack {
                        Text(viewModel.categories[index])
                        Spacer()
                        Button(action: {
                            viewModel.removeCategory(at: index)
                        }) {
                            Image(systemName: "xmark")
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.vertical, 4)
                }

                HStack {
                    TextField("Add new category", text: $viewModel.newCategory)
                    Button(action: {
                        viewModel.addCategory()
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                    .disabled(viewModel.newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationTitle("Session Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    let newSession = SessionModel(
                        id: UUID(),
                        title: viewModel.sessionName,
                        date: viewModel.sessionDate,
                        status: .ongoing,
                        amount: 0, // 預設為 0，或你也可以加上金額欄位
                        categories: viewModel.categories
                    )
                    onAdd?(newSession)
                    dismiss()
                }
                .disabled(viewModel.sessionName.isEmpty)
            }
        }
    }
}

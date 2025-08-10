//
//  AddSessionViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/6/17.
//

import Foundation

class AddSessionViewModel: ObservableObject {
    @Published var sessionName: String
    @Published var sessionDate: Date
    @Published var newCategory: String = ""
    @Published var categories: [CategoryModel]
    @Published var editingCategoryID: UUID?
    var editingSession: SessionModel?
    
    var sortedCategories: [CategoryModel] {
        categories.sorted(by: { $0.createdAt < $1.createdAt })
    }
    
    var activeSortedCategories: [CategoryModel] {
        categories.filter { !$0.isDisabled }.sorted(by: { $0.createdAt < $1.createdAt })
    }
    
    var selectedCategory: CategoryModel? {
        sortedCategories.first(where: { $0.id == editingCategoryID })
    }

    init(sessionToEdit: SessionModel? = nil) {
        self.editingSession = sessionToEdit
        self.sessionName = sessionToEdit?.title ?? ""
        self.sessionDate = sessionToEdit?.date ?? Date()
        self.categories = sessionToEdit?.categories ?? []
    }

    func updateCategoryName(id: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 避免同名
        if categories.contains(where: { $0.name == trimmed && $0.id != id }) {
            return
        }

        if let index = categories.firstIndex(where: { $0.id == id }) {
            categories[index].name = trimmed
        }
    }

    func removeCategory(byId categoryId: UUID) {
        categories.removeAll { $0.id == categoryId }
    }
    
    func disableCategory(byId categoryId: UUID) {
        if let index = categories.firstIndex(where: { $0.id == categoryId }) {
            categories[index].isDisabled = true
        }
    }
    
    func restoreCategory(byId categoryId: UUID) {
        if let index = categories.firstIndex(where: { $0.id == categoryId }) {
            categories[index].isDisabled = false
        }
    }

    // 嘗試將 newCategory 加入,成功則清空 newCategory,失敗回傳錯誤訊息
    func tryAddCategory() -> String? {
        let trimmed = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return nil }

        if categories.contains(where: { $0.name == trimmed }) {
            return "此類別已存在"
        }

        let new = CategoryModel(id: UUID(), name: trimmed)
        categories.append(new)

        DispatchQueue.main.async {
            self.newCategory = ""
        }

        return nil
    }
    
    func hasTransaction(for categoryId: UUID) -> Bool {
        guard let session = editingSession else { return false }
        
        for transaction in session.transactions {
            for item in transaction.items {
                if item.categoryId == categoryId {
                    return true
                }
            }
        }
        return false
    }

    func save() -> SessionModel {
        let baseSession = editingSession ?? SessionModel(
            title: "",
            date: Date(),
            categories: [],
            createdAt: Date()
        )

        return SessionModel(
            id: baseSession.id,
            title: sessionName,
            date: sessionDate,
            categories: categories,
            createdAt: baseSession.createdAt,
            transactions: baseSession.transactions
        )
    }
}

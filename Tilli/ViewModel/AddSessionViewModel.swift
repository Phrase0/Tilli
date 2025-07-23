//
//  Untitled.swift
//  Tilli
//
//  Created by Peiyun on 2025/6/17.
//

import Foundation

class AddSessionViewModel: ObservableObject {
    @Published var sessionName: String
    @Published var sessionDate: Date
    @Published var categories: [String]
    @Published var newCategory: String = ""

    var editingSession: SessionModel?

    init(sessionToEdit: SessionModel? = nil) {
        self.editingSession = sessionToEdit
        self.sessionName = sessionToEdit?.title ?? ""
        self.sessionDate = sessionToEdit?.date ?? Date()
        self.categories = sessionToEdit?.categories ?? []
    }

    func removeCategory(at index: Int) {
        guard categories.indices.contains(index) else { return }
        categories.remove(at: index)
    }

    /// 嘗試將 newCategory 加入，成功則清空 newCategory，失敗回傳錯誤訊息
    func tryAddCategory() -> String? {
        let trimmed = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return nil
        }

        if categories.contains(trimmed) {
            return "此分類已存在"
        }

        categories.append(trimmed)
        DispatchQueue.main.async {
            self.newCategory = ""
        }
        return nil
    }

    func save() -> SessionModel {
        let baseSession = editingSession ?? SessionModel(
            title: "",
            date: Date(),
            status: .ongoing,
//            amount: 0,
            categories: [],
            createdAt: Date(),
            products: []
        )

        return SessionModel(
            id: baseSession.id,
            title: sessionName,
            date: sessionDate,
            status: baseSession.status,
//            amount: baseSession.amount,
            categories: categories,
            createdAt: baseSession.createdAt,
            products: baseSession.products
        )
    }
}

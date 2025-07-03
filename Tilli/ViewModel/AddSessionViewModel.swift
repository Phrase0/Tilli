//
//  Untitled.swift
//  Tilli
//
//  Created by Peiyun on 2025/6/17.
//

import Foundation

class AddSessionViewModel: ObservableObject {
    @Published var sessionName: String = ""
    @Published var sessionDate: Date = Date()
    @Published var categories: [String] = []
    @Published var newCategory: String = ""

    private(set) var editingSession: SessionModel?

    init(sessionToEdit: SessionModel? = nil) {
        if let session = sessionToEdit {
            self.editingSession = session
            self.sessionName = session.title
            self.sessionDate = session.date
            self.categories = session.categories
        }
    }

    func addCategory() {
        let trimmed = newCategory.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !categories.contains(trimmed) else { return }
        categories.append(trimmed)
        newCategory = ""
    }

    func removeCategory(at index: Int) {
        categories.remove(at: index)
    }

    func save() -> SessionModel {
        if let editingSession = editingSession {
            return SessionModel(
                id: editingSession.id,
                title: sessionName,
                date: sessionDate,
                status: editingSession.status,
                amount: editingSession.amount,
                categories: categories,
                createdAt: editingSession.createdAt,
                products: editingSession.products
            )
        } else {
            return SessionModel(
                id: UUID(),
                title: sessionName,
                date: sessionDate,
                status: .ongoing,
                amount: 0,
                categories: categories,
                createdAt: Date(),
                products: []
            )
        }
    }
}

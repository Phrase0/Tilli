//
//  Untitled.swift
//  Tilli
//
//  Created by Peiyun on 2025/6/17.
//

import Foundation

class AddSessionViewModel: ObservableObject {
    // MARK: - Input Properties
    @Published var sessionName: String
    @Published var sessionDate: Date
    @Published var categories: [String]
    @Published var newCategory: String = ""

    // MARK: - Editing State
    var editingSession: SessionModel?

    // MARK: - Init
    init(sessionToEdit: SessionModel? = nil) {
        self.editingSession = sessionToEdit
        self.sessionName = sessionToEdit?.title ?? ""
        self.sessionDate = sessionToEdit?.date ?? Date()
        self.categories = sessionToEdit?.categories ?? []
    }

    // MARK: - Public Methods
    func removeCategory(at index: Int) {
        guard categories.indices.contains(index) else { return }
        categories.remove(at: index)
    }

    func save() -> SessionModel {
        let baseSession = editingSession ?? SessionModel(
            title: "",
            date: Date(),
            status: .ongoing,
            amount: 0,
            categories: [],
            createdAt: Date(),
            products: []
        )

        return SessionModel(
            id: baseSession.id,
            title: sessionName,
            date: sessionDate,
            status: baseSession.status,
            amount: baseSession.amount,
            categories: categories,
            createdAt: baseSession.createdAt,
            products: baseSession.products
        )
    }
}

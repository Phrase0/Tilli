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
    
    // 可選編輯 session
    private(set) var editingSession: SessionModel?

    // 依編輯或新增來初始化
    init(sessionToEdit: SessionModel? = nil) {
        if let session = sessionToEdit {
            self.editingSession = session
            self.sessionName = session.title
            self.sessionDate = session.date
            self.categories = session.categories // 假設 SessionModel 有 categories 屬性
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

    // 回傳 SessionModel，供儲存使用
    func save() -> SessionModel {
        if let editingSession = editingSession {
            // 修改既有 session
            return SessionModel(
                id: editingSession.id,
                title: sessionName,
                date: sessionDate,
                status: editingSession.status,
                amount: editingSession.amount,
                categories: categories
            )
        } else {
            // 新增新 session
            return SessionModel(
                id: UUID(),
                title: sessionName,
                date: sessionDate,
                status: SessionStatus.ongoing,
                amount: 0,
                categories: categories
            )
        }
    }

}

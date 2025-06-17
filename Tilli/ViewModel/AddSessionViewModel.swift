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
    @Published var categories: [String] = ["Breakfast", "Lunch", "Dinner"]
    @Published var newCategory: String = ""

    func addCategory() {
        let trimmed = newCategory.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !categories.contains(trimmed) else { return }
        categories.append(trimmed)
        newCategory = ""
    }

    func removeCategory(at index: Int) {
        categories.remove(at: index)
    }

    func save() {
        // 之後接 CoreData 寫入邏輯
        print("Saving session: \(sessionName), \(sessionDate), categories: \(categories)")
    }
}

//
//  Untitled.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/27.
//

import CoreData
import SwiftUI

class SessionDataManager: ObservableObject {
    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext

    @Published var sessions: [SessionModel] = []

    init(container: NSPersistentContainer = PersistenceController.shared.container) {
        self.container = container
        self.context = container.viewContext
        fetchAllSessions()
    }

    // MARK: - Create
    func addSession(_ model: SessionModel) {
        let entity = CDSessionEntity(context: context)
        entity.update(from: model, context: context)
        saveContext()
        fetchAllSessions()
    }

    // MARK: - Read
    func fetchAllSessions() {
        let request: NSFetchRequest<CDSessionEntity> = CDSessionEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        do {
            let result = try context.fetch(request)
            sessions = result.map { $0.toModel() }
        } catch {
            print("Fetch sessions failed:", error)
        }
    }

    func fetchSession(by id: UUID) -> SessionModel? {
        let request: NSFetchRequest<CDSessionEntity> = CDSessionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)

        do {
            if let entity = try context.fetch(request).first {
                return entity.toModel()
            }
        } catch {
            print("Fetch session by ID failed:", error)
        }
        return nil
    }

    // MARK: - Update
    func updateSession(_ model: SessionModel) {
        let request: NSFetchRequest<CDSessionEntity> = CDSessionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", model.id as CVarArg)

        do {
            if let entity = try context.fetch(request).first {
                entity.update(from: model, context: context)
                saveContext()
                fetchAllSessions()
            }
        } catch {
            print("Update session failed:", error)
        }
    }

    // MARK: - Delete
    func deleteSession(_ model: SessionModel) {
        let request: NSFetchRequest<CDSessionEntity> = CDSessionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", model.id as CVarArg)

        do {
            if let entity = try context.fetch(request).first {
                context.delete(entity)
                saveContext()
                fetchAllSessions()
            }
        } catch {
            print("Delete session failed:", error)
        }
    }

    // MARK: - Save
    private func saveContext() {
        do {
            try context.save()
            print("Session saved to CoreData")
        } catch {
            print("Core Data save failed:", error)
            context.rollback()
        }
    }
}

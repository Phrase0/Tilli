//
//  ProductCoreDataViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/25.
//

import Foundation
import CoreData
import SwiftUI

class ProductCoreDataViewModel: ObservableObject {
    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext

    @Published var products: [ProductModel] = []

    init(container: NSPersistentContainer = PersistenceController.shared.container) {
        self.container = container
        self.context = container.viewContext
        fetchAllProducts()
    }

    // MARK: - Create
    func addProduct(_ model: ProductModel) {
        let entity = CDProductEntity(context: context)
        entity.update(from: model)
        saveContext()
        fetchAllProducts()
    }

    // MARK: - Read
    func fetchAllProducts() {
        let request: NSFetchRequest<CDProductEntity> = CDProductEntity.fetchRequest()

        do {
            let result = try context.fetch(request)
            products = result.map { ProductModel(entity: $0) }
        } catch {
            print("Fetch products failed:", error)
        }
    }

    func fetchProducts(forSessionId sessionId: UUID) -> [ProductModel] {
        let request: NSFetchRequest<CDProductEntity> = CDProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "sessionId == %@", sessionId as CVarArg)

        do {
            let result = try context.fetch(request)
            return result.map { ProductModel(entity: $0) }
        } catch {
            print("Fetch products for session failed:", error)
            return []
        }
    }

    // MARK: - Update
    func updateProduct(_ model: ProductModel) {
        let request: NSFetchRequest<CDProductEntity> = CDProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", model.id as CVarArg)

        do {
            if let entity = try context.fetch(request).first {
                entity.update(from: model)
                saveContext()
                fetchAllProducts()
            }
        } catch {
            print("Update product failed:", error)
        }
    }

    // MARK: - Delete
    func deleteProduct(_ model: ProductModel) {
        let request: NSFetchRequest<CDProductEntity> = CDProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", model.id as CVarArg)

        do {
            if let entity = try context.fetch(request).first {
                context.delete(entity)
                saveContext()
                fetchAllProducts()
            }
        } catch {
            print("Delete product failed:", error)
        }
    }

    // MARK: - Save
    private func saveContext() {
        do {
            try context.save()
        } catch {
            print("Core Data save failed:", error)
            context.rollback()
        }
    }
}

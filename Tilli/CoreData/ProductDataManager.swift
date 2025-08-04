//
//  ProductCoreDataViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/25.
//

import CoreData
import SwiftUI

class ProductDataManager: ObservableObject {
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
        let request: NSFetchRequest<CDCategoryEntity> = CDCategoryEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", model.categoryId as CVarArg)

        do {
            guard let categoryEntity = try context.fetch(request).first else {
                print("找不到對應 category，無法加入 product")
                return
            }

            let productEntity = CDProductEntity(context: context)
            productEntity.update(from: model, context: context)
            productEntity.category = categoryEntity

            saveContext()
            fetchAllProducts()
        } catch {
            print("加入 product 失敗:", error)
        }
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
//    func updateProduct(_ model: ProductModel) {
//        let request: NSFetchRequest<CDProductEntity> = CDProductEntity.fetchRequest()
//        request.predicate = NSPredicate(format: "id == %@", model.id as CVarArg)
//
//        do {
//            if let entity = try context.fetch(request).first {
//                entity.update(from: model, context: context)
//                saveContext()
//                fetchAllProducts()
//            }
//        } catch {
//            print("Update product failed:", error)
//        }
//    }
    func updateProduct(_ model: ProductModel) {
        let request: NSFetchRequest<CDProductEntity> = CDProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", model.id as CVarArg)

        do {
            if let entity = try context.fetch(request).first {
                entity.update(from: model, context: context)
                saveContext()
                // 不要呼叫 fetchAllProducts() 這裡避免不必要的刷新
                if let index = products.firstIndex(where: { $0.id == model.id }) {
                    products[index] = model
                }
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
            print("Product save to CoreData")
        } catch {
            print("Core Data save failed:", error)
            context.rollback()
        }
    }
}

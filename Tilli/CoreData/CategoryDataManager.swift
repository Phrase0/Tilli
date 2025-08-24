////
////  CategoryDataManager.swift
////  Tilli
////
////  Created by Peiyun on 2025/8/4.
////
//import SwiftUI
//import CoreData
//
//class CategoryDataManager: ObservableObject {
//    
//    private let context: NSManagedObjectContext
//
//    @Published var categories: [CategoryModel] = []
//    
//
//    init(container: NSPersistentContainer = PersistenceController.shared.container) {
//        self.context = container.viewContext
//        fetchAllCategories()
//    }
//
//    // MARK: - Create
//    func addCategory(_ model: CategoryModel, toSessionId sessionId: UUID) {
//        let request: NSFetchRequest<CDSessionEntity> = CDSessionEntity.fetchRequest()
//        request.predicate = NSPredicate(format: "id == %@", sessionId as CVarArg)
//
//        do {
//            guard let sessionEntity = try context.fetch(request).first else {
//                print("找不到 session，無法加入 category")
//                return
//            }
//
//            let categoryEntity = CDCategoryEntity(context: context)
//            categoryEntity.update(from: model, context: context)
//            sessionEntity.addToCategories(categoryEntity)
//
//            saveContext()
//            fetchAllCategories()
//        } catch {
//            print("加入 category 失敗:", error)
//        }
//    }
//
//    // MARK: - Read
//    func fetchAllCategories() {
//        let request: NSFetchRequest<CDCategoryEntity> = CDCategoryEntity.fetchRequest()
//
//        do {
//            let result = try context.fetch(request)
//            categories = result.map { $0.toModel() }
//        } catch {
//            print("Fetch categories failed:", error)
//        }
//    }
//
//    func fetchCategories(forSessionId sessionId: UUID) -> [CategoryModel] {
//        let request: NSFetchRequest<CDCategoryEntity> = CDCategoryEntity.fetchRequest()
//        request.predicate = NSPredicate(format: "session.id == %@", sessionId as CVarArg)
//
//        do {
//            let result = try context.fetch(request)
//            return result.map { $0.toModel() }
//        } catch {
//            print("Fetch categories for session failed:", error)
//            return []
//        }
//    }
//
//    // MARK: - Delete
//    func deleteCategory(_ model: CategoryModel) {
//        let request: NSFetchRequest<CDCategoryEntity> = CDCategoryEntity.fetchRequest()
//        request.predicate = NSPredicate(format: "id == %@", model.id as CVarArg)
//
//        do {
//            if let entity = try context.fetch(request).first {
//                context.delete(entity)
//                saveContext()
//                fetchAllCategories()
//            }
//        } catch {
//            print("Delete category failed:", error)
//        }
//    }
//
//    // MARK: - Save
//    private func saveContext() {
//        do {
//            try context.save()
//            print("Category saved to CoreData")
//        } catch {
//            print("Core Data save failed:", error)
//            context.rollback()
//        }
//    }
//}

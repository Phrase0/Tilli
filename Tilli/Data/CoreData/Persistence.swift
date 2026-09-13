//
//  Persistence.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/22.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        return controller
    }()

    let container: NSPersistentContainer

    /// 整個 process 共用同一份 `NSManagedObjectModel`。
    ///
    /// `NSPersistentContainer(name:)` 每次都會重新從 bundle 解析一份 model，
    /// 一旦同時存在兩份（例如單元測試另外建了 in-memory container），
    /// `+[CDxxxEntity entity]` 就會回報
    /// 「Failed to find a unique match for an NSEntityDescription」並取不到 entity。
    /// 共用一份同時也省掉重複解析的成本。
    private static let managedObjectModel: NSManagedObjectModel = {
        guard let url = Bundle.main.url(forResource: "Tilli", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url) else {
            fatalError("找不到 CoreData model：Tilli.momd")
        }
        return model
    }()

    /// 後台 Context，用於處理耗時操作
    lazy var backgroundContext: NSManagedObjectContext = {
        let context = container.newBackgroundContext()
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }()

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Tilli", managedObjectModel: Self.managedObjectModel)
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                assertionFailure("Unresolved error \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}

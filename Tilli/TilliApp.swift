//
//  TilliApp.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/22.
//

import SwiftUI

@main
struct TilliApp: App {
    @StateObject private var sessionDataManager = SessionDataManager()
    @StateObject private var transactionDataManager = TransactionDataManager()
    @StateObject private var productRepository = ProductRepository()
    @StateObject private var inventoryChangeRepository = InventoryChangeRepository()
    @StateObject private var qRCodeDataManager = QRCodeDataManager()
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(sessionDataManager)
                .environmentObject(transactionDataManager)
                .environmentObject(productRepository)
                .environmentObject(inventoryChangeRepository)
                .environmentObject(qRCodeDataManager)
        }
    }
}



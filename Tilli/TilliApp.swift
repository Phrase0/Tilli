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
//    @StateObject private var categoryDataManager = CategoryDataManager()
    @StateObject private var productDataManager = ProductDataManager()
    @StateObject private var transactionDataManager = TransactionDataManager()
    
    @StateObject private var appState = AppState()
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(appState)
                .environmentObject(sessionDataManager)
//                .environmentObject(categoryDataManager)
                .environmentObject(productDataManager)
                .environmentObject(transactionDataManager)
        }
    }
}



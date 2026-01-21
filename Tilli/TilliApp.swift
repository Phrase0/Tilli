//
//  TilliApp.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/22.
//

import SwiftUI
import FirebaseCore

@main
struct TilliApp: App {
    @StateObject private var authenticationManager = AuthenticationManager()
    @StateObject private var sessionDataManager = SessionRepository()
    @StateObject private var transactionDataManager = TransactionRepository()
    @StateObject private var productRepository = ProductRepository()
    @StateObject private var inventoryChangeRepository = InventoryChangeRepository()
    @StateObject private var qRCodeDataManager = QRCodeRepository()
    let persistenceController = PersistenceController.shared

    @Environment(\.scenePhase) private var scenePhase

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(authenticationManager)
                .environmentObject(sessionDataManager)
                .environmentObject(transactionDataManager)
                .environmentObject(productRepository)
                .environmentObject(inventoryChangeRepository)
                .environmentObject(qRCodeDataManager)
                .task {
                    // App 啟動時自動匿名登入
                    await authenticationManager.signInAnonymously()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        // App 回到前景時檢查 deviceId
                        Task {
                            await authenticationManager.checkDeviceId()
                        }
                    }
                }
                .alert("帳號已在其他裝置登入", isPresented: $authenticationManager.showDeviceConflictAlert) {
                    Button("取消", role: .cancel) {
                        // 不踢掉其他裝置，登出當前帳號
                        authenticationManager.signOut()
                    }
                    Button("登出其他裝置") {
                        Task {
                            await authenticationManager.kickOtherDevice()
                        }
                    }
                } message: {
                    Text("您的帳號已在其他裝置登入。要登出其他裝置並繼續使用嗎？")
                }
        }
    }
}



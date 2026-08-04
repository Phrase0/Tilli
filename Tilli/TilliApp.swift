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
    @StateObject private var eventDataManager = EventRepository()
    @StateObject private var transactionDataManager = TransactionRepository()
    @StateObject private var productRepository = ProductRepository()
    @StateObject private var inventoryChangeRepository = InventoryChangeRepository()
    @StateObject private var qRCodeDataManager = QRCodeRepository()
    let persistenceController = PersistenceController.shared

    @AppStorage("selectedLanguage") private var selectedLanguage = "zh-Hant"
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.locale, Locale(identifier: selectedLanguage))
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(authenticationManager)
                .environmentObject(eventDataManager)
                .environmentObject(transactionDataManager)
                .environmentObject(productRepository)
                .environmentObject(inventoryChangeRepository)
                .environmentObject(qRCodeDataManager)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        // App 回到前景時檢查 deviceId
                        Task {
                            await authenticationManager.checkDeviceId()
                        }
                        // 確保 Listener 運行中（可能因進入背景而中斷）
                        SyncManager.shared.startListening()
                    }
                }
                // 帳號已在其他裝置登入
                .alert("deviceConflictTitle", isPresented: $authenticationManager.showDeviceConflictAlert) {
                    // 取消
                    Button("commonCancel", role: .cancel) {
                        authenticationManager.signOut()
                    }
                    // 登出其他裝置
                    Button("deviceConflictKickOther") {
                        Task {
                            await authenticationManager.kickOtherDevice()
                        }
                    }
                } message: {
                    // 您的帳號已在其他裝置登入。要登出其他裝置並繼續使用嗎？
                    Text("deviceConflictMessage")
                }
        }
    }
}



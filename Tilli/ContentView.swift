//
//  ContentView.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/23.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Int = 0
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var sessionDataManager: SessionRepository
    @EnvironmentObject var inventoryChangeRepository: InventoryChangeRepository

    // MARK: - 測試用（測試完成後刪除這段）
    @State private var hasGeneratedTestData = false

    /// 控制是否顯示新用戶個人資料設定（安全網）
    @State private var showProfileSetup = false

    var body: some View {
        TabView(selection: $selectedTab) {
            SessionsView()
                .tabItem { Label("場次", systemImage: "list.bullet") }
                .tag(0)

            CalendarView()
                .tabItem { Label("日曆", systemImage: "calendar") }
                .tag(1)

            InventoryTabView()
                .tabItem { Label("庫存", systemImage: "shippingbox") }
                .tag(2)

            MerchantQRCodeView()
                .tabItem { Label("QRCode", systemImage: "qrcode") }
                .tag(3)

            ProfileView()
                .tabItem { Label("個人", systemImage: "person.crop.circle") }
                .tag(4)
        }
        // 新用戶強制完成個人資料設定（安全網：處理 app 重啟等情況）
        .fullScreenCover(isPresented: $showProfileSetup) {
            NavigationStack {
                ProfileEditView(isNewUser: true)
                    .environmentObject(authManager)
            }
            .interactiveDismissDisabled()
        }
        // MARK: - 測試用（測試完成後刪除這段 .onAppear）
        .onAppear {
            // 檢查是否需要顯示個人資料設定（安全網：只在 app 啟動時檢查一次）
            checkProfileSetup()

            TestDataGenerator.generateTestData(
                sessionDataManager: sessionDataManager,
                inventoryChangeRepository: inventoryChangeRepository
            )
            TestDataGenerator.generate30DaysMultiCafeSession(
                sessionDataManager: sessionDataManager,
                inventoryChangeRepository: inventoryChangeRepository
            )
        }
    }

    // MARK: - 檢查是否需要顯示個人資料設定
    private func checkProfileSetup() {
        let needsSetup = authManager.isLoggedIn &&
            (authManager.currentUser?.name.trimmingCharacters(in: .whitespaces).isEmpty ?? true)

        if needsSetup != showProfileSetup {
            showProfileSetup = needsSetup
        }
    }
}

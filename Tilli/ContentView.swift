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

    /// 是否需要顯示個人資料設定頁（由 authState 控制）
    private var needsProfileSetup: Bool {
        authManager.authState == .needsSetup
    }

    var body: some View {
        if authManager.authState == .loading {
            loadingView
        } else {
            mainView
        }
    }

    private var loadingView: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            ProgressView()
                .scaleEffect(1.5)
        }
    }

    private var mainView: some View {
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
        .id(authManager.authState)
        // 新用戶強制完成個人資料設定（統一由 authState 控制）
        .fullScreenCover(isPresented: Binding(
            get: { needsProfileSetup },
            set: { _ in }  // 不允許手動關閉，只能透過完成設定來關閉
        )) {
            NavigationStack {
                ProfileEditView(isNewUser: true)
                    .environmentObject(authManager)
            }
            .interactiveDismissDisabled()
        }
        // MARK: - 測試用（測試完成後刪除這段 .onAppear）
        .onAppear {
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
}


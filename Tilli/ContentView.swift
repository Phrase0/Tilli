//
//  ContentView.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/23.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Int = 1
    @EnvironmentObject var sessionDataManager: SessionDataManager
    @EnvironmentObject var appState: AppState

    // MARK: - 測試用（測試完成後刪除這段）
    @State private var hasGeneratedTestData = false

    var body: some View {
        TabView(selection: $selectedTab) {
            CalendarView()
                .tabItem { Label("日曆", systemImage: "calendar") }
                .tag(0)

            SessionsView()
                .environmentObject(appState)
                .tabItem { Label("場次", systemImage: "list.bullet") }
                .tag(1)

            MainAddProductFlowView(selectedTab: $selectedTab)
                .environmentObject(appState)
                .tabItem { Label("新增", systemImage: "plus.circle.fill") }
                .tag(2)

            MerchantQRCodeView()
                .tabItem { Label("QRCode", systemImage: "qrcode") }
                .tag(3)

            ProfileView()
                .tabItem { Label("個人", systemImage: "person.crop.circle") }
                .tag(4)
        }
        // MARK: - 測試用（測試完成後刪除這段 .onAppear）
        .onAppear {
            TestDataGenerator.generateTestData(sessionDataManager: sessionDataManager)
            TestDataGenerator.generate30DaysMultiCafeSession(sessionDataManager: sessionDataManager)
        }
    }
}

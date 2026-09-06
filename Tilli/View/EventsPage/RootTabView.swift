//
//  RootTabView.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/28.
//

import SwiftUI

struct RootTabView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var syncManager = SyncManager.shared
    @AppStorage("selectedLanguage") private var selectedLanguage = "zh-Hant"
    @AppStorage("darkModeEnabled") private var darkModeEnabled = false

    private var needsProfileSetup: Bool {
        authManager.authState == .needsSetup
    }

    var body: some View {
        ZStack {
            if authManager.authState == .loading {
                loadingView
            } else {
                mainView
            }

            // 全量下載完成前顯示轉圈圈，避免中途看到「尚無資料」的空畫面
            // （例如刪除 App 重裝後，本機資料還沒補回來的那段時間）
            if authManager.isLoading || syncManager.isDownloading {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .allowsHitTesting(true)
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
            }
        }
        .preferredColorScheme(darkModeEnabled ? .dark : .light)
    }

    private var loadingView: some View {
        ZStack {
            DesignSystem.ColorToken.paper.ignoresSafeArea()
            ProgressView()
                .scaleEffect(1.5)
        }
    }

    private var mainView: some View {
        NavigationStack {
            EventsView()
        }
        .id(authManager.authState)
        .fullScreenCover(isPresented: Binding(
            get: { needsProfileSetup },
            set: { _ in }
        )) {
            NavigationStack {
                ProfileEditView(isNewUser: true)
                    .environmentObject(authManager)
            }
            .interactiveDismissDisabled()
        }
    }
}

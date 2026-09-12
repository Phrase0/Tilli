//
//  RootTabView.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/28.
//

import SwiftUI

struct RootTabView: View {
    @EnvironmentObject var authManager: AuthenticationManager
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

            // TODO: [SYNC-PENDING] 重建同步後，全量下載期間也要顯示遮罩
            // ⚠️ 重建時請加上限（見 SYNC_ARCHITECTURE_V2.md §9.2），
            //    舊版因為等待沒有上限而造成登出無限轉圈
            if authManager.isLoading {
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

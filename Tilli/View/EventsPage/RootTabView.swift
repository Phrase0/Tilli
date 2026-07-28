//
//  RootTabView.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/28.
//

import SwiftUI

struct RootTabView: View {
    @State private var selectedTab: Int = 0
    @EnvironmentObject var authManager: AuthenticationManager

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

            if authManager.isLoading {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .allowsHitTesting(true)
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
            }
        }
    }

    private var loadingView: some View {
        ZStack {
            DesignSystem.ColorToken.paper.ignoresSafeArea()
            ProgressView()
                .scaleEffect(1.5)
        }
    }

    private var mainView: some View {
        TabView(selection: $selectedTab) {
            // 場次
            Text("eventsTabPlaceholder")
                .tabItem {
                    Image(systemName: "list.bullet")
                    // 場次
                    Text("eventsTabTitle")
                }
                .tag(0)

            // 我的
            MyView()
                .tabItem {
                    Image(systemName: "person.crop.circle")
                    // 我的
                    Text("myTabTitle")
                }
                .tag(1)
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

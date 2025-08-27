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

    var body: some View {
        TabView(selection: $selectedTab) {
            CalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(0)

            SessionsView()
                .environmentObject(appState)
                .tabItem { Label("Sessions", systemImage: "list.bullet") }
                .tag(1)

            MainAddProductFlowView(selectedTab: $selectedTab)
                .environmentObject(appState)
                .tabItem { Label("Add", systemImage: "plus.circle") }
                .tag(2)

            QRCodeView()
                .tabItem { Label("QRCode", systemImage: "qrcode") }
                .tag(3)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(4)
        }
    }
}

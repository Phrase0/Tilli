//
//  ContentView.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/23.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Int = 0
    @StateObject private var sessionStore = SessionStore() // ✅ 提出來只建一次

    var body: some View {
        TabView(selection: $selectedTab) {
            SessionsView()
                .environmentObject(sessionStore)
                .tabItem {
                    Label("Sessions", systemImage: "folder")
                }
                .tag(0)

            MainAddProductFlowView(selectedTab: $selectedTab)
                .environmentObject(sessionStore)
                .tabItem {
                    Label("Add", systemImage: "plus.circle")
                }
                .tag(1)

            CalendarView()
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }
                .tag(2)

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
                .tag(3)
        }
    }
}

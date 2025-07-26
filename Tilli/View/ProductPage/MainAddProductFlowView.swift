//
//  MainAddProductFlowView.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/22.
//


import SwiftUI
import PhotosUI

struct MainAddProductFlowView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var productDataManager: ProductDataManager
    @Binding var selectedTab: Int

    @State private var searchText: String = ""
    @State private var showAddProduct: Bool = false

    var filteredSessions: [SessionModel] {
        appState.sessions.filter { session in
            searchText.isEmpty || session.title.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        VStack {
            if let session = appState.currentSession, showAddProduct {
                // ❗️AddNewProductView 改用 environmentObject，所以這裡不需要傳 productDataManager
                AddNewProductView(
                    session: session,
                    onSave: {
                        showAddProduct = false
                        selectedTab = 1
                    },
                    onCancel: {
                        showAddProduct = false
                        selectedTab = 1
                    }
                )
                // ✅ 額外保險：如果這不是在 NavigationLink 或 .sheet 中，明確提供 environmentObject
                .environmentObject(productDataManager)
            }
            else if appState.currentSession == nil {
                NavigationView {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredSessions) { session in
                                SessionCardView(session: session) {
                                    appState.currentSession = session
                                    showAddProduct = true
                                }
                            }
                        }
                        .padding()
                    }
                    .navigationTitle("選擇場次")
                    .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
                }
            }
            else {
                Color.clear
                    .onAppear {
                        showAddProduct = true
                    }
            }
        }
    }
}

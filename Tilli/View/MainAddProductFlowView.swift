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
                // 直接顯示新增商品頁
                AddNewProductView(
                    session: session,
                    onSave: { newProduct in
                        if let index = appState.sessions.firstIndex(where: { $0.id == session.id }) {
                            appState.sessions[index].products.append(newProduct)
                            appState.sessions[index].amount = appState.sessions[index].products.reduce(0) {
                                $0 + Int($1.price * Double($1.quantity))
                            }
                        }
                        // 儲存後保持 currentSession，不清空
                        showAddProduct = false
                        selectedTab = 0
                    },
                    onCancel: {
                        // 取消新增，同樣保持 currentSession
                        showAddProduct = false
                        selectedTab = 0
                    }
                )
            }
            else if appState.currentSession == nil {
                // 尚未選擇場次，顯示選擇場次頁
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
                // currentSession 不為 nil，但尚未顯示新增頁，利用 onAppear 觸發跳轉
                Color.clear
                    .onAppear {
                        showAddProduct = true
                    }
            }
        }
    }
}

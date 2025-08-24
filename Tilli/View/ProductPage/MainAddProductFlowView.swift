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
    @EnvironmentObject var sessionDataManager: SessionDataManager
    @Binding var selectedTab: Int

    @State private var searchText: String = ""
    @State private var showAddProduct: Bool = false

    var filteredSessions: [SessionModel] {
        sessionDataManager.sessions.filter { session in
            searchText.isEmpty || session.title.localizedStandardContains(searchText)
        }
    }
    
    var sortedFilteredSessions: [SessionModel] {
         let filtered = filteredSessions
         return filtered.sorted {
             switch ($0.status, $1.status) {
             case (.ongoing, _): return true
             case (_, .ongoing): return false
             case (.upcoming, .completed): return true
             case (.completed, .upcoming): return false
             default:
                 return $0.date > $1.date // 同類型比日期
             }
         }
     }

    var body: some View {
        VStack {
            if let session = appState.currentSession, showAddProduct {
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
            }
            else if appState.currentSession == nil {
                NavigationView {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(sortedFilteredSessions) { session in
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

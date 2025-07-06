//
//  MainAddProductFlowView().swift
//  Tilli
//
//  Created by Peiyun on 2025/7/3.
//

import SwiftUI
import PhotosUI

struct MainAddProductFlowView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedTab: Int

    @State private var searchText: String = ""

    // 讀取並過濾 session
    var filteredSessions: [SessionModel] {
        appState.sessions.filter { session in
            searchText.isEmpty || session.title.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        VStack {
            if let session = appState.currentSession {
                AddNewProductView(session: session, onSave: { newProduct in
                    if let index = appState.sessions.firstIndex(where: { $0.id == session.id }) {
                        appState.sessions[index].products.append(newProduct)
                        appState.sessions[index].amount = appState.sessions[index].products.reduce(0) {
                            $0 + Int($1.price * Double($1.quantity))
                        }
                    }
                    appState.currentSession = nil
                    selectedTab = 0
                }, onCancel: {
                    appState.currentSession = nil
                    selectedTab = 0
                })
            } else {
                NavigationView {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredSessions) { session in
                                SessionCardView(session: session) {
                                    appState.currentSession = session
                                }
                            }
                        }
                        .padding()
                    }
                    .navigationTitle("選擇場次")
                    .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
                }
            }
        }
    }
}

//
//  MainAddProductFlowView().swift
//  Tilli
//
//  Created by Peiyun on 2025/7/3.
//

import SwiftUI
import PhotosUI

struct MainAddProductFlowView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @Binding var selectedTab: Int

    @State private var currentSession: SessionModel? = nil
    @State private var searchText: String = ""

    var filteredSessions: [SessionModel] {
        sessionStore.sessions.filter { session in
            searchText.isEmpty || session.title.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        VStack {
            if let session = currentSession {
                AddNewProductView(session: session, onSave: { newProduct in
                    if let index = sessionStore.sessions.firstIndex(where: { $0.id == session.id }) {
                        sessionStore.sessions[index].products.append(newProduct)
                        sessionStore.sessions[index].amount = sessionStore.sessions[index].products.reduce(0) {
                            $0 + Int($1.price * Double($1.quantity))
                        }
                    }
                    currentSession = nil
                    selectedTab = 0
                }, onCancel: {
                    currentSession = nil
                    selectedTab = 0
                })
            } else {
                NavigationView {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredSessions) { session in
                                SessionCardView(session: session) {
                                    currentSession = session
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

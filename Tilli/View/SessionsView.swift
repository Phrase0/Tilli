//
//  SessionsView.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/22.
//

import SwiftUI

struct SessionsView: View {
    @StateObject private var viewModel = SessionsViewModel()
    @State private var showAddSession = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 搜尋欄
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("search session", text: $viewModel.searchText)
                        .textInputAutocapitalization(.none)
                        .disableAutocorrection(true)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)

                // 卡片式列表
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.filteredSessions) { session in
                            SessionCard(session: session)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.top, 10)
                }
            }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showAddSession = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSession) {
                AddSessionView()
            }
        }
    }
}

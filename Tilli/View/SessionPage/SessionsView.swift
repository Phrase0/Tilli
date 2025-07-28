//
//  SessionsView.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/22.
//

import SwiftUI

struct SessionsView: View {
    
    @EnvironmentObject var sessionDataManager: SessionDataManager
    @StateObject private var viewModel = SessionViewModel()
//    @EnvironmentObject var appState: AppState
    
    @State private var searchText = ""
    // 控制新增頁面導航
    @State private var isNavigatingToAddSession = false
    // 用來儲存當前想要編輯的 Session
    @State private var editingSession: SessionModel? = nil

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredSessions(by: searchText)) { session in
                        NavigationLink(destination:
                            SessionDetailView(session: session)
                        ) {
                            sessionCard(session)
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            appState.currentSession = session
                        })
                    }
                }
                .padding()
            }
            .navigationTitle("Sessions")
            .searchable(text: $searchText)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(
                        destination: AddSessionView(onSave: { newSession in
                            appState.sessions.append(newSession)
                            viewModel.sessions = appState.sessions // 同步更新viewModel.sessions
                        }),
                        isActive: $isNavigatingToAddSession
                    ) {
                        Image(systemName: "plus")
                    }
                }
            }
            // 隱藏式 NavigationLink 用來觸發編輯頁面導航
            .background(
                NavigationLink(
                    destination: editingSession != nil ?
                        AnyView(AddSessionView(sessionToEdit: editingSession!, onSave: { updatedSession in
                            if let index = appState.sessions.firstIndex(where: { $0.id == updatedSession.id }) {
                                appState.sessions[index] = updatedSession
                                viewModel.sessions = appState.sessions // 同步更新viewModel.sessions
                            }
                            editingSession = nil
                        })) :
                        AnyView(EmptyView()),
                    isActive: Binding(
                        get: { editingSession != nil },
                        set: { isActive in
                            if !isActive { editingSession = nil }
                        }
                    )
                ) {
                    EmptyView()
                }
                .hidden()
            )
            .onAppear {
                // 初次載入時同步 ViewModel 的 sessions
                viewModel.sessions = appState.sessions
                // 清空 currentSession，確保從明細返回時沒殘留
                appState.currentSession = nil
            }
        }
    }

    @ViewBuilder
    private func sessionCard(_ session: SessionModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.title)
                        .font(.headline)

                    Text(session.date, formatter: DateFormatter.sessionDate)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(session.status.rawValue)
                            .font(.caption)
                            .foregroundColor(session.status.textColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(session.status.color)
                            .clipShape(Capsule())

                        if session.status == .ongoing {
                            Button {
                                editingSession = session
                            } label: {
                                Image(systemName: "pencil")
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }

//                    Text("NT$\(session.amount.formatted())")
//                        .font(.subheadline)
//                        .fontWeight(.bold)
//                        .foregroundColor(.black)
//                        .padding(.horizontal, 8)
//                        .padding(.vertical, 4)
//                        .background(Color(.systemGray6))
//                        .clipShape(Capsule())
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    private func filteredSessions(by keyword: String) -> [SessionModel] {
        if keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return appState.sessions
        } else {
            return appState.sessions.filter {
                $0.title.localizedCaseInsensitiveContains(keyword)
            }
        }
    }
}

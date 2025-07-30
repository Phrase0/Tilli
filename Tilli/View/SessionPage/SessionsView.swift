//
//  SessionsView.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/22.
//

import SwiftUI

struct SessionsView: View {
    
    @EnvironmentObject var sessionDataManager: SessionDataManager
    @EnvironmentObject var appState: AppState

    @State private var searchText = ""
    @State private var isNavigatingToAddSession = false
    @State private var editingSession: SessionModel? = nil
    
    @StateObject private var viewModel = SessionViewModel()

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.filteredSessions(by: searchText)) { session in
                        // 取得 session 在 sessions 陣列的索引
                        if let index = viewModel.sessions.firstIndex(where: { $0.id == session.id }) {
                            NavigationLink(destination:
                                            SessionDetailView(session: $viewModel.sessions[index])
                            ) {
                                sessionCard(session)
                            }
                            .simultaneousGesture(TapGesture().onEnded {
                                appState.currentSession = session
                            })
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("場次")
            .searchable(text: $searchText)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(
                        destination: AddSessionView(onSave: { newSession in
                            sessionDataManager.addSession(newSession)
                            viewModel.sessions = sessionDataManager.sessions
                        }),
                        isActive: $isNavigatingToAddSession
                    ) {
                        Image(systemName: "plus")
                    }
                }
            }
            .background(
                NavigationLink(
                    destination: editingSession != nil ?
                    AnyView(AddSessionView(sessionToEdit: editingSession!, onSave: { updatedSession in
                        sessionDataManager.updateSession(updatedSession)
                        viewModel.sessions = sessionDataManager.sessions
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
                viewModel.sessions = sessionDataManager.sessions
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
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

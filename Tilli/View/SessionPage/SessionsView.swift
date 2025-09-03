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
    @State private var sessionToDelete: SessionModel? = nil
    @State private var showDeleteConfirmation = false

    @State private var selectedSession: SessionModel? = nil

    @StateObject private var viewModel: SessionViewModel
    init() {
        _viewModel = StateObject(wrappedValue: SessionViewModel())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.sortedFilteredSessions(by: searchText)) { session in
                        sessionCard(session)
                            .onTapGesture {
                                selectedSession = session
                                appState.currentSession = session
                            }
                    }
                }
                .padding()
            }
            .navigationTitle("場次")
            .searchable(text: $searchText)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isNavigatingToAddSession = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(isPresented: $isNavigatingToAddSession) {
                AddSessionView(onSave: { newSession in
                    viewModel.addSession(newSession, using: sessionDataManager)
                    isNavigatingToAddSession = false
                })
            }
            .navigationDestination(item: $selectedSession) { session in
                if let index = viewModel.sessions.firstIndex(where: { $0.id == session.id }) {
                    SessionDetailView(session: $viewModel.sessions[index])
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { editingSession != nil },
                set: { isActive in
                    if !isActive { editingSession = nil }
                }
            )) {
                if let session = editingSession {
                    AddSessionView(sessionToEdit: session, onSave: { updatedSession in
                        viewModel.updateSession(updatedSession, using: sessionDataManager)
                        editingSession = nil
                    })
                }
            }
            .onAppear {
                viewModel.refresh(using: sessionDataManager)
                appState.currentSession = nil
            }
        }
        .alert("確定要刪除這個場次嗎？", isPresented: $showDeleteConfirmation, presenting: sessionToDelete) { session in
            Button("刪除", role: .destructive) {
                viewModel.deleteSession(session, using: sessionDataManager)
            }
            Button("取消", role: .cancel) { }
        } message: { session in
            Text("刪除後將同時移除底下的所有類別、商品與交易紀錄，且無法復原，是否確定？")
        }
    }

    // MARK: - 卡片 View
    @ViewBuilder
    private func sessionCard(_ session: SessionModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(session.title)
                        .font(.headline)

                    Text(session.date, formatter: DateFormatter.sessionDate)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 12) {
                    Menu {
                        Button {
                            editingSession = session
                        } label: {
                            Label("編輯", systemImage: "pencil")
                        }
                        
                        Button(role: .destructive) {
                            sessionToDelete = session
                            showDeleteConfirmation = true
                        } label: {
                            Label("刪除", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .rotationEffect(.degrees(90))
                            .foregroundColor(.gray)
                            .padding(8)
                    }
                    
                    Text(session.status.rawValue)
                        .font(.caption)
                        .foregroundColor(session.status.textColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(session.status.color)
                        .clipShape(Capsule())
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(session.status == .ongoing ? Color.blue.opacity(0.1) : Color.white)
        )
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

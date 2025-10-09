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
                    if viewModel.sortedFilteredSessions(by: searchText, from: sessionDataManager.sessions).isEmpty {
                        // 空狀態顯示
                        if searchText.isEmpty {
                            // 完全沒有場次
                            EmptyStateView(
                                systemImage: "calendar.badge.plus",
                                title: "尚無場次",
                                message: "點擊右上角「+」按鈕新增第一個場次"
                            )
                        } else {
                            // 搜尋無結果
                            EmptyStateView(
                                systemImage: "magnifyingglass",
                                title: "查無結果",
                                message: "找不到符合「\(searchText)」的場次"
                            )
                        }
                    } else {
                        // 有場次時顯示列表
                        ForEach(viewModel.sortedFilteredSessions(by: searchText, from: sessionDataManager.sessions)) { session in
                            sessionCard(session)
                                .onTapGesture {
                                    selectedSession = session
                                    appState.currentSession = session
                                }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("場次")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜尋場次")
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
                if let index = sessionDataManager.sessions.firstIndex(where: { $0.id == session.id }) {
                    SessionDetailView(session: $sessionDataManager.sessions[index])
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
                // SessionDataManager 會自動管理和更新 sessions 數據
                appState.currentSession = nil
            }
        }
        .alert("確定要刪除這個場次嗎？", isPresented: $showDeleteConfirmation, presenting: sessionToDelete) { session in
            Button("刪除", role: .destructive) {
                viewModel.deleteSession(session, using: sessionDataManager)
            }
            Button("取消", role: .cancel) { }
        } message: { session in
            Text("刪除後將同時移除底下的所有類別、商品與交易記錄，且無法復原，是否確定？")
        }
        .sheet(isPresented: $viewModel.showDuplicateSessionDialog) {
            duplicateSessionView
        }
    }

    // MARK: - 複製場次 View
    @ViewBuilder
    private var duplicateSessionView: some View {
        NavigationView {
            Form {
                TextField("場次名稱", text: $viewModel.duplicateSessionName)
                    .onChange(of: viewModel.duplicateSessionName) {
                        viewModel.onSessionNameChanged()
                    }
                
                DatePicker("日期", selection: $viewModel.duplicateSessionDate, displayedComponents: .date)
            }
            .navigationTitle("複製場次")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        viewModel.cancelDuplicateSession()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("確定") {
                        viewModel.confirmDuplicateSession(using: sessionDataManager)
                    }
                    .disabled(viewModel.isDuplicateButtonDisabled)
                }
            }
        }
        .presentationDetents([.fraction(0.35)])
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
                            viewModel.startDuplicateSession(session)
                        } label: {
                            Label("複製場次", systemImage: "doc.on.doc")
                        }
                        
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
                    
                    Text(session.status.localizedDescription)
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

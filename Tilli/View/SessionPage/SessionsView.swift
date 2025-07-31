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
    
    
    @StateObject private var viewModel: SessionViewModel
    init() {
        _viewModel = StateObject(wrappedValue: SessionViewModel())
    }
    
    @State private var selectedSessionID: UUID? = nil
    
    private func binding(for session: SessionModel) -> Binding<SessionModel>? {
        guard let index = viewModel.sessions.firstIndex(where: { $0.id == session.id }) else {
            return nil
        }
        return $viewModel.sessions[index]
    }
    
    
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.filteredSessions(by: searchText)) { session in
                        // 取得 session 在 sessions 陣列的索引
                        SwipeToDeleteCardView(session: session) {
                            viewModel.deleteSession(session, using: sessionDataManager)
                        } content: {
                            ZStack {
                                sessionCard(session)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedSessionID = session.id
                                        appState.currentSession = session
                                    }
                                // 這裡改為搜尋 binding 而不是用 index
                                if let binding = binding(for: session) {
                                    NavigationLink(
                                        destination: SessionDetailView(session: binding),
                                        tag: session.id,
                                        selection: $selectedSessionID
                                    ) {
                                        EmptyView()
                                    }
                                    .hidden()
                                }
                                
                            }
                            
                            
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


struct SwipeToDeleteCardView<Content: View>: View {
    let session: SessionModel
    let onDelete: () -> Void
    let content: () -> Content
    
    @State private var offsetX: CGFloat = 0
    @GestureState private var isDragging = false
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        ZStack(alignment: .trailing) {
            // 背後的紅色刪除區域
            HStack {
                Spacer()
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.red)
                        .clipShape(Circle())
                }
                .padding(.trailing, 16)
            }
            
            // 前方卡片
            content()
                .background(Color.white)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                .offset(x: offsetX)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if value.translation.width < 0 {
                                offsetX = max(value.translation.width, -80)
                            }
                        }
                        .onEnded { value in
                            withAnimation {
                                if value.translation.width < -50 {
                                    offsetX = -80
                                } else {
                                    offsetX = 0
                                }
                            }
                        }
                )
                .alert("確定要刪除這個場次嗎？", isPresented: $showDeleteConfirmation) {
                    Button("刪除", role: .destructive, action: onDelete)
                    Button("取消", role: .cancel) { }
                } message: {
                    Text("此操作將無法還原。")
                }
        }
    }
}

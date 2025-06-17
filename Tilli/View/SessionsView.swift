//
//  SessionsView.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/22.
//

import SwiftUI

struct SessionsView: View {
    @StateObject private var viewModel = SessionViewModel()
    @State private var searchText = ""
    @State private var isNavigatingToAddSession = false


    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 12, pinnedViews: []) {
                    ForEach(viewModel.filtered(by: searchText)) { session in
                        sessionCard(session)
                    }
                }
                .padding()
            }
            .navigationTitle("Sessions")
            .searchable(text: $searchText)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: AddSessionView(onAdd: { newSession in
                        viewModel.sessions.append(newSession) // 加入新增 session
                    }), isActive: $isNavigatingToAddSession) {
                        Image(systemName: "plus")
                    }
                }
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
                    Text(session.status.rawValue)
                        .font(.caption)
                        .foregroundColor(session.status.textColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(session.status.color)
                        .clipShape(Capsule())

                    Text("NT$\(session.amount.formatted())")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray6))
                        .clipShape(Capsule())
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

//
//  SelectSessionView.swift
//  Tilli
//
//  Created by Peiyun on 2025/6/23.
//
import SwiftUI

struct SelectSessionView: View {
    @Binding var selectedSession: SessionModel?
    var onSelect: (SessionModel) -> Void

    var sessions: [SessionModel]

    var body: some View {
        List(sessions) { session in
            Button {
                selectedSession = session
                onSelect(session)
            } label: {
                HStack {
                    Text(session.title)
                    Spacer()
                    if selectedSession?.id == session.id {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        .navigationTitle("Select Session")
    }
}


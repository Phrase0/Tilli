//
//  MainAddProductFlowView.swift
//  Tilli
//
//  Created by Peiyun on 2025/6/23.
//

import SwiftUI

struct MainAddProductFlowView: View {
    @StateObject private var sessionVM = SessionViewModel()
    @StateObject private var productVM = ProductViewModel()

    @State private var selectedSession: SessionModel? = nil
    @State private var isNavigatingToProduct = false

    
    var body: some View {
        NavigationView {
            VStack {
                if let session = selectedSession {
                    NavigationLink(
                        destination: AddProductView(
                            productViewModel: productVM,
                            sessionViewModel: sessionVM,
                            selectedSession: session
                        ),
                        isActive: $isNavigatingToProduct
                    ) {
                        EmptyView()
                    }
                    .hidden()

                    // Optional: 可以放提示或控制按鈕
                    Text("Adding product to: \(session.title)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                } else {
                    SelectSessionView(
                        selectedSession: $selectedSession,
                        onSelect: { session in
                            selectedSession = session
                            isNavigatingToProduct = true
                        },
                        sessions: sessionVM.sessions
                    )
                }
            }
            .onAppear {
                if selectedSession == nil,
                   let lastUsed = sessionVM.sessions.first {
                    selectedSession = lastUsed
                }
            }
            .navigationTitle("New Product")
        }
    }
}


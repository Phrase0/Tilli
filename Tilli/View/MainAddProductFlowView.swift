//
//  MainAddProductFlowView().swift
//  Tilli
//
//  Created by Peiyun on 2025/7/3.
//

import SwiftUI

//struct MainAddProductFlowView: View {
//    @StateObject private var sessionVM = SessionViewModel()
//
//    @State private var currentSession: SessionModel? = nil
//    @State private var isAddingProduct = false
//
//    var body: some View {
//        NavigationView {
//            Group {
//                if let session = currentSession {
//                    AddNewProductView(session: session) { newProduct in
//                        if let index = sessionVM.sessions.firstIndex(where: { $0.id == session.id }) {
//                            sessionVM.sessions[index].products.append(newProduct)
//                            // 更新 amount 總和
//                            sessionVM.sessions[index].amount = sessionVM.sessions[index].products.reduce(0) {
//                                $0 + Int($1.price * Double($1.quantity))
//                            }
//                        }
//                        // 新增完成，回到選擇頁面或重置狀態
//                        currentSession = nil
//                        isAddingProduct = false
//                    }
//                } else {
//                    SessionPickerView(sessionViewModel: sessionVM) { session in
//                        currentSession = session
//                        isAddingProduct = true
//                    }
//                }
//            }
//            .navigationBarHidden(true)
//        }
//    }
//}
struct MainAddProductFlowView: View {
    @EnvironmentObject var sessionStore: SessionStore

    @State private var currentSession: SessionModel?

    var body: some View {
        NavigationView {
            if let session = currentSession ?? sessionStore.sessions.first {
                AddNewProductView(session: session) { newProduct in
                    if let index = sessionStore.sessions.firstIndex(where: { $0.id == session.id }) {
                        sessionStore.sessions[index].products.append(newProduct)
                        sessionStore.sessions[index].amount = sessionStore.sessions[index].products.reduce(0) {
                            $0 + Int($1.price * Double($1.quantity))
                        }
                    }
                    currentSession = nil
                }
            } else {
                SessionPickerView(onSessionSelected: { session in
                    currentSession = session
                })
                .environmentObject(sessionStore)

            }
        }
    }
}

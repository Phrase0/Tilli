//
//  SessionPickerView.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/3.
//
import SwiftUI

struct SessionPickerView: View {
    @Environment(\.presentationMode) private var presentationMode
    //
    @EnvironmentObject var sessionStore: SessionStore
    //
//    @ObservedObject var sessionViewModel: SessionViewModel
    var onSessionSelected: (SessionModel) -> Void

    @State private var searchText: String = ""

//    var filteredSessions: [SessionModel] {
//        sessionViewModel.filtered(by: searchText)
//            .sorted { $0.date > $1.date }
//    }
    var filteredSessions: [SessionModel] {
        sessionStore.sessions.filter { session in
            searchText.isEmpty || session.title.localizedStandardContains(searchText)
        }
    }
    
    

    var body: some View {
        VStack {
            TextField("搜尋場次名稱...", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            List(filteredSessions) { session in
                Button(action: {
                    onSessionSelected(session)
                    presentationMode.wrappedValue.dismiss()
                }) {
                    VStack(alignment: .leading) {
                        Text(session.title)
                            .font(.headline)
                        Text(session.date, formatter: DateFormatter.sessionDate)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("選擇場次")
    }
}

//
//  SessionsViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/23.
//

import Foundation
import Combine

class SessionsViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var sessions: [Session] = [
        Session(title: "河濱市集春季特賣", date: "2025年4月10日", amount: "NT$6,200", status: .ongoing),
        Session(title: "手作市集週末場", date: "2025年4月8日", amount: "NT$4,800", status: .ongoing),
        Session(title: "年度文創市集", date: "2025年4月5日", amount: "NT$12,500", status: .completed)
    ]
    
    var filteredSessions: [Session] {
        guard !searchText.isEmpty else { return sessions }
        
        return sessions.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.title.folding(options: .diacriticInsensitive, locale: .current).localizedCaseInsensitiveContains(searchText)
        }
    }
}


//
//  AppState.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/5.
//

import Foundation

class AppState: ObservableObject {
    @Published var sessions: [SessionModel] = []
    @Published var currentSession: SessionModel? = nil
    @Published var currentSummaryItems: [SummaryItemModel] = []
    @Published var transactionRecords: [[SummaryItemModel]] = []
}


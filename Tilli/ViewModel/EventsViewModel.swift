//
//  EventsViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2026/7/29.
//

import SwiftUI

class EventsViewModel: ObservableObject {
    @Published var displayMode: EventsDisplayMode = .list
}

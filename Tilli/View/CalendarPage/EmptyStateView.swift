//
//  EmptyStateView.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/16.
//

import SwiftUI

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    let topPadding: CGFloat
    
    init(systemImage: String, title: String, message: String, topPadding: CGFloat = 100) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.topPadding = topPadding
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text(title)
                .font(.headline)
                .foregroundColor(.gray)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.top, topPadding)
        .frame(maxWidth: .infinity)
    }
}

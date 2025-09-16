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
    
    var body: some View {
        VStack {
            Spacer(minLength: 50)
            
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
                    .padding(.horizontal, 32) // 讓文字不會太貼邊
            }
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

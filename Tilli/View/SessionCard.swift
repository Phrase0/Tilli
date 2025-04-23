//
//  SessionCard.swift
//  Tilli
//
//  Created by Peiyun on 2025/4/23.
//
import SwiftUI

struct SessionCard: View {
    let session: Session
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.title)
                    .font(.headline)
                Spacer()
                Text(session.status.rawValue)
                    .font(.subheadline)
                    .foregroundColor(session.status.color)
            }
            
            HStack(alignment: .lastTextBaseline) {
                Text(session.date)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                Spacer()
                
                Text(session.amount)
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray5))
                    .cornerRadius(12)
            }


            
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

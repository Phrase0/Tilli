//
//  SessionCardView.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/5.
//

import SwiftUI

struct SessionCardView: View {
    var session: SessionModel
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: {
            onTap?()
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.title)
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text(session.date, formatter: DateFormatter.sessionDate)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(session.status.rawValue)
                            .font(.caption)
                            .foregroundColor(session.status.textColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(session.status.color)
                            .clipShape(Capsule())

                        Text("NT$\(session.amount)")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.systemGray6))
                            .clipShape(Capsule())
                    }
                }
                .padding()
                .background(Color.white)
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

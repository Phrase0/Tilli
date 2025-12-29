////
////  SessionCardView.swift
////  Tilli
////
////  Created by Peiyun on 2025/7/5.
////
//
//import SwiftUI
//
//struct SessionCardView: View {
//    var session: SessionModel
//    var onTap: (() -> Void)? = nil
//
//    var body: some View {
//        Button(action: {
//            onTap?()
//        }) {
//            VStack(alignment: .leading, spacing: 8) {
//                HStack(alignment: .top) {
//                    VStack(alignment: .leading, spacing: 6) {
//                        Text(session.title)
//                            .font(.headline)
//
//                        Text(session.displayDateRange)
//                            .font(.subheadline)
//                            .foregroundColor(.gray)
//                    }
//
//                    Spacer()
//
//                    Text(session.status.localizedDescription)
//                        .font(.caption)
//                        .foregroundColor(session.status.textColor)
//                        .padding(.horizontal, 8)
//                        .padding(.vertical, 4)
//                        .background(session.status.color)
//                        .clipShape(Capsule())
//                }
//            }
//            .padding()
//            .background(
//                RoundedRectangle(cornerRadius: 12)
//                    .fill(session.status == .ongoing ? Color.blue.opacity(0.1) : Color.white)
//            )
//            .cornerRadius(12)
//            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
//        }
//        .buttonStyle(PlainButtonStyle())
//    }
//}

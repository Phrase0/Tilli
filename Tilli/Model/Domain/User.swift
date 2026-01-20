//
//  User.swift
//  Tilli
//
//  Created by Peiyun on 2025/1/20.
//

import Foundation

struct User: Identifiable, Codable {
    let id: String
    let name: String
    let email: String
    let photoURL: String?
    let provider: AuthProvider

    enum AuthProvider: String, Codable {
        case email
        case apple
        case google
    }
}

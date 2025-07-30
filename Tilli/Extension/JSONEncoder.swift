//
//  Untitled.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/27.
//
import Foundation

extension JSONEncoder {
    func encodeToString<T: Encodable>(_ value: T) throws -> String {
        let data = try self.encode(value)
        return String(data: data, encoding: .utf8) ?? ""
    }
}

extension JSONDecoder {
    func decodeFromString<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        guard let data = string.data(using: .utf8) else {
            throw NSError(domain: "Decode Error", code: 0)
        }
        return try self.decode(T.self, from: data)
    }
}

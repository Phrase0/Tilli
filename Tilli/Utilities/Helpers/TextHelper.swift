//
//  TextHelper.swift
//  Tilli
//
//  Created by Peiyun on 2025/12/30.
//

import Foundation

struct TextHelper {

    /// 預定義的字數限制
    static let sessionNameLimit = 40
    static let productNameLimit = 40
    static let productDescriptionLimit = 20

    /// 檢查文字是否超過上限
    static func isOverLimit(_ text: String, limit: Int) -> Bool {
        return text.count > limit
    }

    /// 截斷文字至上限
    static func truncateToLimit(_ text: String, limit: Int) -> String {
        if text.count <= limit {
            return text
        }
        return String(text.prefix(limit))
    }

    /// 取得剩餘可輸入字數
    static func remainingCharacters(for text: String, limit: Int) -> Int {
        return limit - text.count
    }
}

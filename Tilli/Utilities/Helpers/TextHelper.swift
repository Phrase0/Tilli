//
//  TextHelper.swift
//  Tilli
//
//  Created by Peiyun on 2025/12/30.
//

import Foundation

struct TextHelper {

    /// 字元上限
    static let characterLimit = 40

    /// 取得字元上限
    static func maxLength(for text: String) -> Int {
        return characterLimit
    }

    /// 檢查文字是否超過上限
    static func isOverLimit(_ text: String) -> Bool {
        return text.count > characterLimit
    }

    /// 截斷文字至上限
    static func truncateToLimit(_ text: String) -> String {
        if text.count <= characterLimit {
            return text
        }
        return String(text.prefix(characterLimit))
    }

    /// 取得剩餘可輸入字數
    static func remainingCharacters(for text: String) -> Int {
        return characterLimit - text.count
    }
}

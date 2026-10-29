//
//  Sequence+LocalizedJoin.swift
//  Tilli
//
//  名稱串接的分隔符放在 Localizable.xcstrings，跟著 App 語言走。
//  ListFormatter 跟系統語言走，App 內語言設定不同時會對不上，所以不用它。
//

import Foundation

extension Sequence where Element == String {
    /// 名稱列表：「大福、抹茶」／「Daifuku, Matcha」
    func joinedAsList() -> String {
        // 、
        joined(separator: String.localized("listSeparator"))
    }

    /// 套餐成員：「大福＋抹茶」／「Daifuku + Matcha」
    func joinedAsBundleMembers() -> String {
        // ＋
        joined(separator: String.localized("bundleMemberSeparator"))
    }
}

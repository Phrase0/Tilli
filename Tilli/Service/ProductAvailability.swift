//
//  ProductAvailability.swift
//  Tilli
//
//  Created by Peiyun on 2026/9/12.
//
//  統一「商品可不可以賣」的判斷，取代散落的 isDisabled 檢查。
//  見 FEATURE_PLAN_V1.md §2.5（解 B6）。
//

import Foundation

/// 商品不可販售的原因。
///
/// 拆出這個 enum 是為了讓「類別不存在」這條 fail-closed 分支**可以被單元測試覆蓋** ——
/// `isAvailableForSale` 在該分支會 `assertionFailure`，Debug 下測試會直接 trap，
/// 所以判斷邏輯放在純函式 `saleAvailability(in:)`，assertion 與 log 留在外層。
enum SaleAvailability: Equatable {
    case available
    case productDisabled      // 商品已下架
    case categoryDisabled     // 所屬類別已停用
    case categoryMissing      // 所屬類別不存在（資料異常）
}

extension ProductModel {

    /// 純判斷，不帶副作用（無 assertion、無 log），供測試與外層共用。
    func saleAvailability(in categories: [CategoryModel]) -> SaleAvailability {
        guard !isDisabled else { return .productDisabled }
        guard let category = categories.first(where: { $0.id == categoryId }) else {
            return .categoryMissing
        }
        return category.isDisabled ? .categoryDisabled : .available
    }

    /// 可在 POS 販售：商品未下架、且所屬類別存在且未停用。
    ///
    /// 原本 6 處判斷只有 1 處檢查兩層，所以「類別停用但商品照樣顯示」
    /// 在部分畫面會發生；而唯一檢查兩層的那處寫成
    /// `categories.first(where:)?.isDisabled == false`，
    /// 找不到類別時 `nil == false` → `false`，商品會被**靜默隱藏**。
    /// 這裡一樣 fail-closed，但**留下痕跡**。
    func isAvailableForSale(in categories: [CategoryModel]) -> Bool {
        let availability = saleAvailability(in: categories)

        if availability == .categoryMissing {
            assertionFailure("商品「\(name)」(\(id)) 的類別 \(categoryId) 不存在")
            print("🔴 商品 \(id) 的類別 \(categoryId) 不存在，視為不可販售")
        }

        return availability == .available
    }
}

extension Array where Element == CategoryModel {

    /// 啟用中的類別，依 `sortOrder` 排序。
    ///
    /// 原本 5 處各自寫 `filter { !$0.isDisabled }.sorted { $0.sortOrder < $1.sortOrder }`，
    /// 而且來源不一致（有的用 `event.categories`、有的用 ViewModel 的 `categories`），
    /// 是 A3「商品是新鮮的、類別是快照」的一部分。
    var active: [CategoryModel] {
        filter { !$0.isDisabled }.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// 已停用的類別，依 `sortOrder` 排序
    var disabled: [CategoryModel] {
        filter { $0.isDisabled }.sorted { $0.sortOrder < $1.sortOrder }
    }
}

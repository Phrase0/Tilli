//
//  BundleModel.swift
//  Tilli
//
//  組合與套餐。存於 `CDEventEntity.bundlesData`（JSON）。
//  見 docs/superpowers/specs/2026-10-27-bundles-design.md §3。
//

import Foundation

/// 套餐（fixed）或組合（chooseAny）。也是 `SummaryItemModel.bundleKind` 的快照值。
enum BundleKind: String, Codable, Hashable {
    case fixed
    case chooseAny
}

enum BundleMode: Codable, Hashable {
    case fixed                      // 套餐：成員全拿
    case chooseAny(count: Int)      // 組合：從候選中任選 count 個
}

struct BundleModel: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var price: Decimal              // 套餐價／組合價
    var mode: BundleMode
    var productIds: [UUID]          // 成員（fixed）或候選（chooseAny）
    var isDisabled: Bool = false
    var imageURL: String? = nil     // 套餐照片（選填）；圖檔存本機
    var createdAt: Date = Date()

    /// 由 mode 推導，不另外存
    var kind: BundleKind {
        switch mode {
        case .fixed: return .fixed
        case .chooseAny: return .chooseAny
        }
    }

    /// fixed → 成員數；chooseAny → N
    var requiredCount: Int {
        switch mode {
        case .fixed: return productIds.count
        case .chooseAny(let count): return count
        }
    }
}

extension BundleModel {
    private enum CodingKeys: String, CodingKey {
        case id, name, price, mode, productIds, isDisabled, imageURL, createdAt
    }

    /// 合成的 Decodable 不套用屬性預設值，缺 key 會整份解不出來，所以手寫。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        price = try c.decode(Decimal.self, forKey: .price)
        mode = try c.decode(BundleMode.self, forKey: .mode)
        productIds = try c.decode([UUID].self, forKey: .productIds)
        isDisabled = try c.decodeIfPresent(Bool.self, forKey: .isDisabled) ?? false
        imageURL = try c.decodeIfPresent(String.self, forKey: .imageURL)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
    }
}

extension BundleModel {
    /// 複製場次用：換新 bundle id，productIds 依對照表換成新商品 id；任一成員不在對照表 → nil。
    /// 保留名稱／價格／mode／停用狀態／createdAt（維持列表順序）；imageURL 清空（新圖待同步上傳）。
    func remapped(productIdMap: [UUID: UUID]) -> BundleModel? {
        var newProductIds: [UUID] = []
        for oldId in productIds {
            guard let newId = productIdMap[oldId] else { return nil }
            newProductIds.append(newId)
        }
        var copy = self
        copy.id = UUID()
        copy.productIds = newProductIds
        copy.imageURL = nil
        return copy
    }
}

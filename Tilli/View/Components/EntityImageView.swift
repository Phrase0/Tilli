//
//  EntityImageView.swift
//  Tilli
//
//  Created by Peiyun on 2026/2/6.
//  可重用圖片元件：本地優先 → 遠端 fallback → 交給 ImageCacheStore 快取
//

import SwiftUI
import Kingfisher

/// 圖片 Entity 類型（決定壓縮規格與目標 entity）
enum ImageEntityType {
    case product  // 200x200 JPEG 壓縮
    case qrCode   // 512x512 PNG 無損
    case profile  // 200x200 JPEG 壓縮

    var imageType: ImageType {
        switch self {
        case .product: return .thumbnail
        case .qrCode: return .qrCode
        case .profile: return .thumbnail
        }
    }

    var entityName: String {
        switch self {
        case .product: return "CDProductEntity"
        case .qrCode: return "CDQRCodeEntity"
        case .profile: return "CDUserProfileEntity"
        }
    }
}

/// 圖片元件
/// 1. `imageData` 有值 → 顯示本地圖片
/// 2. `imageData` 為 nil 但 `imageURL` 有值 → 下載遠端圖，成功後交給 `ImageCacheStore` 快取
/// 3. 都沒有 → 灰色 placeholder
///
/// 註：同步層移除後 `imageURL` 目前一律為 nil，情況 2 暫時不會發生；
/// 保留是因為重建同步後會再用到（見 ARCHITECTURE.md §4）。
struct EntityImageView: View {
    let imageData: Data?
    let imageURL: String?
    let entityId: UUID
    let entityType: ImageEntityType
    let contentMode: SwiftUI.ContentMode
    /// 只有 entityType == .profile 才需要：CDUserProfileEntity 是用 uid（字串）識別，不是 UUID
    var profileUid: String? = nil

    var body: some View {
        if let data = imageData, let uiImage = UIImage(data: data) {
            // 1. 本地圖片
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else if let urlString = imageURL, !urlString.isEmpty, let url = URL(string: urlString) {
            // 2. 遠端圖片
            KFImage(url)
                .placeholder {
                    ProgressView()
                }
                .onSuccess { result in
                    Task { @MainActor in
                        ImageCacheStore.shared.store(
                            result.image,
                            kind: entityType,
                            id: entityId,
                            profileUid: profileUid
                        )
                    }
                }
                // TODO: [SYNC-PENDING] 下載失敗目前沒有 fallback，會永遠停在 ProgressView。
                // 重建同步後要補重試鍵或 placeholder（見 FEATURE_PLAN_V1.md 附錄 A.2 B2）
                .onFailure { _ in }
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            // 3. Placeholder
            Rectangle()
                .foregroundColor(Color(.systemGray5))
                .overlay(
                    Image(systemName: "photo")
                        .foregroundColor(.gray)
                )
        }
    }
}

//
//  SyncableImageView.swift
//  Tilli
//
//  Created by Peiyun on 2026/2/6.
//  可重用圖片元件：本地優先 → KFImage fallback → 回寫 CoreData
//

import SwiftUI
import Kingfisher
import CoreData

/// 圖片 Entity 類型（決定圖片處理方式）
enum ImageEntityType {
    case product  // 200x200 JPEG 壓縮
    case qrCode   // 512x512 PNG 無損

    var imageType: ImageType {
        switch self {
        case .product: return .thumbnail
        case .qrCode: return .qrCode
        }
    }

    var entityName: String {
        switch self {
        case .product: return "CDProductEntity"
        case .qrCode: return "CDQRCodeEntity"
        }
    }
}

/// 可同步的圖片元件
/// 1. imageData 有值 → 顯示本地圖片
/// 2. imageData 為 nil 但 imageURL 有值 → KFImage 顯示遠端，成功後回寫 CoreData
/// 3. 都沒有 → 灰色 placeholder
struct SyncableImageView: View {
    let imageData: Data?
    let imageURL: String?
    let entityId: UUID
    let entityType: ImageEntityType
    let contentMode: SwiftUI.ContentMode

    var body: some View {
        if let data = imageData, let uiImage = UIImage(data: data) {
            // 1. 本地圖片
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else if let urlString = imageURL, !urlString.isEmpty, let url = URL(string: urlString) {
            // 2. 遠端圖片（KFImage）
            KFImage(url)
                .placeholder {
                    ProgressView()
                }
                .onSuccess { result in
                    // 回寫 CoreData
                    saveImageLocally(result.image, entityId: entityId, entityType: entityType)
                }
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

    /// 將下載的圖片處理後存入 CoreData
    private func saveImageLocally(_ image: UIImage, entityId: UUID, entityType: ImageEntityType) {
        guard let processedData = ImageSyncService.shared.processImageForLocal(image, type: entityType.imageType) else { return }

        let context = PersistenceController.shared.container.viewContext

        Task { @MainActor in
            let request = NSFetchRequest<NSManagedObject>(entityName: entityType.entityName)
            request.predicate = NSPredicate(format: "id == %@", entityId as CVarArg)

            do {
                if let entity = try context.fetch(request).first {
                    entity.setValue(processedData, forKey: "imageData")
                    try context.save()
                }
            } catch {
                print("❌ SyncableImageView 回寫圖片失敗: \(error)")
            }
        }
    }
}

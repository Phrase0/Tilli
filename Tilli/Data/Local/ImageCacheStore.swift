//
//  ImageCacheStore.swift
//  Tilli
//
//  Created by Peiyun on 2026/9/12.
//
//  把遠端下載回來的圖片回寫到 CoreData 的本機快取。
//  （由原 View/Components/EntityImageView.swift 抽出 —— View 不該直接操作 CoreData，
//   見 CONVENTIONS.md「MVVM 規則」規則 2）
//

import UIKit
import CoreData

/// 圖片本機快取的寫入點
///
/// ⚠️ 這裡只負責「把下載到的圖存進本機」。實際的下載由 View 層的 Kingfisher 負責，
/// 上傳則等重建同步時由上傳端處理（見 ARCHITECTURE.md §4，`imageData` 分類為 X 純本機）。
final class ImageCacheStore {

    static let shared = ImageCacheStore()

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.context = context
    }

    /// 將圖片處理成本機規格後寫入對應 entity 的 `imageData`
    /// - Parameters:
    ///   - image: 下載回來的原圖
    ///   - kind: 決定壓縮規格與目標 entity
    ///   - id: entity 的 UUID（`.profile` 不使用）
    ///   - profileUid: 只有 `.profile` 需要 —— CDUserProfileEntity 以 uid（字串）識別，不是 UUID
    @MainActor
    func store(_ image: UIImage, kind: ImageEntityType, id: UUID, profileUid: String? = nil) {
        guard let data = ImageProcessor.processForLocal(image, type: kind.imageType) else { return }

        let request = NSFetchRequest<NSManagedObject>(entityName: kind.entityName)
        if kind == .profile {
            guard let uid = profileUid else {
                print("❌ ImageCacheStore: profile 圖片缺少 profileUid，略過")
                return
            }
            request.predicate = NSPredicate(format: "uid == %@", uid)
        } else {
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        }
        request.fetchLimit = 1

        do {
            guard let entity = try context.fetch(request).first else {
                print("❌ ImageCacheStore: 找不到 \(kind.entityName)（id: \(id)），圖片未快取")
                return
            }
            entity.setValue(data, forKey: "imageData")
            try context.save()
        } catch {
            print("❌ ImageCacheStore 回寫圖片失敗: \(error)")
        }
    }
}

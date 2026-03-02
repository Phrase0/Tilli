//
//  QRCodeRepository.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/18.
//

import CoreData
import SwiftUI
import FirebaseAuth

class QRCodeRepository: ObservableObject {

    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext
    private var syncObserver: Any?

    @Published var qrCode: QRCodeModel?

    /// 便利屬性：取得 QR Code 圖片
    var qrCodeImage: UIImage? {
        return qrCode?.image
    }

    init(container: NSPersistentContainer = PersistenceController.shared.container) {
        self.container = container
        self.context = container.viewContext
        loadQRCode()

        // 監聽 sync 完成通知（登出清資料 / 全量下載），重新讀取 CoreData
        syncObserver = NotificationCenter.default.addObserver(
            forName: .syncDidComplete, object: nil, queue: .main
        ) { [weak self] _ in
            self?.loadQRCode()
        }
    }

    deinit {
        if let observer = syncObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - QR Code Operations

    /// 載入 QR Code
    func loadQRCode() {
        let request: NSFetchRequest<CDQRCodeEntity> = CDQRCodeEntity.fetchRequest()
        request.fetchLimit = 1

        do {
            let result = try context.fetch(request)
            if let qrEntity = result.first {
                qrCode = qrEntity.toModel()
            } else {
                qrCode = nil
            }
        } catch {
            print("Load QR Code failed:", error)
            qrCode = nil
        }
    }

    /// 儲存 QR Code（upsert：id 不變，內容覆蓋）
    func saveQRCode(_ model: QRCodeModel) {
        deleteAllQRCodes()

        let entity = CDQRCodeEntity(context: context)
        entity.update(from: model, context: context)
        entity.userId = Auth.auth().currentUser?.uid ?? UserProfile.guestUserId
        entity.updatedAt = Date()
        entity.syncStatus = "pending"

        saveContext()

        DispatchQueue.main.async {
            self.qrCode = model
        }

        Task { @MainActor in
            SyncManager.shared.syncQRCode(model)
        }
    }

    /// 圖片上傳 Storage 成功後，更新 imageURL
    func updateQRCodeImageURL(_ imageURL: String) {
        guard var model = qrCode else { return }

        let request: NSFetchRequest<CDQRCodeEntity> = CDQRCodeEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", model.id as CVarArg)

        do {
            let results = try context.fetch(request)
            if let entity = results.first {
                entity.imageURL = imageURL
                entity.updatedAt = Date()
                saveContext()

                model.imageURL = imageURL
                DispatchQueue.main.async {
                    self.qrCode = model
                }

                Task { @MainActor in
                    SyncManager.shared.syncQRCode(model, imageURL: imageURL)
                }
            }
        } catch {
            print("Update QR Code imageURL failed:", error)
        }
    }

    /// 刪除 QR Code
    func deleteQRCode() {
        let deletedId = qrCode?.id

        deleteAllQRCodes()
        saveContext()

        DispatchQueue.main.async {
            self.qrCode = nil
        }

        if let id = deletedId {
            Task { @MainActor in
                SyncManager.shared.syncDeleteQRCode(id)
            }
        }
    }

    /// 刪除所有 QR Code（內部使用）
    private func deleteAllQRCodes() {
        let request: NSFetchRequest<CDQRCodeEntity> = CDQRCodeEntity.fetchRequest()

        do {
            let result = try context.fetch(request)
            for entity in result {
                context.delete(entity)
            }
        } catch {
            print("Delete QR Codes failed:", error)
        }
    }

    /// 取得 QR Code Model
    func getQRCode() -> QRCodeModel? {
        return qrCode
    }

    // MARK: - Save Context
    private func saveContext() {
        do {
            try context.save()
            print("QR Code data saved to CoreData")
        } catch {
            print("Core Data save failed:", error)
            context.rollback()
        }
    }
}

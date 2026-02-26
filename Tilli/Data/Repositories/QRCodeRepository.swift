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

    @Published var qrCode: QRCodeModel?

    /// 便利屬性：取得 QR Code 圖片
    var qrCodeImage: UIImage? {
        return qrCode?.image
    }

    init(container: NSPersistentContainer = PersistenceController.shared.container) {
        self.container = container
        self.context = container.viewContext
        loadQRCode()
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

    /// 儲存 QR Code
    func saveQRCode(_ model: QRCodeModel) {
        // 檢查是否已有 QR Code（決定是 create 還是 update）
        let isUpdate = qrCode != nil
        let oldQRCodeId = qrCode?.id

        // 先刪除所有現有的 QR Code，然後新增
        deleteAllQRCodes()

        // 新增 QR Code Entity
        let entity = CDQRCodeEntity(context: context)
        entity.update(from: model, context: context)
        entity.userId = Auth.auth().currentUser?.uid ?? UserProfile.guestUserId
        entity.updatedAt = Date()
        entity.syncStatus = "pending"

        saveContext()

        // 更新 Published 屬性
        DispatchQueue.main.async {
            self.qrCode = model
        }

        // 同步到 Firestore
        // 注意：圖片上傳需要在 View 層處理，取得 imageURL 後再同步
        Task { @MainActor in
            if isUpdate {
                // 如果有舊的，先刪除舊的
                if let oldId = oldQRCodeId, oldId != model.id {
                    SyncManager.shared.syncDeleteQRCode(oldId)
                }
                SyncManager.shared.syncQRCode(model, operation: .update)
            } else {
                SyncManager.shared.syncQRCode(model, operation: .create)
            }
        }
    }

    /// 更新 QR Code
    func updateQRCode(_ model: QRCodeModel) {
        saveQRCode(model)
    }

    /// 刪除 QR Code
    func deleteQRCode() {
        let deletedId = qrCode?.id

        deleteAllQRCodes()
        saveContext()

        // 更新 Published 屬性
        DispatchQueue.main.async {
            self.qrCode = nil
        }

        // 同步刪除到 Firestore
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

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

    /// 儲存 QR Code（upsert：id 不變，內容覆蓋）
    func saveQRCode(_ model: QRCodeModel) {
        deleteAllQRCodes()

        let entity = CDQRCodeEntity(context: context)
        entity.update(from: model, context: context)
        entity.userId = Auth.auth().currentUser?.uid ?? UserProfileModel.guestUserId
        entity.updatedAt = Date()
        entity.syncStatus = "pending"

        saveContext()

        DispatchQueue.main.async {
            self.qrCode = model
        }
        // TODO: [SYNC-PENDING] 重建同步時在此 enqueue，見 ARCHITECTURE.md
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
            // TODO: [SYNC-PENDING] 重建同步時在此 enqueue，見 ARCHITECTURE.md
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

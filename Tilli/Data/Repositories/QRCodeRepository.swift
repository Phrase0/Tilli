//
//  QRCodeRepository.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/18.
//

import CoreData
import SwiftUI

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
        // 先刪除所有現有的 QR Code，然後新增
        deleteAllQRCodes()

        // 新增 QR Code Entity
        let entity = CDQRCodeEntity(context: context)
        entity.update(from: model, context: context)

        // 設定 sync 相關欄位（由 Repository 處理）
        // entity.userId = AuthManager.shared.currentUserId  // Phase 1.4 時啟用
        entity.updatedAt = Date()
        entity.syncStatus = "pending"

        saveContext()

        // 更新 Published 屬性
        DispatchQueue.main.async {
            self.qrCode = model
        }
    }

    /// 更新 QR Code
    func updateQRCode(_ model: QRCodeModel) {
        saveQRCode(model)
    }

    /// 刪除 QR Code
    func deleteQRCode() {
        deleteAllQRCodes()
        saveContext()

        // 更新 Published 屬性
        DispatchQueue.main.async {
            self.qrCode = nil
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

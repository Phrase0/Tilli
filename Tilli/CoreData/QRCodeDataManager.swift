//
//  QRCodeDataManager.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/18.
//

import CoreData
import SwiftUI

class QRCodeDataManager: ObservableObject {

    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext

    @Published var qrCodeImage: UIImage?

    init(container: NSPersistentContainer = PersistenceController.shared.container) {
        self.container = container
        self.context = container.viewContext
        loadQRCode()
    }

    // MARK: - QR Code Operations

    /// 載入 QR Code 圖片
    func loadQRCode() {
        let request: NSFetchRequest<CDQRCodeEntity> = CDQRCodeEntity.fetchRequest()
        request.fetchLimit = 1

        do {
            let result = try context.fetch(request)
            if let qrEntity = result.first {
                qrCodeImage = UIImage(data: qrEntity.imageData)
            } else {
                qrCodeImage = nil
            }
        } catch {
            print("Load QR Code failed:", error)
            qrCodeImage = nil
        }
    }

    /// 儲存 QR Code 圖片
    func saveQRCode(_ image: UIImage) {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            print("Failed to convert image to data")
            return
        }

        // 先刪除所有現有的 QR Code，然後新增
        deleteAllQRCodes()

        // 新增 QR Code
        let qrEntity = CDQRCodeEntity(context: context)
        qrEntity.id = UUID()
        qrEntity.createdAt = Date()
        qrEntity.imageData = imageData

        saveContext()

        // 更新 Published 屬性
        DispatchQueue.main.async {
            self.qrCodeImage = image
        }
    }

    /// 更新 QR Code 圖片
    func updateQRCode(_ image: UIImage) {
        saveQRCode(image) // 因為邏輯相同，直接呼叫 saveQRCode
    }

    /// 刪除 QR Code
    func deleteQRCode() {
        deleteAllQRCodes()
        saveContext()

        // 更新 Published 屬性
        DispatchQueue.main.async {
            self.qrCodeImage = nil
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

    /// 取得 QR Code 圖片
    func getQRCode() -> UIImage? {
        return qrCodeImage
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

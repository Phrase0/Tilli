//
//  QRCodeViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2026/9/3.
//

import SwiftUI

class QRCodeViewModel: ObservableObject {

    @Published var showingImagePicker = false
    @Published var tempSelectedImage: UIImage?
    @Published var showDeleteAlert = false

    /// 將選好的圖片存成 QRCodeModel。本地優先：一定成功；實際上傳交給 SyncManager 背景處理
    /// （跟商品、個人資料同一套模式，離線或失敗會自動排進佇列重試，不會像之前那樣失敗了也沒人知道）
    @MainActor
    func handleSelectedImage(
        _ image: UIImage,
        qrCodeDataManager: QRCodeRepository
    ) {
        var model = QRCodeModel(
            id: qrCodeDataManager.qrCode?.id ?? UUID(),
            imageData: nil,
            imageURL: nil,
            createdAt: qrCodeDataManager.qrCode?.createdAt ?? Date()
        )
        model.image = image
        qrCodeDataManager.saveQRCode(model)
        tempSelectedImage = nil
    }

    func deleteQRCode(qrCodeDataManager: QRCodeRepository) {
        qrCodeDataManager.deleteQRCode()
    }
}

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

    /// 將選好的圖片存成 QRCodeModel，並非同步上傳、回填圖片 URL
    @MainActor
    func handleSelectedImage(
        _ image: UIImage,
        qrCodeDataManager: QRCodeRepository,
        authManager: AuthenticationManager
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

        guard authManager.isLoggedIn else { return }

        Task {
            do {
                let imageURL = try await ImageSyncService.shared.uploadQRCodeImage(image)
                guard authManager.isLoggedIn else { return }
                await MainActor.run {
                    qrCodeDataManager.updateQRCodeImageURL(imageURL)
                }
            } catch {
                print("QRCode image upload failed: \(error)")
            }
        }
    }

    func deleteQRCode(qrCodeDataManager: QRCodeRepository) {
        qrCodeDataManager.deleteQRCode()
    }
}

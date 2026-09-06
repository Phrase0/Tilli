//
//  ImageSyncService.swift
//  Tilli
//
//  Created by Peiyun on 2026/2/4.
//  Created for CoreData + Firebase Sync
//  處理圖片的壓縮、上傳到 Firebase Storage、以及下載
//

import UIKit
import FirebaseStorage
import FirebaseAuth

// MARK: - 圖片類型

/// 圖片類型，決定處理規格
enum ImageType {
    /// QR Code：512x512px PNG 無損
    case qrCode
    /// 縮圖（產品、頭貼）：200x200px JPEG 壓縮
    case thumbnail

    /// 目標尺寸
    var targetSize: CGFloat {
        switch self {
        case .qrCode: return 512
        case .thumbnail: return 200
        }
    }

    /// 是否使用 PNG 格式
    var usePNG: Bool {
        switch self {
        case .qrCode: return true
        case .thumbnail: return false
        }
    }

    /// JPEG 壓縮品質（僅 thumbnail 使用）
    var compressionQuality: CGFloat {
        switch self {
        case .qrCode: return 1.0  // PNG 不需要
        case .thumbnail: return 0.8
        }
    }

    /// Content-Type
    var contentType: String {
        switch self {
        case .qrCode: return "image/png"
        case .thumbnail: return "image/jpeg"
        }
    }

    /// 檔案副檔名
    var fileExtension: String {
        switch self {
        case .qrCode: return "png"
        case .thumbnail: return "jpg"
        }
    }
}

/// 圖片同步服務
/// 負責圖片壓縮、上傳到 Firebase Storage、以及下載
class ImageSyncService {
    static let shared = ImageSyncService()

    private let storage = Storage.storage()

    private init() {}

    // MARK: - Current User ID

    private var currentUserId: String? {
        return Auth.auth().currentUser?.uid
    }

    // MARK: - Storage Paths

    /// 產品圖片路徑
    private func productImagePath(productId: UUID) -> String {
        guard let userId = currentUserId else { return "" }
        return "users/\(userId)/products/\(productId.uuidString).\(ImageType.thumbnail.fileExtension)"
    }

    /// QR Code 圖片路徑（固定檔名，上傳即覆蓋舊的）
    private func qrCodeImagePath() -> String {
        guard let userId = currentUserId else { return "" }
        return "users/\(userId)/qrcode.\(ImageType.qrCode.fileExtension)"
    }

    /// 頭貼圖片路徑（固定檔名，上傳即覆蓋舊的）
    private func profileImagePath(uid: String) -> String {
        return "users/\(uid)/profile.\(ImageType.thumbnail.fileExtension)"
    }

    // MARK: - 本地圖片處理（供 Model 使用）

    /// 處理圖片供本地儲存（調整尺寸 + 轉換格式）
    /// - Parameters:
    ///   - image: 原始圖片
    ///   - type: 圖片類型
    /// - Returns: 處理後的圖片資料
    func processImageForLocal(_ image: UIImage, type: ImageType) -> Data? {
        // 1. 調整尺寸
        let resized = resizeImageToSquare(image, targetSize: type.targetSize)

        // 2. 轉換格式
        if type.usePNG {
            return resized.pngData()
        } else {
            return resized.jpegData(compressionQuality: type.compressionQuality)
        }
    }

    // MARK: - Upload Product Image

    /// 上傳產品圖片
    /// - Parameters:
    ///   - image: 要上傳的圖片
    ///   - productId: 產品 ID
    /// - Returns: 上傳後的下載 URL
    func uploadProductImage(_ image: UIImage, productId: UUID) async throws -> String {
        guard currentUserId != nil else {
            throw SyncError.authenticationRequired
        }

        let path = productImagePath(productId: productId)
        return try await uploadImage(image, path: path, type: .thumbnail)
    }

    /// 上傳 QR Code 圖片（固定路徑，上傳即覆蓋舊的）
    /// - Parameter image: 要上傳的圖片
    /// - Returns: 上傳後的下載 URL
    func uploadQRCodeImage(_ image: UIImage) async throws -> String {
        guard currentUserId != nil else {
            throw SyncError.authenticationRequired
        }

        let path = qrCodeImagePath()
        return try await uploadImage(image, path: path, type: .qrCode)
    }

    /// 上傳頭貼圖片
    /// - Parameters:
    ///   - image: 要上傳的圖片
    ///   - uid: 用戶 UID
    /// - Returns: 上傳後的下載 URL（含時間戳避免快取）
    func uploadProfileImage(_ image: UIImage, uid: String) async throws -> String {
        let path = profileImagePath(uid: uid)
        let url = try await uploadImage(image, path: path, type: .thumbnail)

        // 加上時間戳避免快取
        let separator = url.contains("?") ? "&" : "?"
        return "\(url)\(separator)t=\(Int(Date().timeIntervalSince1970))"
    }

    // MARK: - Core Upload Method

    /// 處理並上傳圖片
    /// - Parameters:
    ///   - image: 要上傳的圖片
    ///   - path: Storage 路徑
    ///   - type: 圖片類型
    /// - Returns: 上傳後的下載 URL
    private func uploadImage(_ image: UIImage, path: String, type: ImageType) async throws -> String {
        // 1. 調整尺寸為正方形
        let resized = resizeImageToSquare(image, targetSize: type.targetSize)

        // 2. 轉換為指定格式
        let imageData: Data
        if type.usePNG {
            guard let data = resized.pngData() else {
                throw SyncError.imageUploadFailed
            }
            imageData = data
        } else {
            guard let data = resized.jpegData(compressionQuality: type.compressionQuality) else {
                throw SyncError.imageUploadFailed
            }
            imageData = data
        }

        // 3. 上傳到 Firebase Storage
        let ref = storage.reference().child(path)

        let metadata = StorageMetadata()
        metadata.contentType = type.contentType

        _ = try await ref.putDataAsync(imageData, metadata: metadata)

        // 4. 取得下載 URL
        let url = try await ref.downloadURL()
        return url.absoluteString
    }

    // MARK: - Delete Images

    /// 刪除產品圖片
    func deleteProductImage(productId: UUID) async throws {
        guard currentUserId != nil else {
            throw SyncError.authenticationRequired
        }

        let path = productImagePath(productId: productId)
        let ref = storage.reference().child(path)

        do {
            try await ref.delete()
        } catch {
            // 如果檔案不存在，不視為錯誤
            let nsError = error as NSError
            if nsError.domain == StorageErrorDomain &&
                nsError.code == StorageErrorCode.objectNotFound.rawValue {
                return
            }
            throw error
        }
    }

    /// 刪除 QR Code 圖片（固定路徑）
    func deleteQRCodeImage() async throws {
        guard currentUserId != nil else {
            throw SyncError.authenticationRequired
        }

        let path = qrCodeImagePath()
        let ref = storage.reference().child(path)

        do {
            try await ref.delete()
        } catch {
            let nsError = error as NSError
            if nsError.domain == StorageErrorDomain &&
                nsError.code == StorageErrorCode.objectNotFound.rawValue {
                return
            }
            throw error
        }
    }

    // MARK: - Image Processing

    /// 調整圖片為正方形並縮放到指定尺寸
    /// - Parameters:
    ///   - image: 原始圖片
    ///   - targetSize: 目標尺寸（寬高相同）
    /// - Returns: 調整後的正方形圖片
    private func resizeImageToSquare(_ image: UIImage, targetSize: CGFloat) -> UIImage {
        // 先把 imageOrientation 烘進實際像素資料。image.size 是照 imageOrientation 校正過的「顯示」尺寸，
        // 但 .cgImage 是原始像素資料、不認得 imageOrientation；直接拿校正過的座標去裁未校正的像素，
        // 遇到非 .up 方向的照片（例如直式拍攝的相機照片）就會裁到錯的位置。這裡先正規化，讓兩邊座標系統一致。
        let normalized = normalizedOrientation(image)
        let size = normalized.size

        // 1. 先裁切為正方形
        let squareSize = min(size.width, size.height)
        let origin = CGPoint(
            x: (size.width - squareSize) / 2,
            y: (size.height - squareSize) / 2
        )
        let cropRect = CGRect(origin: origin, size: CGSize(width: squareSize, height: squareSize))

        guard let cgImage = normalized.cgImage?.cropping(to: cropRect) else {
            return normalized
        }

        let croppedImage = UIImage(cgImage: cgImage, scale: normalized.scale, orientation: .up)

        // 2. 縮放到目標尺寸
        let newSize = CGSize(width: targetSize, height: targetSize)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            croppedImage.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return resized
    }

    /// 把 imageOrientation 烘進實際像素資料（重新畫一次），讓 .cgImage 的座標系統跟 .size 一致
    private func normalizedOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

}


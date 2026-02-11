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

    /// QR Code 圖片路徑
    private func qrCodeImagePath(qrCodeId: UUID) -> String {
        guard let userId = currentUserId else { return "" }
        return "users/\(userId)/qrcodes/\(qrCodeId.uuidString).\(ImageType.qrCode.fileExtension)"
    }

    /// 頭貼圖片路徑
    private func profileImagePath(uid: String) -> String {
        return "profile_photos/\(uid).\(ImageType.thumbnail.fileExtension)"
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

    /// 處理圖片並返回 UIImage（供 View 使用）
    /// - Parameters:
    ///   - image: 原始圖片
    ///   - type: 圖片類型
    /// - Returns: 處理後的 UIImage
    func processImage(_ image: UIImage, type: ImageType) -> UIImage {
        return resizeImageToSquare(image, targetSize: type.targetSize)
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

    /// 上傳 QR Code 圖片
    /// - Parameters:
    ///   - image: 要上傳的圖片
    ///   - qrCodeId: QR Code ID
    /// - Returns: 上傳後的下載 URL
    func uploadQRCodeImage(_ image: UIImage, qrCodeId: UUID) async throws -> String {
        guard currentUserId != nil else {
            throw SyncError.authenticationRequired
        }

        let path = qrCodeImagePath(qrCodeId: qrCodeId)
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

    /// 刪除 QR Code 圖片
    func deleteQRCodeImage(qrCodeId: UUID) async throws {
        guard currentUserId != nil else {
            throw SyncError.authenticationRequired
        }

        let path = qrCodeImagePath(qrCodeId: qrCodeId)
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

    /// 刪除頭貼圖片
    func deleteProfileImage(uid: String) async throws {
        let path = profileImagePath(uid: uid)
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

    /// 根據 URL 刪除圖片
    func deleteImageByURL(_ urlString: String) async throws {
        guard !urlString.isEmpty else { return }

        do {
            let ref = storage.reference(forURL: urlString)
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

    /// 批次刪除多個圖片
    func deleteImages(urls: [String]) async {
        for url in urls where !url.isEmpty {
            do {
                try await deleteImageByURL(url)
            } catch {
                // 記錄錯誤但繼續刪除其他圖片
                print("刪除圖片失敗: \(url), error: \(error)")
            }
        }
    }

    // MARK: - Image Processing

    /// 調整圖片為正方形並縮放到指定尺寸
    /// - Parameters:
    ///   - image: 原始圖片
    ///   - targetSize: 目標尺寸（寬高相同）
    /// - Returns: 調整後的正方形圖片
    private func resizeImageToSquare(_ image: UIImage, targetSize: CGFloat) -> UIImage {
        let size = image.size

        // 1. 先裁切為正方形
        let squareSize = min(size.width, size.height)
        let origin = CGPoint(
            x: (size.width - squareSize) / 2,
            y: (size.height - squareSize) / 2
        )
        let cropRect = CGRect(origin: origin, size: CGSize(width: squareSize, height: squareSize))

        guard let cgImage = image.cgImage?.cropping(to: cropRect) else {
            return image
        }

        let croppedImage = UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)

        // 2. 縮放到目標尺寸
        let newSize = CGSize(width: targetSize, height: targetSize)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            croppedImage.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return resized
    }

    // MARK: - Download Image

    /// 從 URL 下載圖片
    /// - Parameter urlString: 圖片 URL
    /// - Returns: 下載的圖片，如果失敗則返回 nil
    func downloadImage(from urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            print("下載圖片失敗: \(error)")
            return nil
        }
    }

    /// 從 Storage 路徑下載圖片資料
    /// - Parameter path: Storage 路徑
    /// - Returns: 圖片資料
    func downloadImageData(from path: String) async throws -> Data {
        let ref = storage.reference().child(path)

        // 最大下載 5MB
        let maxSize: Int64 = 5 * 1024 * 1024
        return try await ref.data(maxSize: maxSize)
    }

    // MARK: - Check Image Exists

    /// 檢查產品圖片是否存在於 Storage
    func productImageExists(productId: UUID) async -> Bool {
        guard currentUserId != nil else { return false }

        let path = productImagePath(productId: productId)
        let ref = storage.reference().child(path)

        do {
            _ = try await ref.getMetadata()
            return true
        } catch {
            return false
        }
    }

    /// 檢查 QR Code 圖片是否存在於 Storage
    func qrCodeImageExists(qrCodeId: UUID) async -> Bool {
        guard currentUserId != nil else { return false }

        let path = qrCodeImagePath(qrCodeId: qrCodeId)
        let ref = storage.reference().child(path)

        do {
            _ = try await ref.getMetadata()
            return true
        } catch {
            return false
        }
    }
}


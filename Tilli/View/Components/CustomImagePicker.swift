//
//  CustomImagePicker.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/17.
//

import SwiftUI
import UIKit

struct CustomImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Binding var isPresented: Bool

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CustomImagePicker

        init(parent: CustomImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            var finalImage: UIImage?

            if let editedImage = info[UIImagePickerController.InfoKey.editedImage] as? UIImage {
                finalImage = editedImage
            } else if let originalImage = info[UIImagePickerController.InfoKey.originalImage] as? UIImage {
                finalImage = originalImage
            }

            // 強制轉換為正方形
            if let image = finalImage {
                parent.image = cropToSquare(image: image)
            }

            parent.isPresented = false
        }

        private func cropToSquare(image: UIImage) -> UIImage {
            // 先正規化方向，理由同 ImageSyncService.resizeImageToSquare：image.size 是校正過的顯示尺寸，
            // .cgImage 是未校正的原始像素，直接用前者的座標裁後者，非 .up 方向的照片會裁到錯的位置。
            let normalized = normalizedOrientation(image)
            let size = min(normalized.size.width, normalized.size.height)
            let origin = CGPoint(x: (normalized.size.width - size) / 2, y: (normalized.size.height - size) / 2)
            let cropRect = CGRect(origin: origin, size: CGSize(width: size, height: size))

            guard let cgImage = normalized.cgImage?.cropping(to: cropRect) else { return normalized }
            return UIImage(cgImage: cgImage, scale: normalized.scale, orientation: .up)
        }

        private func normalizedOrientation(_ image: UIImage) -> UIImage {
            guard image.imageOrientation != .up else { return image }
            let renderer = UIGraphicsImageRenderer(size: image.size)
            return renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: image.size))
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
}

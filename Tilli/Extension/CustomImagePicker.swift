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

    // 預先初始化的 picker，避免每次點擊都重新建立
    private static var sharedPicker: UIImagePickerController?

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CustomImagePicker

        init(parent: CustomImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            picker.dismiss(animated: true)

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
            let size = min(image.size.width, image.size.height)
            let origin = CGPoint(x: (image.size.width - size) / 2, y: (image.size.height - size) / 2)
            let cropRect = CGRect(origin: origin, size: CGSize(width: size, height: size))

            guard let cgImage = image.cgImage?.cropping(to: cropRect) else { return image }
            return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            parent.isPresented = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        // 如果已經有預先初始化的 picker，直接使用
        if let existingPicker = Self.sharedPicker {
            existingPicker.delegate = context.coordinator
            return existingPicker
        }

        // 首次建立 picker 並快取
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true

        Self.sharedPicker = picker
        return picker
    }

    // 靜態方法用於預先初始化
    static func preloadImagePicker() {
        if sharedPicker == nil {
            DispatchQueue.main.async {
                let picker = UIImagePickerController()
                picker.sourceType = .photoLibrary
                picker.allowsEditing = true
                sharedPicker = picker
            }
        }
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
}

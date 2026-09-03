//
//  ProfileEditViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2026/9/3.
//

import SwiftUI

class ProfileEditViewModel: ObservableObject {

    @Published var name: String = ""
    @Published var selectedImage: UIImage?
    @Published var isSaving = false
    @Published var errorMessage: String?

    var isNameValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var canSave: Bool {
        isNameValid && !isSaving
    }

    func loadExistingName(from user: UserProfile) {
        name = user.name
    }

    /// 上傳圖片並更新使用者資料，回傳是否成功
    @discardableResult
    @MainActor
    func saveProfile(authManager: AuthenticationManager) async -> Bool {
        guard isNameValid else { return false }

        isSaving = true
        errorMessage = nil

        do {
            var photoURL: String? = nil

            if let image = selectedImage,
               let uid = authManager.currentUser?.uid {
                photoURL = try await ImageSyncService.shared.uploadProfileImage(image, uid: uid)
            }

            let trimmedName = name.trimmingCharacters(in: .whitespaces)
            let processedImage = selectedImage.map { ImageSyncService.shared.processImage($0, type: .thumbnail) }
            await authManager.updateProfile(name: trimmedName, photoURL: photoURL, localImage: processedImage)

            isSaving = false
            return true

        } catch {
            isSaving = false
            errorMessage = String.localized("profileEditSaveError \(error.localizedDescription)")
            print("Save profile error: \(error)")
            return false
        }
    }
}

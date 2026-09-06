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

    func loadExistingName(from user: UserProfileModel) {
        name = user.name
    }

    /// 更新使用者資料（本地優先：一定成功，不管有沒有網路；頭貼上傳交給 AuthenticationManager 背景處理）
    @discardableResult
    @MainActor
    func saveProfile(authManager: AuthenticationManager) async -> Bool {
        guard isNameValid else { return false }

        isSaving = true
        errorMessage = nil

        // 直接把選好的圖傳下去，只在 UserProfileModel.image 的 setter 裡處理一次，
        // 不要在這裡先處理一次——商品、QRCode 都只處理一次，這裡也要一致，處理兩次會放大裁切誤差。
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        await authManager.updateProfile(name: trimmedName, image: selectedImage)

        isSaving = false
        return true
    }
}

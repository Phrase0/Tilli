//
//  ProfileEditView.swift
//  Tilli
//
//  Created by Peiyun on 2025/1/21.
//

import SwiftUI
import FirebaseStorage
import Kingfisher

struct ProfileEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthenticationManager

    /// 是否為新用戶（從登入流程進入）
    let isNewUser: Bool

    // MARK: - State
    @State private var name: String = ""
    @State private var selectedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    // MARK: - Validation
    private var isNameValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canSave: Bool {
        isNameValid && !isSaving
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    // 標題說明
                    if isNewUser {
                        VStack(spacing: 8) {
                            Text("設定您的個人資料")
                                .font(.title2)
                                .fontWeight(.bold)

                            Text("請輸入您的名稱，頭貼為選填")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 24)
                    }

                    // 頭貼選擇
                    Button {
                        showingImagePicker = true
                    } label: {
                        ZStack {
                            // 圖片內容
                            if let image = selectedImage {
                                // 1. 優先顯示剛選的新照片
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(Circle())
                            } else if let localImage = authManager.localProfileImage {
                                // 2. 顯示本地快取的照片（立即顯示）
                                Image(uiImage: localImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(Circle())
                            } else if let photoURL = authManager.currentUser?.photoURL,
                                      let url = URL(string: photoURL) {
                                // 3. 用 Kingfisher 載入現有照片
                                KFImage(url)
                                    .placeholder { placeholderWithCamera }
                                    .onFailure { _ in }
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(Circle())
                            } else {
                                // 4. 沒有圖片：顯示 placeholder
                                placeholderWithCamera
                            }
                        }
                    }

                    // 姓名輸入
                    VStack(alignment: .leading, spacing: 8) {
                        Text("名稱")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TextField("請輸入您的名稱", text: $name)
                            .font(.body)
                            .padding(16)
                            .background(Color(.systemBackground))
                            .cornerRadius(12)

                        if !isNameValid && !name.isEmpty {
                            Text("名稱不可為空白")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.horizontal, 24)

                    // 錯誤訊息
                    if let error = errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    Spacer(minLength: 40)

                    // 儲存按鈕
                    Button {
                        Task {
                            await saveProfile()
                        }
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isNewUser ? "完成" : "儲存")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(canSave ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(!canSave)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle(isNewUser ? "建立個人資料" : "編輯個人資料")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true) // 始終隱藏系統返回按鈕
        .toolbar {
            // 只在編輯模式（非新用戶）時顯示取消按鈕
            if !isNewUser {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            CustomImagePicker(image: $selectedImage, isPresented: $showingImagePicker)
        }
        .onAppear {
            // 載入現有資料（編輯模式）
            if !isNewUser, let user = authManager.currentUser {
                name = user.name
            }
        }
        .interactiveDismissDisabled(isSaving || isNewUser)
    }

    // MARK: - Placeholder with Camera
    private var placeholderWithCamera: some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 120, height: 120)
            .overlay(
                VStack(spacing: 4) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.gray)
                    Text("新增照片")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            )
    }

    // MARK: - Save Profile
    private func saveProfile() async {
        guard isNameValid else { return }

        isSaving = true
        errorMessage = nil

        do {
            var photoURL: String? = nil

            // 如果有選擇新照片，上傳到 Firebase Storage
            if let image = selectedImage,
               let imageData = image.jpegData(compressionQuality: 0.7) {
                photoURL = try await uploadPhoto(imageData)
            }

            // 更新 UserProfile（同時傳遞本地圖片）
            let trimmedName = name.trimmingCharacters(in: .whitespaces)
            await authManager.updateProfile(name: trimmedName, photoURL: photoURL, localImage: selectedImage)

            isSaving = false
            dismiss()

        } catch {
            isSaving = false
            errorMessage = "儲存失敗：\(error.localizedDescription)"
            print("Save profile error: \(error)")
        }
    }

    // MARK: - Upload Photo to Firebase Storage
    private func uploadPhoto(_ data: Data) async throws -> String {
        guard let uid = authManager.currentUser?.uid else {
            throw NSError(domain: "ProfileEdit", code: -1, userInfo: [NSLocalizedDescriptionKey: "用戶未登入"])
        }

        let storageRef = Storage.storage().reference()
        let photoRef = storageRef.child("profile_photos/\(uid).jpg")

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await photoRef.putDataAsync(data, metadata: metadata)
        let downloadURL = try await photoRef.downloadURL()

        let urlString = downloadURL.absoluteString
        let separator = urlString.contains("?") ? "&" : "?"
        return "\(urlString)\(separator)t=\(Int(Date().timeIntervalSince1970))"
    }
}

//
//  SignInView.swift
//  Tilli
//
//  Created by Peiyun on 2025/1/20.
//

import SwiftUI

struct SignInView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthenticationManager

    var body: some View {
        ZStack {
            DesignSystem.ColorToken.paper
                .ignoresSafeArea()

            VStack(spacing: DesignSystem.Spacing.lg) {
                Spacer()

                VStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(DesignSystem.ColorToken.muted)

                    Text("signInWelcome")
                        .font(DesignSystem.Typography.title2)

                    Text("signInSubtitle")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                }

                Spacer()

                VStack(spacing: DesignSystem.Spacing.md) {
                    Button {
                        authManager.signInWithApple()
                    } label: {
                        HStack {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 16, weight: .medium))
                            Text("signInApple")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignSystem.Spacing.md)
                        .background(DesignSystem.ColorToken.buttonFilled)
                        .foregroundColor(DesignSystem.ColorToken.onButtonFilled)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.md))
                    }

                    Button {
                        Task {
                            await authManager.signInWithGoogle()
                            if authManager.errorMessage == nil &&
                               (authManager.authState == .needsSetup || authManager.authState == .ready) {
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "g.circle.fill")
                                .font(.system(size: 16, weight: .medium))
                            Text("signInGoogle")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignSystem.Spacing.md)
                        .background(DesignSystem.ColorToken.cardSurface)
                        .foregroundColor(DesignSystem.ColorToken.ink)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                                .stroke(DesignSystem.Border.cardColor, lineWidth: DesignSystem.Border.cardWidth)
                        )
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)

                if let errorMessage = authManager.errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.alertRed)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                }

                Spacer()
            }
        }
        .navigationTitle("signInTitle")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(authManager.isLoading)
        .onChange(of: authManager.authState) { newState in
            if newState == .needsSetup || newState == .ready {
                dismiss()
            }
        }
    }
}

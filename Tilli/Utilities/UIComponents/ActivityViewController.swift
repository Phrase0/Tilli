//
//  ActivityViewController.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/3.
//

import SwiftUI
import UIKit

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]?
    let excludedActivityTypes: [UIActivity.ActivityType]?
    let onComplete: ((Bool) -> Void)?
    
    init(
        activityItems: [Any],
        applicationActivities: [UIActivity]? = nil,
        excludedActivityTypes: [UIActivity.ActivityType]? = nil,
        onComplete: ((Bool) -> Void)? = nil
    ) {
        self.activityItems = activityItems
        self.applicationActivities = applicationActivities
        self.excludedActivityTypes = excludedActivityTypes
        self.onComplete = onComplete
    }
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        
        controller.excludedActivityTypes = excludedActivityTypes
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onComplete?(completed)
        }
        
        // 針對 iPad 設置 popover
        if let popover = controller.popoverPresentationController {
            popover.sourceView = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }?.rootViewController?.view
            popover.sourceRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // 不需要更新
    }
}

// MARK: - 便利的 View 擴展

extension View {
    /// 顯示分享界面
    /// - Parameters:
    ///   - isPresented: 控制顯示狀態的 Binding
    ///   - activityItems: 要分享的項目
    ///   - excludedTypes: 要排除的分享類型
    ///   - onComplete: 完成回調
    func shareSheet(
        isPresented: Binding<Bool>,
        activityItems: [Any],
        excludedTypes: [UIActivity.ActivityType] = [],
        onComplete: ((Bool) -> Void)? = nil
    ) -> some View {
        sheet(isPresented: isPresented) {
            ActivityViewController(
                activityItems: activityItems,
                excludedActivityTypes: excludedTypes,
                onComplete: { completed in
                    isPresented.wrappedValue = false
                    onComplete?(completed)
                }
            )
        }
    }
}

// MARK: - 預設排除的活動類型

extension UIActivity.ActivityType {
    static let defaultExcludedTypes: [UIActivity.ActivityType] = [
        .assignToContact,
        .addToReadingList,
        .postToVimeo,
        .postToFlickr,
        .postToTencentWeibo,
        .postToFacebook,
        .postToTwitter,
        .postToWeibo,
        .openInIBooks,
        .markupAsPDF
    ]
}

// MARK: - 自定義活動項目

class CustomActivityItemSource: NSObject, UIActivityItemSource {
    let csvContent: String
    let csvFileURL: URL
    let reportTitle: String
    
    init(csvContent: String, csvFileURL: URL, reportTitle: String = "CSV 報表") {
        self.csvContent = csvContent
        self.csvFileURL = csvFileURL
        self.reportTitle = reportTitle
        super.init()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return csvContent
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        switch activityType {
        case .copyToPasteboard:
            return csvContent
        case .mail, .message:
            return csvFileURL
        case .airDrop:
            return csvFileURL
        default:
            return csvFileURL
        }
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return reportTitle
    }
}
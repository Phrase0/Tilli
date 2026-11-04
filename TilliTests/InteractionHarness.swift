//
//  InteractionHarness.swift
//  TilliTests
//
//  互動驗證工具：把 SwiftUI 畫面放進視窗，開啟無障礙自動化後「按」按鈕、程式捲動，讀回捲動位置與選中狀態。
//

import XCTest
import SwiftUI

@MainActor
final class InteractionHarness<Root: View> {
    let window: UIWindow
    let host: UIHostingController<Root>

    init(_ root: Root, size: CGSize = CGSize(width: 393, height: 844)) {
        Self.enableAccessibilityAutomation()
        InteractionWarmUp.run()
        host = UIHostingController(rootView: root)
        window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        settle()
    }

    /// 讓 SwiftUI 完成版面、動畫與偏好值回報
    func settle(_ seconds: TimeInterval = 0.6) {
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// 內容最高的那個捲動畫面（商品列表；chip 列是橫向、內容很矮）
    var mainScrollView: UIScrollView? {
        allViews(window).compactMap { $0 as? UIScrollView }.max { $0.contentSize.height < $1.contentSize.height }
    }

    /// 畫面上的無障礙元素（同一個元素只算一次）
    var elements: [NSObject] {
        var seen = Set<ObjectIdentifier>()
        return Self.elements(in: window).filter { seen.insert(ObjectIdentifier($0)).inserted }
    }

    /// 有選中特性的元素標籤（chip 高亮）
    var selectedLabels: [String] {
        elements.filter { $0.accessibilityTraits.contains(.selected) }.compactMap(\.accessibilityLabel)
    }

    /// 按下標籤相符的按鈕（同名的標題文字不算）；找不到回傳 false
    @discardableResult
    func tap(_ label: String) -> Bool {
        guard let element = elements.first(where: {
            $0.accessibilityLabel == label && $0.accessibilityTraits.contains(.button)
        }) else { return false }
        let ok = element.accessibilityActivate()
        settle()
        return ok
    }

    /// 程式捲動到指定位置（不算手指捲動）
    func scroll(toY y: CGFloat) {
        guard let scrollView = mainScrollView else { return }
        let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
        scrollView.setContentOffset(CGPoint(x: 0, y: min(max(0, y), maxY)), animated: false)
        settle(0.3)
    }

    private func allViews(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(allViews) }

    private static func elements(in object: NSObject, depth: Int = 0) -> [NSObject] {
        guard depth < 40 else { return [] }
        var result: [NSObject] = []
        if let children = object.accessibilityElements as? [NSObject] {
            for child in children {
                result.append(child)
                result += elements(in: child, depth: depth + 1)
            }
        }
        if let view = object as? UIView {
            for sub in view.subviews { result += elements(in: sub, depth: depth + 1) }
        }
        return result
    }

    private static func enableAccessibilityAutomation() {
        guard let handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
              let symbol = dlsym(handle, "_AXSSetAutomationEnabled") else { return }
        typealias SetEnabled = @convention(c) (Bool) -> Void
        unsafeBitCast(symbol, to: SetEnabled.self)(true)
    }
}

/// 第一次開啟無障礙自動化後要先建立並丟掉一個畫面，否則第一個測試的操作可能還沒生效
@MainActor
private enum InteractionWarmUp {
    private static var done = false

    static func run() {
        guard !done else { return }
        done = true
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.rootViewController = UIHostingController(rootView: Button("warm-up") {})
        window.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        window.isHidden = true
    }
}

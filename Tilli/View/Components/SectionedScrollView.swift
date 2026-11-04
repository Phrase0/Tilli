//
//  SectionedScrollView.swift
//  Tilli
//
//  分區塊的捲動畫面＋上方 chip 列（收銀頁、管理商品頁共用，兩頁實作完全相同）。
//  區塊放在一般 `VStack`（非懶載入，每個區塊都回報位置），高亮規則在 `SectionHighlight`／`SectionScrollState`。
//  捲動控制（`ScrollViewReader`）只包住商品列表；點 chip 時把目標交給列表那層捲動，chip 列不在它的範圍內。
//

import SwiftUI

struct SectionedScrollView<ID: Hashable, Section: View>: View {
    private let ids: [ID]
    private let title: (ID) -> Text
    private let topPadding: CGFloat
    private let bottomPadding: CGFloat
    private let onSelect: () -> Void
    private let onUserScroll: () -> Void
    private let onBackgroundTap: (() -> Void)?
    private let section: (ID) -> Section

    @State private var state = SectionScrollState<ID>()
    /// 點 chip 要捲到的位置；列表那層捲完後清掉（同一個區塊再點也會再捲一次）
    @State private var scrollRequest: ScrollTarget?
    @State private var viewportHeight: CGFloat = 0

    private let coordinateSpaceName = "SectionedScrollView"

    init(
        ids: [ID],
        title: @escaping (ID) -> Text,
        topPadding: CGFloat = 0,
        bottomPadding: CGFloat = 0,
        onSelect: @escaping () -> Void = {},
        onUserScroll: @escaping () -> Void = {},
        onBackgroundTap: (() -> Void)? = nil,
        @ViewBuilder section: @escaping (ID) -> Section
    ) {
        self.ids = ids
        self.title = title
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
        self.onSelect = onSelect
        self.onUserScroll = onUserScroll
        self.onBackgroundTap = onBackgroundTap
        self.section = section
    }

    var body: some View {
        VStack(spacing: 0) {
            // 只有一個區塊時不顯示（跳轉沒有意義）
            if ids.count > 1 {
                SectionChipRow(
                    items: ids.map { .init(id: $0, title: title($0)) },
                    selected: state.selected,
                    onSelect: select
                )
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        // 內容最頂端（點第一個 chip 捲到這裡，連同上方留白）
                        Color.clear.frame(height: 0).id(ContentTopAnchor())
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                            ForEach(ids, id: \.self) { id in
                                section(id)
                                    .id(id)
                                    .background(reporter(.block(AnyHashable(id))))
                            }
                        }
                        .padding(.top, topPadding)
                        .padding(.bottom, bottomPadding)
                    }
                    .background(contentReporter)
                    .modifier(BackgroundTap(action: onBackgroundTap))
                }
                .coordinateSpace(name: coordinateSpaceName)
                .background(
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear { viewportHeight = geometry.size.height }
                            .onChange(of: geometry.size.height) { _, height in viewportHeight = height }
                    }
                )
                .onPreferenceChange(SectionGeometryKey.self) { values in
                    updateGeometry(values)
                }
                .onUserScroll {
                    state.userDidScroll()
                    onUserScroll()
                }
                .onChange(of: scrollRequest) { _, target in
                    guard let target else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        switch target {
                        case .contentTop: proxy.scrollTo(ContentTopAnchor(), anchor: .top)
                        case .section(let id): proxy.scrollTo(id, anchor: .top)
                        }
                    }
                    scrollRequest = nil
                }
            }
        }
        .onChange(of: ids) { _, newIDs in
            state.layoutChanged(ids: newIDs)
        }
        .onAppear {
            // 第一次出現高亮第一個；切換分頁回來保留
            state.appear(ids: ids)
        }
    }

    /// 點 chip：立刻高亮並鎖定，交給列表那層把該區塊捲到頂端（第一個區塊捲到內容最頂端）
    private func select(_ id: ID) {
        state.select(id)
        onSelect()
        scrollRequest = id == ids.first ? .contentTop : .section(id)
    }

    private enum ScrollTarget: Equatable {
        case contentTop
        case section(ID)
    }

    /// 由各區塊與整段內容的位置算出捲動量、最大捲動量與各區塊頂端，交給高亮狀態
    private func updateGeometry(_ values: [SectionGeometryItem: CGRect]) {
        guard let content = values[.content] else { return }
        let scrollY = -content.minY
        let maxScrollY = max(0, content.height - viewportHeight)
        var tops: [ID: CGFloat] = [:]
        for (item, frame) in values {
            if case .block(let key) = item, let id = key.base as? ID {
                tops[id] = frame.minY + scrollY
            }
        }
        state.geometryChanged(ids: ids, tops: tops, scrollY: scrollY, maxScrollY: maxScrollY)
    }

    private func reporter(_ item: SectionGeometryItem) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: SectionGeometryKey.self,
                value: [item: geometry.frame(in: .named(coordinateSpaceName))]
            )
        }
    }

    private var contentReporter: some View {
        reporter(.content)
    }
}

/// 內容最頂端的捲動目標（型別與區塊 id 不同，不會撞名）
private struct ContentTopAnchor: Hashable {}

/// 位置回報的對象：整段內容、或某個區塊
private enum SectionGeometryItem: Hashable {
    case content
    case block(AnyHashable)
}

/// 整段內容與各區塊在列表座標中的位置（相對列表可見範圍的頂端）
private struct SectionGeometryKey: PreferenceKey {
    static var defaultValue: [SectionGeometryItem: CGRect] = [:]

    static func reduce(value: inout [SectionGeometryItem: CGRect], nextValue: () -> [SectionGeometryItem: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// 點空白處（只在有指定動作時掛手勢，避免與卡片的點擊搶）
private struct BackgroundTap: ViewModifier {
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content
                .contentShape(Rectangle())
                .onTapGesture { action() }
        } else {
            content
        }
    }
}

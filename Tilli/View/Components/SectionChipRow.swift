//
//  SectionChipRow.swift
//  Tilli
//
//  區塊 chip 列與高亮狀態（`SectionedScrollView` 使用；收銀頁、管理商品頁共用）。
//  捲動時依序高亮：平常是佔據列表頂端的區塊；最後幾區捲不到頂端時，最後一段捲動距離平均分給它們。
//  點 chip 後鎖定高亮，直到手指捲動。
//

import SwiftUI

// MARK: - 高亮規則（純函式）

enum SectionHighlight {
    /// 依序高亮的區塊。
    /// - Parameters:
    ///   - tops: 各區塊頂端在捲動內容中的位置
    ///   - scrollY: 目前捲動量；`maxScrollY`: 最大捲動量
    /// 平常：頂端已捲到列表頂端的區塊中最後一個（還沒有則第一個）。
    /// 最後幾區頂端超過最大捲動量、永遠捲不到頂端時：從前面某個區塊到頂開始、到捲到底為止的這段距離，
    /// 平均切給它與後面的區塊，依序高亮，不會跳過。起點從最後一個捲得到頂端的區塊開始往前找，
    /// 直到每個區塊至少分到 `minimumTurnDistance`（最後一個捲得到的區塊剛好在底部才到頂時，距離幾乎是 0）。
    /// 內容一頁放得下（最大捲動量 0）時不分配，維持第一個。
    static func active<ID: Hashable>(ids: [ID], tops: [ID: CGFloat], scrollY: CGFloat, maxScrollY: CGFloat) -> ID? {
        guard let first = ids.first else { return nil }
        let tolerance: CGFloat = 1
        let minimumTurnDistance: CGFloat = 60
        let top = { (id: ID) in tops[id] ?? .infinity }
        let byTop = ids.last { top($0) <= scrollY + tolerance } ?? first

        guard maxScrollY > tolerance,
              let firstUnreachable = ids.firstIndex(where: { top($0) > maxScrollY + tolerance }),
              firstUnreachable > 0 else { return byTop }

        // 往前找起點，讓 [起點…最後] 每個區塊都分得到足夠的捲動距離
        var startIndex = firstUnreachable - 1
        while startIndex > 0,
              maxScrollY - top(ids[startIndex]) < minimumTurnDistance * CGFloat(ids.count - startIndex) {
            startIndex -= 1
        }
        let start = top(ids[startIndex])
        guard scrollY >= start else { return byTop }

        let turns = Array(ids[startIndex...])
        let span = maxScrollY - start
        guard span > tolerance else { return byTop }
        let index = Int(((scrollY - start) / span) * CGFloat(turns.count))
        return turns[min(turns.count - 1, max(0, index))]
    }
}

// MARK: - 高亮狀態

struct SectionScrollState<ID: Hashable> {
    private(set) var selected: ID?
    /// 點 chip 後鎖定高亮，直到手指捲動（程式捲動、捲動動畫不解鎖）
    private(set) var isPinned = false
    private var ids: [ID] = []
    private var tops: [ID: CGFloat] = [:]
    private var scrollY: CGFloat = 0
    private var maxScrollY: CGFloat = 0

    /// 第一次出現時高亮第一個；切換分頁回來保留
    mutating func appear(ids: [ID]) {
        self.ids = ids
        if selected == nil { selected = ids.first }
    }

    mutating func select(_ id: ID) {
        selected = id
        isPinned = true
    }

    /// 手指捲動：解鎖並依目前位置重算
    mutating func userDidScroll() {
        isPinned = false
        refresh()
    }

    /// 捲動位置改變
    mutating func geometryChanged(ids: [ID], tops: [ID: CGFloat], scrollY: CGFloat, maxScrollY: CGFloat) {
        self.ids = ids
        self.tops = tops
        self.scrollY = scrollY
        self.maxScrollY = maxScrollY
        refresh()
    }

    /// 區塊組成改變：解鎖；原本高亮的區塊不見才回到第一個
    mutating func layoutChanged(ids: [ID]) {
        self.ids = ids
        isPinned = false
        tops = tops.filter { ids.contains($0.key) }
        if let selected, ids.contains(selected) { return }
        selected = ids.first
    }

    private mutating func refresh() {
        guard !isPinned, !ids.isEmpty else { return }
        selected = SectionHighlight.active(ids: ids, tops: tops, scrollY: scrollY, maxScrollY: maxScrollY)
    }
}

// MARK: - chip 列

/// chip 的身分：包一層型別，不可與區塊 id 相同。
/// 否則外層的 `ScrollViewReader.scrollTo` 會找到同名的 chip，捲動的是 chip 列而不是商品列表
private struct ChipKey<ID: Hashable>: Hashable {
    let id: ID
}

struct SectionChipRow<ID: Hashable>: View {
    struct Item {
        let id: ID
        let title: Text
    }

    let items: [Item]
    let selected: ID?
    let onSelect: (ID) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    ForEach(items.map { ChipKey(id: $0.id) }, id: \.self) { key in
                        if let item = items.first(where: { $0.id == key.id }) {
                            chip(item)
                        }
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.xs)
            }
            // 高亮的 chip 在畫面外時，chip 列自動滑過去讓它看得到
            .onChange(of: selected) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(ChipKey(id: newValue), anchor: .center)
                }
            }
        }
    }

    /// 選中時黑底白字、未選中時灰底黑字；名稱完整顯示不截斷
    private func chip(_ item: Item) -> some View {
        let isSelected = item.id == selected
        return Button {
            onSelect(item.id)
        } label: {
            item.title
                .font(DesignSystem.Typography.caption)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.xs)
                .background(isSelected ? DesignSystem.ColorToken.ink : DesignSystem.ColorToken.quietFill)
                .foregroundColor(isSelected ? DesignSystem.ColorToken.paper : DesignSystem.ColorToken.ink)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - 手指捲動

extension View {
    /// 使用者用手指捲動時呼叫（程式捲動不觸發）
    @ViewBuilder
    func onUserScroll(_ action: @escaping () -> Void) -> some View {
        if #available(iOS 18.0, *) {
            onScrollPhaseChange { _, phase in
                if phase == .interacting { action() }
            }
        } else {
            // iOS 17 沒有捲動狀態；用同時進行的拖曳手勢偵測，不影響捲動本身
            simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { _ in action() })
        }
    }
}

//
//  EventWorkspaceView.swift
//  Tilli
//
//  Created by Peiyun on 2026/9/5.
//

import SwiftUI

/// 場次工作區的三個分頁。
enum WorkspaceTab: Hashable {
    case inventory
    case pos
    case reports
}

/// 場次工作區：管理商品 / 開始收銀 / 查看分析 三個分頁並存
///
/// 三個子頁的 ViewModel 由這裡統一持有，以建構子參數傳給子頁，子頁用 @ObservedObject 接收。
/// nav bar 的 title / toolbar 也統一由容器層宣告，依 selectedTab 切換右上角內容，
/// 避免三個子頁各自宣告 toolbar 在切換分頁時互相殘留。
struct EventWorkspaceView: View {
    let event: EventModel

    // 三個分頁共用的單一資料源（CONVENTIONS.md 規則 1 例外 2）
    @StateObject private var dataSource: EventDataSource

    @EnvironmentObject private var eventRepository: EventRepository
    @EnvironmentObject private var productRepository: ProductRepository
    @EnvironmentObject private var transactionRepository: TransactionRepository
    @EnvironmentObject private var inventoryChangeRepository: InventoryChangeRepository
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: WorkspaceTab
    @StateObject private var inventoryVM: InventoryViewModel
    @StateObject private var posVM: POSViewModel
    @StateObject private var reportsVM: ReportsViewModel

    // 匯出用的 share sheet 呈現狀態，因匯出動作(Menu)搬到容器的 toolbar，
    // 所以呈現狀態也一併由容器持有，透過 Binding 傳回子頁。
    @State private var inventoryShowShareSheet = false
    @State private var reportsShowingShareSheet = false

    // 商品新增/編輯表單的導航目標，由容器持有並在這裡宣告 navigationDestination，
    // 子頁只透過 Binding 決定要不要開表單。
    @State private var inventoryFormTarget: InventoryFormTarget?

    init(event: EventModel, initialTab: WorkspaceTab) {
        self.event = event
        _selectedTab = State(initialValue: initialTab)

        // 四者共用同一個 EventDataSource 實例
        let source = EventDataSource(event: event)
        _dataSource = StateObject(wrappedValue: source)
        _inventoryVM = StateObject(wrappedValue: InventoryViewModel(dataSource: source))
        _posVM = StateObject(wrappedValue: POSViewModel(dataSource: source))
        _reportsVM = StateObject(wrappedValue: ReportsViewModel(dataSource: source))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            InventoryView(
                event: event,
                viewModel: inventoryVM,
                showShareSheet: $inventoryShowShareSheet,
                formTarget: $inventoryFormTarget
            )
                .tabItem {
                    Image(systemName: "shippingbox")
                    // 管理商品
                    Text(String.localized("workspaceInventoryButton"))
                }
                .tag(WorkspaceTab.inventory)

            POSView(viewModel: posVM)
                .tabItem {
                    Image(systemName: "dollarsign.circle")
                    // 開始收銀
                    Text(String.localized("workspacePosButton"))
                }
                .tag(WorkspaceTab.pos)

            ReportsView(event: event, viewModel: reportsVM, showingShareSheet: $reportsShowingShareSheet)
                .tabItem {
                    Image(systemName: "chart.bar")
                    // 查看分析
                    Text(String.localized("workspaceReportsButton"))
                }
                .tag(WorkspaceTab.reports)
        }
        .onAppear {
            // Repository 走 @EnvironmentObject，在 init 取不到，這裡注入後立即載入
            dataSource.attach(
                eventRepository: eventRepository,
                productRepository: productRepository,
                transactionRepository: transactionRepository,
                inventoryChangeRepository: inventoryChangeRepository
            )
        }
        .onChange(of: dataSource.isEventDeleted) {
            // 場次被刪除 → 整個工作區退回上一頁（原本寫在 InventoryView 的 onChange 補丁）
            if dataSource.isEventDeleted { dismiss() }
        }
        .navigationTitle(dataSource.event.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                trailingToolbarContent
            }
        }
        .navigationDestination(item: $inventoryFormTarget) { target in
            switch target {
            case .new:
                AddNewProductView(event: event) {
                    inventoryVM.loadData()
                }
            case .edit(let product):
                AddNewProductView(event: event, productToEdit: product) {
                    inventoryVM.loadData()
                }
            }
        }
    }

    // MARK: - 右上角 toolbar（依 selectedTab 切換內容）

    @ViewBuilder
    private var trailingToolbarContent: some View {
        switch selectedTab {
        case .inventory:
            inventoryExportMenu
        case .pos:
            posLayoutToggle
        case .reports:
            reportsExportMenu
        }
    }

    // MARK: - 開始收銀：list/grid 切換

    private var posLayoutToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                posVM.layoutMode = posVM.layoutMode == .list ? .grid : .list
            }
        } label: {
            Image(systemName: posVM.layoutMode == .list ? "square.grid.2x2" : "list.bullet")
        }
    }

    // MARK: - 管理商品：匯出 Menu

    @ViewBuilder
    private var inventoryExportMenu: some View {
        Menu {
            Button {
                inventoryVM.prepareExport(type: .all)
                inventoryShowShareSheet = true
            } label: {
                // 全部匯出
                Label("inventoryChangeExportAll", systemImage: "square.and.arrow.up.on.square")
            }

            Divider()

            Button {
                inventoryVM.prepareExport(type: .summary)
                inventoryShowShareSheet = true
            } label: {
                // 庫存總覽
                Label("inventoryChangeExportSummary", systemImage: "list.bullet.rectangle")
            }

            Button {
                inventoryVM.prepareExport(type: .detail)
                inventoryShowShareSheet = true
            } label: {
                // 庫存異動明細
                Label("inventoryChangeExportDetail", systemImage: "clock.arrow.circlepath")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .foregroundColor(inventoryVM.isExportDisabled ? DesignSystem.ColorToken.muted : DesignSystem.ColorToken.ink)
        }
        .disabled(inventoryVM.isExportDisabled)
    }

    // MARK: - 查看分析：匯出 Menu

    @ViewBuilder
    private var reportsExportMenu: some View {
        Menu {
            switch reportsVM.selectedTab {
            case .transactions:
                Button {
                    reportsVM.prepareExport(type: .transactionDetail)
                    reportsShowingShareSheet = true
                } label: {
                    // 交易明細
                    Label("reportsExportTransactionDetail", systemImage: "list.clipboard")
                }

            case .performance:
                Button {
                    reportsVM.prepareExport(type: .productPerformanceAll)
                    reportsShowingShareSheet = true
                } label: {
                    // 全部匯出
                    Label("reportsExportAll", systemImage: "square.and.arrow.up.on.square")
                }

                Divider()

                Button {
                    reportsVM.prepareExport(type: .topProducts)
                    reportsShowingShareSheet = true
                } label: {
                    // 熱門商品排行
                    Label("reportsExportTopProducts", systemImage: "chart.bar")
                }

                Button {
                    reportsVM.prepareExport(type: .categoryAnalysis)
                    reportsShowingShareSheet = true
                } label: {
                    // 類別銷售匯總
                    Label("reportsExportCategoryAnalysis", systemImage: "folder")
                }

            case .analytics:
                Button {
                    reportsVM.prepareExport(type: .salesAnalyticsAll)
                    reportsShowingShareSheet = true
                } label: {
                    // 全部匯出
                    Label("reportsExportAll", systemImage: "square.and.arrow.up.on.square")
                }

                Divider()

                Button {
                    reportsVM.prepareExport(type: .hourlyAnalysis)
                    reportsShowingShareSheet = true
                } label: {
                    // 時段銷售分析
                    Label("reportsExportHourlyAnalysis", systemImage: "clock")
                }

                Button {
                    reportsVM.prepareExport(type: .paymentMethod)
                    reportsShowingShareSheet = true
                } label: {
                    // 支付方式分析
                    Label("reportsExportPaymentMethod", systemImage: "creditcard")
                }

                Button {
                    reportsVM.prepareExport(type: .dailyRevenueTrend)
                    reportsShowingShareSheet = true
                } label: {
                    // 日營收趨勢
                    Label("reportsExportDailyRevenue", systemImage: "chart.line.uptrend.xyaxis")
                }

                if event.dateType == .permanent {
                    Button {
                        reportsVM.prepareExport(type: .monthlyRevenueTrend)
                        reportsShowingShareSheet = true
                    } label: {
                        // 月營收趨勢
                        Label("reportsExportMonthlyRevenue", systemImage: "calendar")
                    }
                }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .foregroundColor(
                    reportsVM.isCurrentTabExportDisabled()
                        ? DesignSystem.ColorToken.muted
                        : DesignSystem.ColorToken.ink
                )
        }
        .disabled(reportsVM.isCurrentTabExportDisabled())
    }
}

//
//  NetworkMonitor.swift
//  Tilli
//
//  Created by Peiyun on 2026/1/30.
//  Created for CoreData + Firebase Sync
//  使用 Alamofire 監控網路狀態
//

import Foundation
import Alamofire

class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let reachabilityManager = NetworkReachabilityManager()
    private var statusChangeCallback: ((Bool) -> Void)?

    /// 當前是否有網路連線
    var isConnected: Bool {
        return reachabilityManager?.isReachable ?? false
    }

    /// 是否透過 WiFi 連線
    var isConnectedViaWiFi: Bool {
        return reachabilityManager?.isReachableOnEthernetOrWiFi ?? false
    }

    /// 是否透過行動網路連線
    var isConnectedViaCellular: Bool {
        return reachabilityManager?.isReachableOnCellular ?? false
    }

    private init() {}

    /// 開始監控網路狀態
    func startMonitoring(onStatusChange: @escaping (Bool) -> Void) {
        statusChangeCallback = onStatusChange

        reachabilityManager?.startListening { [weak self] status in
            switch status {
            case .reachable(.ethernetOrWiFi), .reachable(.cellular):
                self?.handleNetworkRestored()
                onStatusChange(true)

            case .notReachable, .unknown:
                onStatusChange(false)
            }
        }
    }

    /// 停止監控
    func stopMonitoring() {
        reachabilityManager?.stopListening()
        statusChangeCallback = nil
    }

    /// 網路恢復時的處理
    private func handleNetworkRestored() {
        Task {
            // 處理待同步的操作
            await SyncManager.shared.processPendingQueue()
        }
    }
}

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

    // TODO: [SYNC-PENDING] 重建同步後，網路恢復時【只做一件事】：叫醒 OutboxWorker。
    // ⚠️ 絕對不要在這裡觸發 pull —— reachability 在切換 Wi-Fi／進出隧道時會連續觸發，
    //    每次都全量下載是最大的成本地雷。見 SYNC_ARCHITECTURE_V2.md §8.3、§9.4
}

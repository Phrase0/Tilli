//
//  CoreDataError.swift
//  Tilli
//
//  Created by Peiyun on 2025/10/9.
//

import Foundation

/// 統一的 CoreData 錯誤類型
enum CoreDataError: Error, LocalizedError {
    case entityNotFound(String)
    case saveFailed(Error)
    case fetchFailed(Error)
    case relationshipError(String)
    case validationError(String)
    case contextMergeError(Error)
    
    var errorDescription: String? {
        switch self {
        case .entityNotFound(let description):
            return "找不到資料: \(description)"
        case .saveFailed(let error):
            return "儲存失敗: \(error.localizedDescription)"
        case .fetchFailed(let error):
            return "查詢失敗: \(error.localizedDescription)"
        case .relationshipError(let description):
            return "關聯錯誤: \(description)"
        case .validationError(let description):
            return "驗證錯誤: \(description)"
        case .contextMergeError(let error):
            return "Context 合併錯誤: \(error.localizedDescription)"
        }
    }
}

/// CoreData 操作結果
enum CoreDataResult<T> {
    case success(T)
    case failure(CoreDataError)
    
    var isSuccess: Bool {
        switch self {
        case .success:
            return true
        case .failure:
            return false
        }
    }
    
    var value: T? {
        switch self {
        case .success(let value):
            return value
        case .failure:
            return nil
        }
    }
    
    var error: CoreDataError? {
        switch self {
        case .success:
            return nil
        case .failure(let error):
            return error
        }
    }
}

/// 統一的錯誤處理協議
protocol CoreDataErrorHandling {
    func handleError(_ error: Error, operation: String)
    func logError(_ error: CoreDataError, operation: String)
}

/// 預設的錯誤處理實現
extension CoreDataErrorHandling {
    func handleError(_ error: Error, operation: String) {
        let coreDataError: CoreDataError
        
        if let cdError = error as? CoreDataError {
            coreDataError = cdError
        } else {
            coreDataError = .saveFailed(error)
        }
        
        logError(coreDataError, operation: operation)
    }
    
    func logError(_ error: CoreDataError, operation: String) {
        print("🔴 CoreData Error in \(operation): \(error.localizedDescription)")
        
        #if DEBUG
        // 在開發環境中提供更詳細的錯誤信息
        switch error {
        case .saveFailed(let underlyingError), .fetchFailed(let underlyingError), .contextMergeError(let underlyingError):
            print("🔍 Underlying error: \(underlyingError)")
        default:
            break
        }
        #endif
    }
}

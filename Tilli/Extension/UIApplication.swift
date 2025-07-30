//
//  Untitled.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/22.
//

import SwiftUI

extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

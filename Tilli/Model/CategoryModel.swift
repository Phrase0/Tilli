//
//  CategoryModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/8/3.
//
import SwiftUI

struct CategoryModel: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var products: [ProductModel] = []
    var createdAt: Date = Date()
    var isDisabled: Bool = false 
}

extension CategoryModel {
    init(entity: CDCategoryEntity) {
        self.id = entity.id
        self.name = entity.name
        self.createdAt = entity.createdAt
        self.products = (entity.products as? Set<CDProductEntity>)?.compactMap { $0.toModel() } ?? []
        self.isDisabled = entity.isDisabled
        
    }
}


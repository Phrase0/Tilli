//
//  CDQRCodeEntity+CoreDataProperties.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/18.
//

import Foundation
import CoreData
import UIKit

extension CDQRCodeEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDQRCodeEntity> {
        return NSFetchRequest<CDQRCodeEntity>(entityName: "CDQRCodeEntity")
    }

    @NSManaged public var id: UUID
    @NSManaged public var imageData: Data
    @NSManaged public var createdAt: Date

}

extension CDQRCodeEntity : Identifiable {

}

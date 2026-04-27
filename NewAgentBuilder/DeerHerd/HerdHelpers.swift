//
//  HerdHelpers.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/24/25.
//

import Foundation


// MARK: - UTType+KML.swift
import UniformTypeIdentifiers

extension UTType {
    static var kml: UTType {
        UTType(filenameExtension: "kml") ?? .xml
    }
    
    static var kmz: UTType {
        UTType(filenameExtension: "kmz") ?? .zip
    }
    
    static var jpg: UTType {
        UTType.jpeg
    }
}

// MARK: - Date+Extensions.swift
import Foundation

extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
    
    var endOfDay: Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return Calendar.current.date(byAdding: components, to: startOfDay) ?? self
    }
}

// MARK: - CLLocationCoordinate2D+Hashable.swift
import CoreLocation

extension CLLocationCoordinate2D: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(latitude)
        hasher.combine(longitude)
    }
    
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

// MARK: - View+Extensions.swift
import SwiftUI

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

//
//  ColorExtension.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 4/30/25.
//

import SwiftUI

extension Color {
    static let platformDarkGray: Color = {
        #if os(iOS)
        return Color(UIColor.darkGray)
        #elseif os(macOS)
        return Color(NSColor.darkGray)
        #endif
    }()
    
    static let platformBackground: Color = {
        #if os(iOS)
        return Color(UIColor.systemBackground)
        #elseif os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #endif
    }()
    static let platformSecondaryBackground: Color = {
        #if os(iOS)
        return Color(UIColor.systemGray5)
        #elseif os(macOS)
        return Color(NSColor.controlBackgroundColor)
        #endif
    }()
}

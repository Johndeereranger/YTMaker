//
//  CrossPlatformColors.swift
//  NewAgentBuilder
//
//  Created by Claude on 2/5/26.
//
//  Cross-platform color definitions for iOS and macOS compatibility.
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Cross-Platform Colors

extension Color {
    /// Background color for control areas (sidebars, panels)
    static var platformControlBackground: Color {
        #if os(macOS)
        Color(NSColor.controlBackgroundColor)
        #else
        Color(UIColor.secondarySystemBackground)
        #endif
    }

    /// Color for interactive controls (buttons, etc.)
    static var platformControl: Color {
        #if os(macOS)
        Color(NSColor.controlColor)
        #else
        Color(UIColor.systemGray5)
        #endif
    }

    /// Background color for text areas
    static var platformTextBackground: Color {
        #if os(macOS)
        Color(NSColor.textBackgroundColor)
        #else
        Color(UIColor.systemBackground)
        #endif
    }
}

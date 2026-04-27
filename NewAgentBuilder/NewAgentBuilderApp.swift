//
//  NewAgentBuilderApp.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 4/28/25.
//

import SwiftUI
import FirebaseCore

//class AppDelegate: NSObject, UIApplicationDelegate {
//  func application(_ application: UIApplication,
//                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
//    FirebaseApp.configure()
//    return true
//  }
//}


// MARK: - Shared App Delegate(s)
#if os(iOS)
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        //FirebaseApp.configure()
        return true
    }
}
#elseif os(macOS)
import AppKit

class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        //FirebaseApp.configure()
        NSApp.windows.first?.toggleFullScreen(nil)
      
    }
}
#endif

@main
struct NewAgentBuilderApp: App {
    
   // @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
#if os(iOS)
@UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
#elseif os(macOS)
@NSApplicationDelegateAdaptor(MacAppDelegate.self) var delegate
#endif
    init() {
         FirebaseApp.configure() // ✅ Runs early on both iOS + macOS
     }

    var body: some Scene {
        WindowGroup {
            AgentHomeView()
                .modifier(PlatformFrameModifier())
        }
    }
}

struct PlatformFrameModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .frame(minWidth: 800, minHeight: 600)
        #else
        content
        #endif
    }
}

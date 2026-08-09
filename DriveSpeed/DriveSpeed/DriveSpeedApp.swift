//
//  DriveSpeedApp.swift
//  DriveSpeed
//
//  Created by Christopher Karr on 7/10/26.
//

import SwiftUI
import Foundation

@main
struct DriveSpeedApp: App {
    /// Window title: the app name plus its major.minor version (e.g. "DriveSpeed 1.0"),
    /// read from the bundle's marketing version (`CFBundleShortVersionString`) so it
    /// tracks the project version automatically instead of being hard-coded (FR-18).
    private static let windowTitle: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let majorMinor = version.split(separator: ".").prefix(2).joined(separator: ".")
        return majorMinor.isEmpty ? "DriveSpeed" : "DriveSpeed \(majorMinor)"
    }()

    var body: some Scene {
        // A single, unique floating window at the normal window level (FR-1,
        // FR-2). `Window`, not `WindowGroup`, because this is a one-window app
        // with no multi-window support (§3 Non-Goals) and closing it will quit
        // the app (FR-16, wired up in Increment 3.4) — no "New Window" menu item
        // spawning duplicates. The title is the app name + major.minor version
        // (FR-18), shown in the standard native title bar.
        Window(Self.windowTitle, id: "main") {
            ContentView()
        }
        // Medium default size, sized to show the numbers plus a legible
        // 60-second two-line graph; freely resizable down to the content's
        // minimum so it stays legible when smaller (FR-14, NFR-3). Increment 3.1.
        .defaultSize(width: 420, height: 320)
        // First launch only: place the window at the top-left of the screen
        // (FR-13, Increment 3.3). Like `.defaultSize`, `.defaultPosition` takes
        // effect only when there's no restored frame, so it sets the fresh-install
        // placement without disturbing 3.2's automatic restoration — every later
        // launch reopens where the window was last left. macOS keeps a window's
        // title bar clear of the menu bar, so `.topLeading` sits just below it.
        .defaultPosition(.topLeading)
        .windowResizability(.contentMinSize)
        // Remember window position and size across launches (FR-11, FR-12) with
        // no explicit persistence code: a SwiftUI `Window` scene saves and restores
        // its frame through macOS's standard window restoration. This is the
        // SwiftUI-only, lightweight path (Increment 3.2); the accepted trade-off is
        // that it rides system window restoration (subject to the "Close windows
        // when quitting an application" setting) instead of a hand-rolled
        // UserDefaults frame, which would mean reaching into the AppKit NSWindow
        // we're deliberately not using. `.defaultSize` applies only on first
        // launch, before any frame has been saved.
    }
}

//
//  LocalLogApp.swift
//  LocalLog
//
//  Created by thorfinn on 2/14/25.
//

import SwiftUI
import CoreText
import AppKit

@main
struct LocalLogApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var storageLocation = StorageLocationStore()

    init() {
        if let fontURL = Bundle.main.url(forResource: "geistmono-regular", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(storageLocation)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Entry") {
                    NotificationCenter.default.post(name: LogCommand.newEntry, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("Video Entry") {
                    NotificationCenter.default.post(name: LogCommand.startVideoEntry, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])
            }

            CommandGroup(replacing: .appVisibility) {
                Button("Toggle Archive") {
                    NotificationCenter.default.post(name: LogCommand.toggleHistory, object: nil)
                }
                .keyboardShortcut("h", modifiers: [.command])
            }

            CommandMenu("Log") {
                Button("Video Entry") {
                    NotificationCenter.default.post(name: LogCommand.startVideoEntry, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])

                Divider()

                Button("Toggle Archive") {
                    NotificationCenter.default.post(name: LogCommand.toggleHistory, object: nil)
                }
                .keyboardShortcut("h", modifiers: [.command])

                Button("Focus Search") {
                    NotificationCenter.default.post(name: LogCommand.focusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command])

                Button("Toggle Fullscreen") {
                    NotificationCenter.default.post(name: LogCommand.toggleFullscreen, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .control])

                Button("Delete Entry") {
                    NotificationCenter.default.post(name: LogCommand.deleteEntry, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: [.command])

                Divider()

                Button("Increase Text Size") {
                    NotificationCenter.default.post(name: LogCommand.increaseTextSize, object: nil)
                }
                .keyboardShortcut("+", modifiers: [.command])

                Button("Decrease Text Size") {
                    NotificationCenter.default.post(name: LogCommand.decreaseTextSize, object: nil)
                }
                .keyboardShortcut("-", modifiers: [.command])

                Button("Reset Text Size") {
                    NotificationCenter.default.post(name: LogCommand.resetTextSize, object: nil)
                }
                .keyboardShortcut("0", modifiers: [.command])
            }
        }
        .defaultSize(width: 1100, height: 600)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentSize)

        Settings {
            StorageSettingsView()
                .environmentObject(storageLocation)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var appearanceObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = NSApplication.shared.windows.first {
            if window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }

            window.title = ""
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.toolbar?.showsBaselineSeparator = false
            window.center()
        }

        updateDockIconForCurrentAppearance()
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateDockIconForCurrentAppearance()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let appearanceObserver {
            DistributedNotificationCenter.default().removeObserver(appearanceObserver)
        }
    }

    private func updateDockIconForCurrentAppearance() {
        let match = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        let assetName = (match == .darkAqua) ? "DockIconDark" : "DockIconLight"
        if let dockIcon = NSImage(named: assetName) {
            NSApp.applicationIconImage = insetDockIcon(dockIcon)
        }
    }

    private func insetDockIcon(_ source: NSImage) -> NSImage {
        let size = source.size
        guard size.width > 0, size.height > 0 else { return source }

        let insetScale: CGFloat = 0.82
        let drawSize = NSSize(width: size.width * insetScale, height: size.height * insetScale)
        let drawOrigin = NSPoint(x: (size.width - drawSize.width) / 2, y: (size.height - drawSize.height) / 2)

        let result = NSImage(size: size)
        result.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        source.draw(in: NSRect(origin: drawOrigin, size: drawSize), from: .zero, operation: .sourceOver, fraction: 1)
        result.unlockFocus()
        result.isTemplate = false
        return result
    }
}

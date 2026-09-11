import SwiftUI
import AppKit

@main
struct holdmyPenApp: App {
    init() {
        setupWindowStyle()
        registerCustomFonts()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button("About holdmyPen") {
                    showAboutPanel()
                }
            }
            // SwiftUI's default Cut/Copy/Paste menu items only validate
            // against its own text controls (TextField/TextEditor), so they
            // show up permanently disabled for our custom NSTextView-backed
            // editor. Route them to the first responder explicitly instead.
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("x", modifiers: .command)
                Button("Copy") {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("c", modifiers: .command)
                Button("Paste") {
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("v", modifiers: .command)
                Button("Select All") {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("a", modifiers: .command)
            }
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.hiddenTitleBar)
    }

    private func showAboutPanel() {
        // Version and copyright already come from Info.plist
        // (CFBundleShortVersionString / NSHumanReadableCopyright); only the
        // icon needs overriding, since the About panel would otherwise show
        // the app's Dock icon instead of the logo.
        var options: [NSApplication.AboutPanelOptionKey: Any] = [:]
        if let logo = NSImage(named: "AppLogo") {
            // The source artwork is a large square PNG with no scale hint,
            // so AppKit reads its point size as its raw pixel size. Left
            // alone, that blows out the panel's icon well and pushes the
            // name/version/copyright text outside the visible frame.
            logo.size = NSSize(width: 128, height: 128)
            options[.applicationIcon] = logo
        }
        NSApplication.shared.orderFrontStandardAboutPanel(options: options)
    }
    
    func setupWindowStyle() {
        NSWindow.allowsAutomaticWindowTabbing = false
        // Apply immediately for existing windows
        DispatchQueue.main.async {
            updateAllWindows()
        }
        // Re-apply when app becomes active (covers new windows)
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            updateAllWindows()
        }
    }

    
    private func updateAllWindows() {
        // System-provided windows (e.g. the About panel) come back with an
        // empty title, unlike our own window which keeps the app's name.
        // Skip those so this custom chrome doesn't get forced onto windows
        // that aren't ours.
        for window in NSApplication.shared.windows where !window.title.isEmpty {
            configureWindow(window)
        }
    }

    private func configureWindow(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 600, height: 450)
    }
    
    private func registerCustomFonts() {
        EditorTypography.registerBundledFonts()
    }
}


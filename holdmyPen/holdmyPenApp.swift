import SwiftUI
import AppKit

@main
struct holdmyPenApp: App {
    init() {
        setupWindowStyle()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.hiddenTitleBar)
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
        for window in NSApplication.shared.windows {
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
    }
}

// Hide title bar completely
extension NSWindow {
    open override func awakeFromNib() {
        super.awakeFromNib()
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        backgroundColor = .black
        isOpaque = true
        styleMask.insert(.fullSizeContentView)
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        isMovableByWindowBackground = true
    }
}


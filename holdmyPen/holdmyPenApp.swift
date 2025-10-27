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
        .windowStyle(.automatic)
    }
    
    func setupWindowStyle() {
        NSWindow.allowsAutomaticWindowTabbing = false
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
    }
}


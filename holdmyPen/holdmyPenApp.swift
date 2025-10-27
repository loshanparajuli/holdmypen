import SwiftUI

@main
struct holdmyPenApp: App {
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
}


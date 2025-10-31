import SwiftUI

struct ContentView: View {
    @StateObject private var noteStore = NoteStore()
    @AppStorage("isDarkMode") private var isDarkMode: Bool = true
    @AppStorage("showHistory") private var showHistory: 
    Bool = false
    @State private var showHistorySidebar: Bool = false
    @State private var timerSeconds: Int = 0
    @State private var isTimerRunning: Bool = false
    @State private var isFullscreen: Bool = false
    @State private var timer: Timer?
    
    var currentNote: Note? {
        noteStore.getCurrentNote()
    }
    
    var body: some View {
        ZStack {
            // Background
            backgroundColor
                .ignoresSafeArea()
            
            HStack(spacing: 0) {
                // Main writing area
                VStack(spacing: 0) {
                    // Text editor
                    ZStack {
                        if let note = currentNote {
                            NoteEditorView(
                                noteStore: noteStore,
                                noteId: note.id,
                                backgroundColor: backgroundColor,
                                textColor: textColor
                            )
                        } else {
                            Text("Start typing...")
                                .font(.system(size: 18, weight: .light))
                                .foregroundColor(placeholderColor)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    // Bottom toolbar - fixed at bottom
                    BottomToolbarView(
                        currentNote: currentNote,
                        isDarkMode: $isDarkMode,
                        showHistory: $showHistorySidebar,
                        timerSeconds: $timerSeconds,
                        isTimerRunning: $isTimerRunning,
                        onNewNote: {
                            noteStore.createNewNote()
                        },
                        onToggleFullscreen: {
                            toggleFullscreen()
                        },
                        backgroundColor: toolbarColor,
                        iconColor: iconColor
                    )
                }
                
                // History sidebar
                if showHistorySidebar {
                    HistorySidebarView(
                        notes: noteStore.notes,
                        currentNoteId: noteStore.currentNoteId,
                        onSelectNote: { id in
                            noteStore.switchToNote(id)
                            withAnimation {
                                showHistorySidebar = false
                            }
                        },
                        onDeleteNote: { id in
                            noteStore.deleteNote(id)
                        },
                        backgroundColor: sidebarColor,
                        textColor: textColor,
                        onClose: {
                            withAnimation {
                                showHistorySidebar = false
                            }
                        }
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: showHistorySidebar)
                }
            }
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .onChange(of: isTimerRunning) { _, newValue in
            if newValue {
                startTimer()
            } else {
                stopTimer()
            }
        }
    }
    
    // Color properties
    private var backgroundColor: Color {
        isDarkMode ? Color(hex: "000000") : Color(hex: "FFFFFF")
    }
    
    private var textColor: Color {
        isDarkMode ? Color(hex: "FFFFFF") : Color(hex: "000000")
    }
    
    private var placeholderColor: Color {
        isDarkMode ? Color(hex: "444444") : Color(hex: "CCCCCC")
    }
    
    private var toolbarColor: Color {
        Color.clear
    }
    
    private var sidebarColor: Color {
        isDarkMode ? Color(hex: "121212") : Color(hex: "FAFAFA")
    }
    
    private var iconColor: Color {
        isDarkMode ? Color(hex: "CCCCCC") : Color(hex: "333333")
    }
    
    private func toggleFullscreen() {
        if let window = NSApplication.shared.windows.first {
            isFullscreen.toggle()
            if isFullscreen {
                window.toggleFullScreen(nil)
            } else {
                window.toggleFullScreen(nil)
            }
        }
    }
    
    private func startTimer() {
        // Only reset timer if it's at 0 (new timer)
        if timerSeconds == 0 {
            timerSeconds = 15 * 60 // 15 minutes
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if timerSeconds > 0 {
                timerSeconds -= 1
            } else {
                stopTimer()
                isTimerRunning = false
                NSSound.beep()
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

#Preview {
    ContentView()
}

// Extension to create Color from hex string
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}

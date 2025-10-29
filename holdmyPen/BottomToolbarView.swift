import SwiftUI

struct BottomToolbarView: View {
    let currentNote: Note?
    @Binding var isDarkMode: Bool
    @Binding var showHistory: Bool
    @Binding var timerSeconds: Int
    @Binding var isTimerRunning: Bool
    let onNewNote: () -> Void
    let onToggleFullscreen: () -> Void
    let backgroundColor: Color
    let iconColor: Color
    
    var body: some View {
        HStack(spacing: 20) {
            Spacer()
            
            // Fullscreen toggle
            Button(action: onToggleFullscreen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundColor(iconColor)
            .help("Toggle fullscreen")
            
            // Timer
            HStack(spacing: 4) {
                // Timer icon (only shows when timer is at 0)
                if timerSeconds == 0 {
                    Button(action: {
                        isTimerRunning = true
                    }) {
                        Image(systemName: "timer")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(iconColor)
                    .help("Start timer (15 min)")
                }
                
                // Timer display and controls (shows when timer is running or paused)
                if timerSeconds > 0 {
                    HStack(spacing: 4) {
                        Text(formatTimer(timerSeconds))
                            .font(.system(size: 11, design: .monospaced))
                        
                        Button(action: {
                            timerSeconds += 5 * 60
                        }) {
                            Text("+5")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(iconColor)
                        .help("Add 5 minutes")
                        
                        // Play/Pause button on the right
                        Button(action: {
                            isTimerRunning.toggle()
                        }) {
                            Image(systemName: isTimerRunning ? "pause.fill" : "play.fill")
                                .font(.system(size: 13))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(iconColor)
                        .help(isTimerRunning ? "Pause timer" : "Resume timer")
                    }
                }
            }
            
            // Theme toggle
            Button(action: {
                isDarkMode.toggle()
            }) {
                Image(systemName: isDarkMode ? "sun.max.fill" : "moon.fill")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundColor(iconColor)
            .help("Toggle theme")
            
            // New note button
            Button(action: onNewNote) {
                Text("newnote")
                    .font(.system(size: 12, weight: .light))
            }
            .buttonStyle(.plain)
            .foregroundColor(iconColor)
            .help("New note")
            
            // History button - rightmost
            Button(action: {
                withAnimation {
                    showHistory.toggle()
                }
            }) {
                Text("history")
                    .font(.system(size: 12, weight: .light))
            }
            .buttonStyle(.plain)
            .foregroundColor(iconColor)
            .help("Show history")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: 36)
    }
    
    private func formatTimer(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}


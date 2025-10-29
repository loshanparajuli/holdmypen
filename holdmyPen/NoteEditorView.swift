import SwiftUI

extension NSTextView {
    open override var frame: CGRect {
        didSet {
            backgroundColor = .clear
            drawsBackground = true
            enclosingScrollView?.hasVerticalScroller = false
            enclosingScrollView?.hasHorizontalScroller = false
            enclosingScrollView?.scrollerStyle = .overlay
        }
    }
}

struct NoteEditorView: View {
    @ObservedObject var noteStore: NoteStore
    let noteId: UUID
    let backgroundColor: Color
    let textColor: Color
    @FocusState private var isFocused: Bool
    
    var note: Note? {
        noteStore.getCurrentNote()
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                HStack {
                    Spacer()
                        .frame(width: geometry.size.width * 0.2)
                    
                    // Text area - 60% of screen width
                    VStack {
                        TextEditor(text: Binding(
                            get: { note?.content ?? "" },
                            set: { newValue in
                                noteStore.updateCurrentNote(content: newValue)
                            }
                        ))
                        .font(.custom("PTSerif-Regular", size: note?.fontSize ?? 18))
                        .foregroundColor(textColor)
                        .frame(width: geometry.size.width * 0.6)
                        .padding(40)
                        .background(Color.clear)
                        .focused($isFocused)
                        .scrollContentBackground(.hidden)
                        .lineSpacing(8)
                    }
                    
                    Spacer()
                        .frame(width: geometry.size.width * 0.2)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(backgroundColor)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
    }
}


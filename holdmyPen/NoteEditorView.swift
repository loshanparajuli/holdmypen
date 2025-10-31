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
    @State private var placeholderText: String = ""
    private let placeholderOptions: [String] = [
        "flow in your thoughts",
        "calm, as pure as water",
        "clear your mind",
        "river flows in you",
        "heavy breathe",
        "holdyourPen"
    ]
    
    var note: Note? {
        noteStore.getCurrentNote()
    }
    
    var body: some View {
        GeometryReader { geometry in
            HStack {
                Spacer()
                    .frame(width: geometry.size.width * 0.2)

                // Text area - 60% of screen width
                VStack {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: Binding(
                            get: { note?.content ?? "" },
                            set: { newValue in
                                noteStore.updateCurrentNote(content: newValue)
                            }
                        ))
                        .font(.custom("PTSerif-Regular", size: note?.fontSize ?? 18))
                        .foregroundColor(textColor)
                        .frame(width: geometry.size.width * 0.6)
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                        .padding(40)
                        .background(Color.clear)
                        .focused($isFocused)
                        .scrollContentBackground(.hidden)
                        .lineSpacing(8)

                        if (note?.content ?? "").isEmpty {
                            Text(placeholderText)
                                .font(.custom("PTSerif-Regular", size: note?.fontSize ?? 18))
                                .foregroundColor(Color.gray.opacity(0.6))
                                .frame(width: geometry.size.width * 0.6, alignment: .topLeading)
                                .padding(40)
                                .padding(.leading, 6) // nudge right so caret doesn't overlap
                                .allowsHitTesting(false)
                        }
                    }
                }

                Spacer()
                    .frame(width: geometry.size.width * 0.2)
            }
        }
        .background(backgroundColor)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
            if (note?.content ?? "").isEmpty {
                placeholderText = placeholderOptions.randomElement() ?? ""
            }
        }
        .onChange(of: noteId) { _, _ in
            if (note?.content ?? "").isEmpty {
                placeholderText = placeholderOptions.randomElement() ?? ""
            }
        }
    }
}


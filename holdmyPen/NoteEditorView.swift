import SwiftUI
import AppKit

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

// Custom NSTextView that handles formatting commands
class FormattableTextView: NSTextView {
    
    // Intercept keyboard events
    override func keyDown(with event: NSEvent) {
        // Check for Cmd+B (bold)
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "b" {
            toggleBold(nil)
            return
        }
        
        // Check for Cmd+I (italic)
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "i" {
            toggleItalic(nil)
            return
        }
        
        // Check for Enter/Return key - reset formatting to regular
        if event.keyCode == 36 || event.keyCode == 76 { // 36 = Return, 76 = Enter
            super.keyDown(with: event) // Insert the newline first
            
            // Reset to regular font for the new line
            if let currentFont = typingAttributes[.font] as? NSFont {
                let regularFont = NSFont(name: "PTSerif-Regular", size: currentFont.pointSize) ?? currentFont
                typingAttributes[.font] = regularFont
            }
            return
        }
        
        // Pass other key events to super
        super.keyDown(with: event)
    }
    
    @objc func toggleBold(_ sender: Any?) {
        guard let textStorage = textStorage else { return }
        let selectedRange = self.selectedRange()
        
        if selectedRange.length == 0 {
            // Toggle for typing attributes
            if let font = typingAttributes[.font] as? NSFont {
                let newFont = toggleBoldFont(font)
                typingAttributes[.font] = newFont
            }
        } else {
            // Toggle for selected text
            textStorage.beginEditing()
            textStorage.enumerateAttribute(.font, in: selectedRange) { value, range, _ in
                if let font = value as? NSFont {
                    let newFont = self.toggleBoldFont(font)
                    textStorage.addAttribute(.font, value: newFont, range: range)
                }
            }
            textStorage.endEditing()
        }
        didChangeText()
    }
    
    // Helper function to toggle bold with PT Serif support
    private func toggleBoldFont(_ font: NSFont) -> NSFont {
        let fontManager = NSFontManager.shared
        let size = font.pointSize
        
        // Try using font manager first (works if fonts are properly registered)
        let isBold = font.fontDescriptor.symbolicTraits.contains(.bold)
        var newFont = isBold ?
            fontManager.convert(font, toNotHaveTrait: .boldFontMask) :
            fontManager.convert(font, toHaveTrait: .boldFontMask)
        
        // Check if font manager actually changed the font
        if newFont.fontName != font.fontName {
            return newFont
        }
        
        // Fallback: Manual mapping for PT Serif if font manager didn't work
        let fontName = font.fontName.lowercased()
        if fontName.contains("ptserif") {
            if fontName.contains("bold") {
                // Remove bold
                if fontName.contains("italic") {
                    newFont = NSFont(name: "PTSerif-Italic", size: size) ?? font
                } else {
                    newFont = NSFont(name: "PTSerif-Regular", size: size) ?? font
                }
            } else {
                // Add bold
                if fontName.contains("italic") {
                    newFont = NSFont(name: "PTSerif-BoldItalic", size: size) ?? font
                } else {
                    newFont = NSFont(name: "PTSerif-Bold", size: size) ?? font
                }
            }
        }
        
        return newFont
    }
    
    @objc func toggleItalic(_ sender: Any?) {
        guard let textStorage = textStorage else { return }
        let selectedRange = self.selectedRange()
        
        if selectedRange.length == 0 {
            // Toggle for typing attributes
            if let font = typingAttributes[.font] as? NSFont {
                let newFont = toggleItalicFont(font)
                typingAttributes[.font] = newFont
            }
        } else {
            // Toggle for selected text
            textStorage.beginEditing()
            textStorage.enumerateAttribute(.font, in: selectedRange) { value, range, _ in
                if let font = value as? NSFont {
                    let newFont = self.toggleItalicFont(font)
                    textStorage.addAttribute(.font, value: newFont, range: range)
                }
            }
            textStorage.endEditing()
        }
        didChangeText()
    }
    
    // Helper function to toggle italic with PT Serif support
    private func toggleItalicFont(_ font: NSFont) -> NSFont {
        let fontManager = NSFontManager.shared
        let size = font.pointSize
        
        // Try using font manager first (works if fonts are properly registered)
        let isItalic = font.fontDescriptor.symbolicTraits.contains(.italic)
        var newFont = isItalic ?
            fontManager.convert(font, toNotHaveTrait: .italicFontMask) :
            fontManager.convert(font, toHaveTrait: .italicFontMask)
        
        // Check if font manager actually changed the font
        if newFont.fontName != font.fontName {
            return newFont
        }
        
        // Fallback: Manual mapping for PT Serif if font manager didn't work
        let fontName = font.fontName.lowercased()
        if fontName.contains("ptserif") {
            if fontName.contains("italic") {
                // Remove italic
                if fontName.contains("bold") {
                    newFont = NSFont(name: "PTSerif-Bold", size: size) ?? font
                } else {
                    newFont = NSFont(name: "PTSerif-Regular", size: size) ?? font
                }
            } else {
                // Add italic
                if fontName.contains("bold") {
                    newFont = NSFont(name: "PTSerif-BoldItalic", size: size) ?? font
                } else {
                    newFont = NSFont(name: "PTSerif-Italic", size: size) ?? font
                }
            }
        }
        
        return newFont
    }
    
    // Make sure the text view responds to these commands
    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(toggleBold(_:)) || aSelector == #selector(toggleItalic(_:)) {
            return true
        }
        return super.responds(to: aSelector)
    }
}

// NSTextView wrapper for rich text editing
struct RichTextEditor: NSViewRepresentable {
    @Binding var attributedText: NSAttributedString
    let textColor: NSColor
    let fontSize: Double
    let placeholderText: String
    let onTextChange: (NSAttributedString) -> Void
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        
        // Replace with our custom text view
        let customTextView = FormattableTextView()
        customTextView.autoresizingMask = [.width, .height]
        scrollView.documentView = customTextView
        
        // Configure text view
        customTextView.delegate = context.coordinator
        customTextView.isRichText = true
        customTextView.allowsUndo = true
        customTextView.usesFontPanel = false
        customTextView.usesRuler = false
        customTextView.font = NSFont(name: "PTSerif-Regular", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        customTextView.textColor = textColor
        customTextView.backgroundColor = NSColor.clear
        customTextView.drawsBackground = true
        customTextView.isAutomaticQuoteSubstitutionEnabled = false
        customTextView.isAutomaticDashSubstitutionEnabled = false
        customTextView.isAutomaticTextReplacementEnabled = false
        customTextView.textContainerInset = NSSize(width: 40, height: 40)
        customTextView.textContainer?.lineFragmentPadding = 0
        
        // Set line spacing
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 8
        customTextView.defaultParagraphStyle = paragraphStyle
        customTextView.typingAttributes = [
            .font: NSFont(name: "PTSerif-Regular", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]
        
        // Configure scroll view
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? FormattableTextView else { return }
        
        // Update text color when theme changes
        textView.textColor = textColor
        textView.insertionPointColor = textColor
        
        // Update typing attributes to use current color
        var attrs = textView.typingAttributes
        attrs[.foregroundColor] = textColor
        textView.typingAttributes = attrs
        
        // Update the foreground color for ALL existing text
        if let storage = textView.textStorage, storage.length > 0 {
            storage.addAttribute(.foregroundColor, value: textColor, range: NSRange(location: 0, length: storage.length))
        }
        
        // Only update if the attributed text is different
        if !textView.attributedString().isEqual(to: attributedText) {
            let selectedRange = textView.selectedRange()
            textView.textStorage?.setAttributedString(attributedText)
            
            // Apply color to the newly set text
            if let storage = textView.textStorage, storage.length > 0 {
                storage.addAttribute(.foregroundColor, value: textColor, range: NSRange(location: 0, length: storage.length))
            }
            
            // Restore selection if valid
            if selectedRange.location <= textView.string.count {
                textView.setSelectedRange(selectedRange)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        
        init(_ parent: RichTextEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.onTextChange(textView.attributedString())
        }
    }
}

struct NoteEditorView: View {
    @ObservedObject var noteStore: NoteStore
    let noteId: UUID
    let backgroundColor: Color
    let textColor: Color
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
                        RichTextEditor(
                            attributedText: Binding(
                                get: { note?.attributedContent ?? NSAttributedString(string: "") },
                                set: { newValue in
                                    noteStore.updateCurrentNoteAttributed(attributedContent: newValue)
                                }
                            ),
                            textColor: NSColor(textColor),
                            fontSize: note?.fontSize ?? 18,
                            placeholderText: placeholderText,
                            onTextChange: { attributedString in
                                noteStore.updateCurrentNoteAttributed(attributedContent: attributedString)
                            }
                        )
                        .frame(width: geometry.size.width * 0.6)
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                        .background(Color.clear)

                        if (note?.content ?? "").isEmpty {
                            Text(placeholderText)
                                .font(.custom("PTSerif-Regular", size: note?.fontSize ?? 18))
                                .foregroundColor(Color.gray.opacity(0.6))
                                .frame(width: geometry.size.width * 0.6, alignment: .topLeading)
                                .padding(40)
                                .padding(.leading, 6)
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


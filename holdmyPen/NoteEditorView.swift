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
    var onImagePasted: ((NSImage) -> Void)?

    override func paste(_ sender: Any?) {
        if let image = NSImage(pasteboard: NSPasteboard.general) {
            onImagePasted?(image)
            return
        }
        super.paste(sender)
    }

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

// A pasted image, floating over the text: drag anywhere to move it, drag the
// bottom-right corner to resize, click the top-right badge to remove it.
// Stays clamped inside its superview (the text view) so it can't be dragged
// out of the writing area.
final class FloatingImageView: NSView {
    let imageId: UUID
    let image: NSImage
    var onFrameChanged: ((UUID, CGRect) -> Void)?
    var onDelete: ((UUID) -> Void)?

    private var dragStartLocation: NSPoint = .zero
    private var dragStartFrame: NSRect = .zero
    private var isResizing = false
    // Needs to be genuinely forgiving to hit with a mouse/trackpad — small
    // hit targets here just read as "resize doesn't work".
    private let handleSize: CGFloat = 36

    init(imageId: UUID, image: NSImage, frame: NSRect) {
        self.imageId = imageId
        self.image = image
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }

    private func deleteHandleRect() -> NSRect {
        NSRect(x: bounds.maxX - handleSize, y: 0, width: handleSize, height: handleSize)
    }

    private func resizeHandleRect() -> NSRect {
        NSRect(x: bounds.maxX - handleSize, y: bounds.maxY - handleSize, width: handleSize, height: handleSize)
    }

    // A double-headed arrow at 45° reads as "resize" the way a plain arrow
    // doesn't; shared by the cursor image and the on-image handle glyph so
    // the affordance you see matches the affordance you get.
    private static func diagonalArrowPath(center: NSPoint, armLength: CGFloat) -> NSBezierPath {
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: center.x - armLength, y: center.y))
        arrow.line(to: NSPoint(x: center.x + armLength, y: center.y))
        arrow.move(to: NSPoint(x: center.x - armLength, y: center.y))
        arrow.line(to: NSPoint(x: center.x - armLength + 4, y: center.y - 4))
        arrow.move(to: NSPoint(x: center.x - armLength, y: center.y))
        arrow.line(to: NSPoint(x: center.x - armLength + 4, y: center.y + 4))
        arrow.move(to: NSPoint(x: center.x + armLength, y: center.y))
        arrow.line(to: NSPoint(x: center.x + armLength - 4, y: center.y - 4))
        arrow.move(to: NSPoint(x: center.x + armLength, y: center.y))
        arrow.line(to: NSPoint(x: center.x + armLength - 4, y: center.y + 4))
        arrow.lineWidth = 2
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        return arrow
    }

    // AppKit has no built-in diagonal-resize cursor, so this draws one.
    private static let diagonalResizeCursor: NSCursor = {
        let size: CGFloat = 20
        let cursorImage = NSImage(size: NSSize(width: size, height: size))
        cursorImage.lockFocus()
        let center = NSPoint(x: size / 2, y: size / 2)
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.rotate(byDegrees: 45)
        transform.translateX(by: -center.x, yBy: -center.y)
        transform.concat()

        let arrow = diagonalArrowPath(center: center, armLength: 7)
        NSColor.black.setStroke()
        arrow.stroke()
        NSColor.white.setStroke()
        arrow.lineWidth = 1
        arrow.stroke()

        cursorImage.unlockFocus()
        return NSCursor(image: cursorImage, hotSpot: center)
    }()

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(resizeHandleRect(), cursor: Self.diagonalResizeCursor)
        addCursorRect(deleteHandleRect(), cursor: .pointingHand)
    }

    // A native SF Symbol reads as an intentional, polished control rather
    // than a hand-drawn glyph. The palette config tints the "x" white and
    // the circle behind it dark, independent of light/dark mode.
    private static let deleteIcon: NSImage = {
        let base = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove image") ?? NSImage()
        let config = NSImage.SymbolConfiguration(paletteColors: [.white, .black.withAlphaComponent(0.55)])
        return base.withSymbolConfiguration(config) ?? base
    }()

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds)

        NSColor.white.withAlphaComponent(0.3).setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        border.lineWidth = 1
        border.stroke()

        let deleteRect = deleteHandleRect().insetBy(dx: 6, dy: 6)
        Self.deleteIcon.draw(in: deleteRect)

        let handleRect = resizeHandleRect().insetBy(dx: 4, dy: 4)
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(ovalIn: handleRect).fill()
        let handleCenter = NSPoint(x: handleRect.midX, y: handleRect.midY)
        let handleArrow = Self.diagonalArrowPath(center: handleCenter, armLength: handleRect.width / 2 - 3)
        let handleTransform = NSAffineTransform()
        handleTransform.translateX(by: handleCenter.x, yBy: handleCenter.y)
        handleTransform.rotate(byDegrees: 45)
        handleTransform.translateX(by: -handleCenter.x, yBy: -handleCenter.y)
        NSGraphicsContext.saveGraphicsState()
        handleTransform.concat()
        NSColor.white.setStroke()
        handleArrow.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        if deleteHandleRect().contains(localPoint) {
            onDelete?(imageId)
            return
        }
        isResizing = resizeHandleRect().contains(localPoint)
        guard let superview = superview else { return }
        dragStartLocation = superview.convert(event.locationInWindow, from: nil)
        dragStartFrame = frame
    }

    override func mouseDragged(with event: NSEvent) {
        guard let superview = superview else { return }
        let currentLocation = superview.convert(event.locationInWindow, from: nil)
        let dx = currentLocation.x - dragStartLocation.x
        let dy = currentLocation.y - dragStartLocation.y
        var newFrame = dragStartFrame

        if isResizing {
            let aspectRatio = dragStartFrame.width / dragStartFrame.height
            // Whichever axis the user is dragging more dominantly drives the
            // size; the other axis is derived to keep the aspect ratio locked.
            var newWidth = max(40, dragStartFrame.width + dx)
            var newHeight = max(40, dragStartFrame.height + dy)
            if abs(dx) >= abs(dy) {
                newHeight = newWidth / aspectRatio
            } else {
                newWidth = newHeight * aspectRatio
            }

            let maxWidth = superview.bounds.width - newFrame.origin.x
            let maxHeight = superview.bounds.height - newFrame.origin.y
            if newWidth > maxWidth {
                newWidth = maxWidth
                newHeight = newWidth / aspectRatio
            }
            if newHeight > maxHeight {
                newHeight = maxHeight
                newWidth = newHeight * aspectRatio
            }

            newFrame.size.width = max(40, newWidth)
            newFrame.size.height = max(40, newHeight)
        } else {
            newFrame.origin.x += dx
            newFrame.origin.y += dy
            newFrame.origin.x = max(0, min(newFrame.origin.x, superview.bounds.width - newFrame.width))
            newFrame.origin.y = max(0, min(newFrame.origin.y, superview.bounds.height - newFrame.height))
        }

        frame = newFrame
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    override func mouseUp(with event: NSEvent) {
        onFrameChanged?(imageId, frame)
    }
}

// NSTextView wrapper for rich text editing
struct RichTextEditor: NSViewRepresentable {
    @Binding var attributedText: NSAttributedString
    let noteId: UUID
    let textColor: NSColor
    let fontSize: Double
    let placeholderText: String
    let images: [NoteImage]
    let onTextChange: (NSAttributedString) -> Void
    let onImagePasted: (NSImage) -> Void
    let onImageFrameChanged: (UUID, CGRect) -> Void
    let onImageDeleted: (UUID) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()

        // Replace with our custom text view
        let customTextView = FormattableTextView()
        customTextView.autoresizingMask = [.width, .height]
        customTextView.onImagePasted = { image in
            onImagePasted(image)
        }
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
        customTextView.textContainerInset = NSSize(width: 16, height: 40)
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
        let coordinator = context.coordinator

        // The text view itself is the source of truth while the user is
        // typing (onTextChange already reflects every keystroke back up).
        // Only touch the text storage wholesale when we're loading a
        // different note; only re-tint existing text when the theme color
        // actually changed. This avoids an O(document length) attribute
        // pass and a deep NSAttributedString equality check on every
        // keystroke.
        let isNoteSwitch = coordinator.lastNoteId != noteId
        let colorChanged = coordinator.lastTextColor != textColor

        if isNoteSwitch {
            let selectedRange = textView.selectedRange()
            textView.textStorage?.setAttributedString(attributedText)
            if let storage = textView.textStorage, storage.length > 0 {
                storage.addAttribute(.foregroundColor, value: textColor, range: NSRange(location: 0, length: storage.length))
            }
            if selectedRange.location <= textView.string.count {
                textView.setSelectedRange(selectedRange)
            }
            coordinator.lastNoteId = noteId
        } else if colorChanged, let storage = textView.textStorage, storage.length > 0 {
            storage.addAttribute(.foregroundColor, value: textColor, range: NSRange(location: 0, length: storage.length))
        }

        if colorChanged {
            textView.textColor = textColor
            textView.insertionPointColor = textColor
            var attrs = textView.typingAttributes
            attrs[.foregroundColor] = textColor
            textView.typingAttributes = attrs
            coordinator.lastTextColor = textColor
        }

        syncImageOverlays(textView: textView, coordinator: coordinator, isNoteSwitch: isNoteSwitch)
    }

    private func syncImageOverlays(textView: FormattableTextView, coordinator: Coordinator, isNoteSwitch: Bool) {
        if isNoteSwitch {
            for imageView in coordinator.imageViews.values {
                imageView.removeFromSuperview()
            }
            coordinator.imageViews.removeAll()
            coordinator.lastExclusionFrames.removeAll()
        }

        // Fast path: most notes have no images, and this runs on every
        // SwiftUI update (including every keystroke) — skip the rest entirely
        // rather than touching the text container for nothing.
        if images.isEmpty && coordinator.imageViews.isEmpty {
            return
        }

        let currentIds = Set(images.map { $0.id })
        for (id, imageView) in coordinator.imageViews where !currentIds.contains(id) {
            imageView.removeFromSuperview()
            coordinator.imageViews.removeValue(forKey: id)
        }

        for noteImage in images where coordinator.imageViews[noteImage.id] == nil {
            guard let image = NSImage(data: noteImage.imageData) else { continue }
            let frame = CGRect(x: noteImage.x, y: noteImage.y, width: noteImage.width, height: noteImage.height)
            let imageView = FloatingImageView(imageId: noteImage.id, image: image, frame: frame)
            imageView.onFrameChanged = { id, newFrame in
                onImageFrameChanged(id, newFrame)
            }
            imageView.onDelete = { id in
                onImageDeleted(id)
            }
            textView.addSubview(imageView)
            coordinator.imageViews[noteImage.id] = imageView
        }

        // Text wraps around each image's frame, converted from text-view to
        // text-container coordinates (offset by the container inset).
        // Assigning exclusionPaths forces a full layout invalidation, so only
        // do it when an image was actually added, removed, moved, or
        // resized — not on every SwiftUI update (e.g. every keystroke while
        // typing elsewhere in the note).
        let currentFrames = coordinator.imageViews.mapValues { $0.frame }
        guard currentFrames != coordinator.lastExclusionFrames else { return }
        coordinator.lastExclusionFrames = currentFrames

        if let container = textView.textContainer {
            let inset = textView.textContainerInset
            let exclusionPadding: CGFloat = 8
            container.exclusionPaths = coordinator.imageViews.values.map { imageView in
                let padded = imageView.frame.insetBy(dx: -exclusionPadding, dy: -exclusionPadding)
                let containerRect = padded.offsetBy(dx: -inset.width, dy: -inset.height)
                return NSBezierPath(rect: containerRect)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        var lastNoteId: UUID?
        var lastTextColor: NSColor?
        var imageViews: [UUID: FloatingImageView] = [:]
        var lastExclusionFrames: [UUID: CGRect] = [:]

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

    private var richTextEditor: RichTextEditor {
        RichTextEditor(
            attributedText: Binding(
                get: { noteStore.attributedContent(for: noteId) },
                set: { newValue in
                    noteStore.updateCurrentNoteAttributed(attributedContent: newValue)
                }
            ),
            noteId: noteId,
            textColor: NSColor(textColor),
            fontSize: note?.fontSize ?? 18,
            placeholderText: placeholderText,
            images: note?.images ?? [],
            onTextChange: { attributedString in
                noteStore.updateCurrentNoteAttributed(attributedContent: attributedString)
            },
            onImagePasted: { image in
                noteStore.addImage(image, to: noteId)
            },
            onImageFrameChanged: { imageId, frame in
                noteStore.updateImageFrame(
                    imageId,
                    in: noteId,
                    x: frame.origin.x,
                    y: frame.origin.y,
                    width: frame.width,
                    height: frame.height
                )
            },
            onImageDeleted: { imageId in
                noteStore.removeImage(imageId, from: noteId)
            }
        )
    }

    var body: some View {
        GeometryReader { geometry in
            HStack {
                Spacer()
                    .frame(width: geometry.size.width * 0.08)

                // Text area - 84% of screen width
                VStack {
                    ZStack(alignment: .topLeading) {
                        richTextEditor
                            .frame(width: geometry.size.width * 0.84)
                            .frame(maxHeight: .infinity, alignment: .topLeading)
                            .background(Color.clear)

                        if (note?.content ?? "").isEmpty {
                            Text(placeholderText)
                                .font(.custom("PTSerif-Regular", size: note?.fontSize ?? 18))
                                .foregroundColor(Color.gray.opacity(0.6))
                                .frame(width: geometry.size.width * 0.84, alignment: .topLeading)
                                .padding(.vertical, 40)
                                .padding(.horizontal, 16)
                                .padding(.leading, 6)
                                .allowsHitTesting(false)
                        }
                    }
                }

                Spacer()
                    .frame(width: geometry.size.width * 0.08)
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


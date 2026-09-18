import AppKit

// The editor's text view.
//
// Deliberately built on TextKit 1. A plain `NSTextView()` comes up on TextKit 2
// on macOS 12 and later, and this class drives the document through TextKit 1
// APIs throughout — `textStorage`, `layoutManager`, and the
// `NSTextContainer.exclusionPaths` that make text flow around a floating image.
// Touching any of those on a TextKit 2 view triggers an implicit downgrade
// mid-session, and how faithfully TextKit 2 honours exclusion paths has varied
// between macOS releases. `makeWithTextKit1(frame:)` builds the
// storage/layout-manager/container chain by hand so the engine is settled up
// front; construct the view that way rather than with
// `FormattableTextView(frame:)`.
final class FormattableTextView: NSTextView {
    var onImagePasted: ((NSImage) -> Void)?

    // How much clear space to leave between a floating image and the text
    // flowing around it. Enough to clear the corner points that straddle the
    // image's edge, not just the edge itself.
    static let exclusionPadding: CGFloat = 14

    // The text view's own references reach the storage only through the
    // layout manager, which doesn't own it; this keeps it alive for the
    // lifetime of the view.
    private var ownedTextStorage: NSTextStorage?

    static func makeWithTextKit1(frame: NSRect) -> FormattableTextView {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)

        let container = NSTextContainer(
            size: NSSize(width: frame.width, height: .greatestFiniteMagnitude)
        )
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        let textView = FormattableTextView(frame: frame, textContainer: container)
        textView.ownedTextStorage = storage
        return textView
    }

    // Whatever colour the current theme is painting text in. Normalized text
    // adopts it, so pasted content can't arrive in the source app's colour
    // (black text pasted into dark mode used to be invisible).
    private var currentTextColor: NSColor {
        (typingAttributes[.foregroundColor] as? NSColor) ?? textColor ?? .labelColor
    }

    // Never shorter than the visible area, so clicking in the empty space
    // under the last line still puts the caret in the note, and so a floating
    // image — a subview of this view, clamped to its bounds — can be dragged
    // anywhere on screen even in a one-line note.
    override func setFrameSize(_ newSize: NSSize) {
        var size = newSize
        if let clipView = superview as? NSClipView {
            size.width = clipView.bounds.width
            size.height = max(size.height, clipView.bounds.height)
        }
        super.setFrameSize(size)
    }

    /// One line of type, including the paragraph's line spacing — the vertical
    /// unit of the wrap grid.
    var lineHeight: CGFloat {
        let font = EditorTypography.font()
        let base = layoutManager?.defaultLineHeight(for: font)
            ?? (font.ascender - font.descender + font.leading)
        return base + EditorTypography.lineSpacing
    }

    /// The column-and-line grid floating images are placed on, or nil when the
    /// writing column is too narrow to carry one.
    var wrapGrid: WrapGrid? {
        let inset = textContainerInset
        return WrapGrid(containerWidth: bounds.width - inset.width * 2,
                        origin: CGPoint(x: inset.width, y: inset.height),
                        lineHeight: lineHeight)
    }

    /// Reflows the text around `frames`, given in this view's coordinates.
    func setImageExclusionFrames(_ frames: [CGRect]) {
        guard let container = textContainer else { return }
        let inset = textContainerInset
        let columnWidth = max(0, bounds.width - inset.width * 2)
        let grid = wrapGrid

        container.exclusionPaths = frames.map { frame in
            // Text stops at the picture's whole grid cell, so every line beside
            // it starts on the same column edge. Without a grid there's nothing
            // to align to, so fall back to holding the text off by a fixed gap.
            let cell = grid?.exclusionCell(forImageFrame: frame)
                ?? frame.insetBy(dx: -Self.exclusionPadding, dy: -Self.exclusionPadding)
                        .offsetBy(dx: -inset.width, dy: -inset.height)
            return NSBezierPath(rect: Self.sweepingAsideSlivers(cell, columnWidth: columnWidth))
        }
    }

    // An image that leaves only a sliver of column beside it gets one word per
    // line down that side, which reads as broken text rather than as wrapping.
    // When the gap on a side is too narrow to hold a sensible line, the
    // exclusion is widened out to that edge instead, so the text just flows
    // past on the other side.
    private static func sweepingAsideSlivers(_ rect: CGRect, columnWidth: CGFloat) -> CGRect {
        guard columnWidth > 0 else { return rect }
        let narrowestUsableColumn = max(120, columnWidth * 0.25)
        var left = rect.minX
        var right = rect.maxX
        if left < narrowestUsableColumn {
            left = min(0, left)
        }
        if columnWidth - right < narrowestUsableColumn {
            right = max(columnWidth, right)
        }
        return CGRect(x: left, y: rect.minY, width: right - left, height: rect.height)
    }

    override func paste(_ sender: Any?) {
        accept(NSPasteboard.general)
    }

    // Both of these are menu/keyboard routes into the same operation, and both
    // would otherwise bypass normalization.
    override func pasteAsPlainText(_ sender: Any?) {
        paste(sender)
    }

    override func pasteAsRichText(_ sender: Any?) {
        paste(sender)
    }

    // Drag-and-drop and Services read through here rather than through
    // `paste`, and carry the same foreign fonts, so they get the same
    // treatment. Dropping an image lands it as a floating image, exactly as
    // pasting one does.
    override func readSelection(from pboard: NSPasteboard) -> Bool {
        if accept(pboard) {
            return true
        }
        return super.readSelection(from: pboard)
    }

    /// Takes content from `pasteboard` on the editor's own terms: images
    /// become floating images, and text is rewritten into the editor's font
    /// and size on the way in.
    ///
    /// Deliberately not `super.paste`, which inserts the source app's fonts
    /// and sizes — exactly the inconsistency this fixes.
    @discardableResult
    private func accept(_ pasteboard: NSPasteboard) -> Bool {
        if let image = NSImage(pasteboard: pasteboard) {
            onImagePasted?(image)
            return true
        }
        guard let incoming = attributedString(from: pasteboard) else { return false }
        insertNormalized(incoming)
        return true
    }

    // Richest-first, so bold/italic survives when the source offers it and we
    // still get the text when it doesn't.
    private func attributedString(from pasteboard: NSPasteboard) -> NSAttributedString? {
        if let data = pasteboard.data(forType: .rtfd),
           let attributed = NSAttributedString(rtfd: data, documentAttributes: nil) {
            return attributed
        }
        if let data = pasteboard.data(forType: .rtf),
           let attributed = NSAttributedString(rtf: data, documentAttributes: nil) {
            return attributed
        }
        if let plain = pasteboard.string(forType: .string) {
            return NSAttributedString(string: plain)
        }
        return nil
    }

    private func insertNormalized(_ incoming: NSAttributedString) {
        let normalized = EditorTypography.normalized(incoming, color: currentTextColor)
        let range = selectedRange()
        guard shouldChangeText(in: range, replacementString: normalized.string) else { return }
        textStorage?.replaceCharacters(in: range, with: normalized)
        setSelectedRange(NSRange(location: range.location + normalized.length, length: 0))
        didChangeText()
    }

    // The font panel, the Format > Font menu and NSFontManager all funnel
    // through these. Swallowing them is what makes the size genuinely fixed
    // rather than merely defaulted.
    override func changeFont(_ sender: Any?) {}
    override func changeAttributes(_ sender: Any?) {}

    // Intercept keyboard events
    override func keyDown(with event: NSEvent) {
        // While an input method is composing (pinyin, kana, dead keys), every
        // key belongs to the IME — including Return, which confirms the
        // candidate rather than starting a new line.
        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }

        // Command on its own: Cmd+Shift+B and friends belong to whatever else
        // claims them, not to bold.
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, let key = event.charactersIgnoringModifiers?.lowercased() {
            if key == "b" {
                toggleBold(nil)
                return
            }
            if key == "i" {
                toggleItalic(nil)
                return
            }
        }

        // Enter/Return - reset formatting to regular
        if event.keyCode == 36 || event.keyCode == 76 { // 36 = Return, 76 = Enter
            super.keyDown(with: event) // Insert the newline first
            typingAttributes[.font] = EditorTypography.font()
            return
        }

        // Pass other key events to super
        super.keyDown(with: event)
    }

    @objc func toggleBold(_ sender: Any?) {
        applyToSelection { EditorTypography.font(bold: !$0.isBold, italic: $0.isItalic) }
    }

    @objc func toggleItalic(_ sender: Any?) {
        applyToSelection { EditorTypography.font(bold: $0.isBold, italic: !$0.isItalic) }
    }

    // Bold and italic are the only formatting the editor offers, and both
    // amount to swapping in a different PT Serif face at the one fixed size —
    // never a different family and never a different size.
    private func applyToSelection(_ transform: @escaping (NSFont) -> NSFont) {
        guard let textStorage = textStorage else { return }
        let selectedRange = self.selectedRange()

        if selectedRange.length == 0 {
            let current = (typingAttributes[.font] as? NSFont) ?? EditorTypography.font()
            typingAttributes[.font] = transform(current)
            return
        }

        guard shouldChangeText(in: selectedRange, replacementString: nil) else { return }
        textStorage.beginEditing()
        textStorage.enumerateAttribute(.font, in: selectedRange) { value, range, _ in
            let current = (value as? NSFont) ?? EditorTypography.font()
            textStorage.addAttribute(.font, value: transform(current), range: range)
        }
        textStorage.endEditing()
        didChangeText()
    }

    // Make sure the text view responds to these commands
    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(toggleBold(_:)) || aSelector == #selector(toggleItalic(_:)) {
            return true
        }
        return super.responds(to: aSelector)
    }
}

private extension NSFont {
    var isBold: Bool { fontDescriptor.symbolicTraits.contains(.bold) }
    var isItalic: Bool { fontDescriptor.symbolicTraits.contains(.italic) }
}

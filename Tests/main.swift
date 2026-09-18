import AppKit

// Headless checks for the "one font, one size, everywhere" rule.
//
// There is no Xcode test target in this project, so these run as a plain
// executable built from the app's own sources: `scripts/run_tests.sh`.

// The tests run as a bare executable with no app bundle, so PT Serif is
// registered straight from the source directory instead.
if let fontDirectory = ProcessInfo.processInfo.environment["HOLDMYPEN_FONT_DIR"] {
    for name in EditorTypography.bundledFontNames {
        let url = URL(fileURLWithPath: fontDirectory).appendingPathComponent("\(name).ttf")
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

var failures = 0
var checks = 0

func check(_ condition: Bool, _ message: @autoclosure () -> String) {
    checks += 1
    if !condition {
        failures += 1
        print("  FAIL  \(message())")
    }
}

func suite(_ name: String, _ body: () -> Void) {
    print("\n\(name)")
    let before = failures
    body()
    print(failures == before ? "  ok" : "  \(failures - before) failed")
}

// MARK: - Helpers

let themeColor = NSColor.white

func face(_ string: NSAttributedString, at index: Int) -> NSFont? {
    string.attribute(.font, at: index, effectiveRange: nil) as? NSFont
}

func describe(_ font: NSFont?) -> String {
    guard let font else { return "no font" }
    return "\(font.fontName) @ \(font.pointSize)"
}

/// Asserts every character uses PT Serif at the fixed size.
func checkUniformTypography(_ string: NSAttributedString, _ label: String) {
    guard string.length > 0 else { return }
    for index in 0..<string.length {
        let font = face(string, at: index)
        check(font?.pointSize == EditorTypography.fontSize,
              "\(label): char \(index) is \(describe(font)), expected size \(EditorTypography.fontSize)")
        check(font?.familyName == "PT Serif",
              "\(label): char \(index) is \(describe(font)), expected PT Serif")
    }
}

/// Stands in for text copied out of another app: a different family, a
/// different (smaller) size, a colour of its own, and extra attributes.
func foreignRichText() -> NSAttributedString {
    let result = NSMutableAttributedString()
    result.append(NSAttributedString(string: "small helvetica ", attributes: [
        .font: NSFont(name: "Helvetica", size: 11) ?? NSFont.systemFont(ofSize: 11),
        .foregroundColor: NSColor.black,
        .backgroundColor: NSColor.yellow,
        .kern: 3.0
    ]))
    result.append(NSAttributedString(string: "BIG BOLD ", attributes: [
        .font: NSFont.boldSystemFont(ofSize: 42),
        .foregroundColor: NSColor.red
    ]))
    result.append(NSAttributedString(string: "italic", attributes: [
        .font: NSFontManager.shared.convert(NSFont(name: "Times New Roman", size: 9)
            ?? NSFont.systemFont(ofSize: 9), toHaveTrait: .italicFontMask)
    ]))
    return result
}

// Kept alive for the length of the run: an NSTextView only has an undo manager
// while it's in a window, so testing undo needs a real (offscreen) one.
var hostWindows: [NSWindow] = []

func makeTextView() -> FormattableTextView {
    let frame = NSRect(x: 0, y: 0, width: 600, height: 400)
    let textView = FormattableTextView.makeWithTextKit1(frame: frame)
    textView.isRichText = true
    textView.allowsUndo = true
    textView.font = EditorTypography.font()
    textView.textColor = themeColor
    textView.typingAttributes = EditorTypography.attributes(color: themeColor)

    let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView?.addSubview(textView)
    window.makeFirstResponder(textView)
    hostWindows.append(window)

    return textView
}

// NSUndoManager closes its undo group at the end of a run-loop iteration.
// Everything here happens in one turn, so tests that care about undo steps
// have to let the loop breathe between them.
func flushRunLoop() {
    RunLoop.current.run(mode: .default, before: Date())
}

func writeToPasteboard(_ attributed: NSAttributedString) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    let range = NSRange(location: 0, length: attributed.length)
    if let rtf = try? attributed.data(from: range,
                                      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
        pasteboard.setData(rtf, forType: .rtf)
    }
    pasteboard.setString(attributed.string, forType: .string)
}

// MARK: - Tests

suite("fonts are registered") {
    for bold in [false, true] {
        for italic in [false, true] {
            let font = EditorTypography.font(bold: bold, italic: italic)
            check(font.familyName == "PT Serif", "bold:\(bold) italic:\(italic) resolved to \(describe(font))")
            check(font.pointSize == EditorTypography.fontSize, "bold:\(bold) italic:\(italic) is \(describe(font))")
            check(font.fontDescriptor.symbolicTraits.contains(.bold) == bold, "bold trait wrong for \(describe(font))")
            check(font.fontDescriptor.symbolicTraits.contains(.italic) == italic, "italic trait wrong for \(describe(font))")
        }
    }
}

suite("normalize rewrites foreign text to the editor's typography") {
    let normalized = EditorTypography.normalized(foreignRichText(), color: themeColor)

    check(normalized.string == foreignRichText().string, "text content changed")
    checkUniformTypography(normalized, "normalized")

    // Bold and italic are the app's own formatting, so they survive.
    check(face(normalized, at: 0)?.fontName == "PTSerif-Regular", "plain run became \(describe(face(normalized, at: 0)))")
    check(face(normalized, at: 16)?.fontName == "PTSerif-Bold", "bold run became \(describe(face(normalized, at: 16)))")
    check(face(normalized, at: 25)?.fontName == "PTSerif-Italic", "italic run became \(describe(face(normalized, at: 25)))")

    // Everything else the source app attached is dropped.
    for index in 0..<normalized.length {
        let attrs = normalized.attributes(at: index, effectiveRange: nil)
        check(attrs[.foregroundColor] as? NSColor == themeColor,
              "char \(index) kept a foreign colour: \(String(describing: attrs[.foregroundColor]))")
        check(attrs[.backgroundColor] == nil, "char \(index) kept a highlight")
        check(attrs[.kern] == nil, "char \(index) kept kerning")
        let spacing = (attrs[.paragraphStyle] as? NSParagraphStyle)?.lineSpacing
        check(spacing == EditorTypography.lineSpacing, "char \(index) line spacing is \(String(describing: spacing))")
    }
}

suite("normalize handles the awkward inputs") {
    let empty = EditorTypography.normalized(NSAttributedString(string: ""), color: themeColor)
    check(empty.length == 0, "empty string grew to \(empty.length)")

    // Text with no font attribute at all still lands on the editor's defaults.
    let bare = EditorTypography.normalized(NSAttributedString(string: "bare"), color: themeColor)
    checkUniformTypography(bare, "attribute-less")

    // Running it twice changes nothing.
    let once = EditorTypography.normalized(foreignRichText(), color: themeColor)
    let twice = EditorTypography.normalized(once, color: themeColor)
    check(once.isEqual(to: twice), "normalize is not idempotent")

    // Emoji and other multi-unit characters keep their runs intact.
    let emoji = EditorTypography.normalized(
        NSAttributedString(string: "a👩‍👩‍👧‍👦b", attributes: [.font: NSFont.systemFont(ofSize: 40)]),
        color: themeColor)
    check(emoji.string == "a👩‍👩‍👧‍👦b", "emoji text mangled: \(emoji.string)")
    checkUniformTypography(emoji, "emoji")
}

suite("pasting from another app adopts the editor's typography") {
    let textView = makeTextView()
    textView.string = ""
    textView.typingAttributes = EditorTypography.attributes(color: themeColor)
    textView.insertText("typed ", replacementRange: NSRange(location: 0, length: 0))

    writeToPasteboard(foreignRichText())
    textView.paste(nil)

    guard let storage = textView.textStorage else {
        check(false, "no text storage")
        return
    }
    check(storage.string == "typed small helvetica BIG BOLD italic",
          "unexpected document: \(storage.string)")
    // This is the actual bug: pasted text used to come in at 11pt/42pt next to
    // 18pt typed text.
    checkUniformTypography(storage, "document after paste")
    check(face(storage, at: 0)?.fontName == "PTSerif-Regular", "typed text changed")
}

suite("pasting plain text adopts the editor's typography") {
    let textView = makeTextView()
    textView.string = ""
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString("plain from a terminal", forType: .string)
    textView.paste(nil)
    check(textView.string == "plain from a terminal", "unexpected document: \(textView.string)")
    checkUniformTypography(textView.attributedString(), "plain paste")
}

suite("paste replaces the selection and leaves the caret after it") {
    let textView = makeTextView()
    textView.string = ""
    textView.typingAttributes = EditorTypography.attributes(color: themeColor)
    textView.insertText("keep REPLACE keep", replacementRange: NSRange(location: 0, length: 0))
    textView.setSelectedRange(NSRange(location: 5, length: 7))

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString("new", forType: .string)
    textView.paste(nil)

    check(textView.string == "keep new keep", "unexpected document: \(textView.string)")
    check(textView.selectedRange() == NSRange(location: 8, length: 0),
          "caret ended at \(textView.selectedRange())")
    checkUniformTypography(textView.attributedString(), "paste over selection")
}

suite("paste is a single undo step") {
    let textView = makeTextView()
    textView.string = ""
    textView.typingAttributes = EditorTypography.attributes(color: themeColor)
    textView.insertText("before ", replacementRange: NSRange(location: 0, length: 0))
    flushRunLoop()

    writeToPasteboard(foreignRichText())
    textView.paste(nil)
    check(textView.string.hasPrefix("before small"), "paste did not land: \(textView.string)")

    guard let undoManager = textView.undoManager else {
        check(false, "no undo manager")
        return
    }
    check(undoManager.canUndo, "paste registered no undo step")
    flushRunLoop()
    undoManager.undo()
    check(textView.string == "before ", "one undo left \(textView.string), expected \"before \"")
}

suite("pasteAsPlainText and pasteAsRichText normalize too") {
    for (label, action) in [("pasteAsPlainText", 0), ("pasteAsRichText", 1)] {
        let textView = makeTextView()
        textView.string = ""
        writeToPasteboard(foreignRichText())
        if action == 0 { textView.pasteAsPlainText(nil) } else { textView.pasteAsRichText(nil) }
        check(textView.string == foreignRichText().string, "\(label) produced: \(textView.string)")
        checkUniformTypography(textView.attributedString(), label)
    }
}

suite("dropping text from another app normalizes too") {
    let textView = makeTextView()
    textView.string = ""
    let pasteboard = NSPasteboard(name: .drag)
    pasteboard.clearContents()
    let dropped = foreignRichText()
    if let rtf = try? dropped.data(from: NSRange(location: 0, length: dropped.length),
                                   documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
        pasteboard.setData(rtf, forType: .rtf)
    }
    pasteboard.setString(dropped.string, forType: .string)

    check(textView.readSelection(from: pasteboard), "readSelection refused the drop")
    check(textView.string == dropped.string, "drop produced: \(textView.string)")
    checkUniformTypography(textView.attributedString(), "drop")
}

suite("dropping an image still becomes a floating image") {
    // Text drops route through readSelection, and a Finder image drop puts a
    // file URL (and its path as a string) on the pasteboard — so without care
    // a dropped image would insert its path as text instead.
    let textView = makeTextView()
    textView.string = ""
    var droppedImage: NSImage?
    textView.onImagePasted = { droppedImage = $0 }

    let image = NSImage(size: NSSize(width: 10, height: 10))
    image.lockFocus()
    NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 10, height: 10))
    image.unlockFocus()

    let pasteboard = NSPasteboard(name: .drag)
    pasteboard.clearContents()
    pasteboard.writeObjects([image])

    check(textView.readSelection(from: pasteboard), "readSelection refused the image")
    check(droppedImage != nil, "image drop did not reach the floating-image handler")
    check(textView.string.isEmpty, "image drop inserted text: \(textView.string)")
}

suite("nothing can resize the text") {
    let textView = makeTextView()
    textView.string = ""
    textView.typingAttributes = EditorTypography.attributes(color: themeColor)
    textView.insertText("some words", replacementRange: NSRange(location: 0, length: 0))
    textView.setSelectedRange(NSRange(location: 0, length: 10))

    // The font panel and the Format > Font menu both arrive as changeFont:.
    NSFontManager.shared.setSelectedFont(NSFont(name: "Helvetica", size: 72)!, isMultiple: false)
    textView.changeFont(NSFontManager.shared)
    checkUniformTypography(textView.attributedString(), "after changeFont:")

    // Bigger/Smaller and the text panel arrive as changeAttributes:.
    textView.changeAttributes(NSFontManager.shared)
    checkUniformTypography(textView.attributedString(), "after changeAttributes:")
}

suite("bold and italic swap face without touching size") {
    let textView = makeTextView()
    textView.string = ""
    textView.typingAttributes = EditorTypography.attributes(color: themeColor)
    textView.insertText("word", replacementRange: NSRange(location: 0, length: 0))
    textView.setSelectedRange(NSRange(location: 0, length: 4))

    textView.toggleBold(nil)
    check(face(textView.attributedString(), at: 0)?.fontName == "PTSerif-Bold",
          "bold gave \(describe(face(textView.attributedString(), at: 0)))")

    textView.toggleItalic(nil)
    check(face(textView.attributedString(), at: 0)?.fontName == "PTSerif-BoldItalic",
          "bold+italic gave \(describe(face(textView.attributedString(), at: 0)))")

    textView.toggleBold(nil)
    check(face(textView.attributedString(), at: 0)?.fontName == "PTSerif-Italic",
          "un-bold gave \(describe(face(textView.attributedString(), at: 0)))")

    textView.toggleItalic(nil)
    check(face(textView.attributedString(), at: 0)?.fontName == "PTSerif-Regular",
          "un-italic gave \(describe(face(textView.attributedString(), at: 0)))")

    checkUniformTypography(textView.attributedString(), "after formatting")
}

suite("toggling formatting repairs a stray size") {
    // A note saved by an older build can hold a 42pt run; formatting it must
    // bring it back to the fixed size rather than preserve the outlier.
    let textView = makeTextView()
    textView.string = ""
    textView.textStorage?.setAttributedString(NSAttributedString(string: "huge", attributes: [
        .font: NSFont.systemFont(ofSize: 42)
    ]))
    textView.setSelectedRange(NSRange(location: 0, length: 4))
    textView.toggleBold(nil)
    checkUniformTypography(textView.attributedString(), "after toggling a 42pt run")
}

suite("notes survive the RTF round trip at one size") {
    // What NoteStore does when it persists and reloads a note.
    var note = Note()
    note.attributedContent = EditorTypography.normalized(foreignRichText(), color: themeColor)
    let reloaded = note.attributedContent
    check(reloaded.string == foreignRichText().string, "round trip changed text: \(reloaded.string)")
    checkUniformTypography(reloaded, "after RTF round trip")
    check(note.content == foreignRichText().string, "plain mirror wrong: \(note.content)")
}

suite("a note with no rich text falls back to the editor's typography") {
    var note = Note()
    note.content = "just plain"
    check(note.attributedContentData == nil, "expected no RTF data")
    checkUniformTypography(note.attributedContent, "plain-text fallback")
}

suite("notes saved by older builds still decode") {
    // Exactly the shape earlier versions wrote, including the fontName /
    // fontSize keys this build no longer uses.
    let legacy = """
    [{"id":"6C5F8E2A-0000-4000-8000-000000000001","content":"old note",\
    "createdAt":760000000,"modifiedAt":760000000,"fontName":"System","fontSize":24}]
    """
    guard let decoded = try? JSONDecoder().decode([Note].self, from: Data(legacy.utf8)) else {
        check(false, "legacy note failed to decode")
        return
    }
    check(decoded.count == 1, "expected 1 note, got \(decoded.count)")
    check(decoded.first?.content == "old note", "content wrong: \(decoded.first?.content ?? "nil")")
    check(decoded.first?.images.isEmpty == true, "images should default to empty")
    // The stored 24pt is ignored — the note renders at the one fixed size.
    checkUniformTypography(decoded.first!.attributedContent, "legacy note")

    // And a note this build writes still carries the keys an older build reads.
    guard let reencoded = try? JSONEncoder().encode(decoded),
          let object = try? JSONSerialization.jsonObject(with: reencoded) as? [[String: Any]] else {
        check(false, "re-encode failed")
        return
    }
    check(object.first?["fontName"] != nil, "fontName dropped from saved notes")
    check(object.first?["fontSize"] != nil, "fontSize dropped from saved notes")
}

suite("the text view comes up on TextKit 1") {
    // Order matters: reading `layoutManager` is itself what drags a TextKit 2
    // view down into TextKit 1 compatibility mode, so asking which engine it
    // is on has to come first or the question answers itself.
    let textView = FormattableTextView.makeWithTextKit1(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    check(textView.textLayoutManager == nil, "text view came up on TextKit 2")
    check(textView.layoutManager != nil, "no TextKit 1 layout manager")
    check(textView.textStorage != nil, "no text storage")
    check(textView.textContainer?.lineFragmentPadding == 0, "container padding was not cleared")

    // The storage is only reachable through the layout manager, which does not
    // own it — losing it would empty the editor.
    check(textView.textStorage === textView.layoutManager?.textStorage,
          "text view and layout manager disagree about the storage")
}

suite("text flows around a floating image") {
    let textView = makeTextView()
    textView.textContainerInset = NSSize(width: 16, height: 40)
    textView.textContainer?.lineFragmentPadding = 0
    textView.typingAttributes = EditorTypography.attributes(color: themeColor)
    textView.string = ""
    textView.insertText(String(repeating: "word ", count: 200),
                        replacementRange: NSRange(location: 0, length: 0))

    guard let layoutManager = textView.layoutManager, let container = textView.textContainer else {
        check(false, "no TextKit 1 stack")
        return
    }

    func heightOfLaidOutText() -> CGFloat {
        layoutManager.ensureLayout(for: container)
        return layoutManager.usedRect(for: container).height
    }

    let plainHeight = heightOfLaidOutText()
    // An image parked over the first few lines, in the text view's own
    // coordinates — the same thing FloatingImageView hands over.
    textView.setImageExclusionFrames([CGRect(x: 20, y: 50, width: 240, height: 200)])
    let wrappedHeight = heightOfLaidOutText()

    check(container.exclusionPaths.count == 1,
          "expected 1 exclusion path, got \(container.exclusionPaths.count)")
    // Text pushed aside by the image has to go somewhere, so the document
    // grows. If wrapping is being ignored, the two heights are identical.
    check(wrappedHeight > plainHeight,
          "text did not reflow around the image (\(plainHeight) -> \(wrappedHeight))")

    // The first line beside the image has to start clear of it: the image sits
    // at x=20..260 in view coordinates, i.e. x=4..244 in the container.
    let imageBottomInContainer = 50 + 200 - textView.textContainerInset.height
    var foundLineBesideImage = false
    layoutManager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs)) { _, used, _, _, stop in
        if used.midY < imageBottomInContainer {
            foundLineBesideImage = true
            check(used.minX >= 244, "a line beside the image starts at x=\(used.minX), inside it")
            stop.pointee = true
        }
    }
    check(foundLineBesideImage, "no line was laid out alongside the image")

    // Clearing the frames puts the text back.
    textView.setImageExclusionFrames([])
    check(container.exclusionPaths.isEmpty, "exclusion paths were not cleared")
    check(heightOfLaidOutText() == plainHeight, "text did not flow back after the image was removed")
}

suite("a sliver of column beside an image is not used for text") {
    // Wrapping into a gap too narrow for a line gives one word per line down
    // the side of the image, which reads as broken rather than as wrapping.
    let textView = makeTextView()
    textView.textContainerInset = NSSize(width: 16, height: 40)
    textView.textContainer?.lineFragmentPadding = 0
    textView.typingAttributes = EditorTypography.attributes(color: themeColor)
    textView.string = ""
    textView.insertText(String(repeating: "word ", count: 200),
                        replacementRange: NSRange(location: 0, length: 0))

    guard let layoutManager = textView.layoutManager, let container = textView.textContainer else {
        check(false, "no TextKit 1 stack")
        return
    }

    // 600 wide less two 16pt insets leaves a 568pt column. With the 8pt
    // breathing room around the image, this one covers 252...508 of it — a
    // roomy 252pt on the left and a 60pt sliver on the right, wide enough for
    // TextKit to drop one short word per line into if it is left alone.
    let image = CGRect(x: 276, y: 100, width: 240, height: 160)
    textView.setImageExclusionFrames([image])
    layoutManager.ensureLayout(for: container)

    let padding = FormattableTextView.exclusionPadding
    let band = (top: 100 - 40 - padding, bottom: 100 + 160 - 40 + padding)
    var linesBesideImage = 0
    var textOnTheSliver = 0
    layoutManager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs)) { _, used, _, _, _ in
        guard used.midY > band.top && used.midY < band.bottom else { return }
        linesBesideImage += 1
        if used.minX >= 508 { textOnTheSliver += 1 }
    }
    check(linesBesideImage > 0, "no lines were laid out alongside the image at all")
    check(textOnTheSliver == 0, "\(textOnTheSliver) lines were squeezed into the gap right of the image")
}

suite("the text view stays at least as tall as the window") {
    // Floating images are subviews of the text view and clamped to its bounds,
    // and a click below the last line has to land in the text. Both break if
    // the text view shrinks to fit a one-line note.
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    let textView = FormattableTextView.makeWithTextKit1(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    textView.autoresizingMask = [.width]
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.minSize = .zero
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                              height: CGFloat.greatestFiniteMagnitude)
    scrollView.documentView = textView
    scrollView.layoutSubtreeIfNeeded()

    textView.typingAttributes = EditorTypography.attributes(color: themeColor)
    textView.string = ""
    textView.insertText("one short line", replacementRange: NSRange(location: 0, length: 0))
    textView.layoutManager?.ensureLayout(for: textView.textContainer!)
    scrollView.layoutSubtreeIfNeeded()

    let visibleHeight = scrollView.contentView.bounds.height
    check(textView.frame.height >= visibleHeight,
          "text view is \(textView.frame.height) tall, shorter than the \(visibleHeight) on screen")
}

suite("typing does not republish the note list") { MainActor.assumeIsolated {
    let suiteName = "holdmyPen.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = NoteStore(defaults: defaults)
    store.createNewNote()
    guard let id = store.currentNoteId else {
        check(false, "no current note")
        return
    }
    let before = store.notes

    // What the editor hands over: already in the editor's typography.
    store.updateCurrentNoteAttributed(
        attributedContent: EditorTypography.normalized(
            NSAttributedString(string: "half a sentence"), color: themeColor))

    // The keystroke path only touches the caches; `notes` is @Published, and
    // rewriting it on every keystroke is what made typing stutter.
    check(store.notes == before, "typing mutated the published note list")
    check(store.isCurrentNoteEmpty == false, "placeholder flag did not clear")
    check(store.attributedContent(for: id).string == "half a sentence",
          "live text was not readable back")

    // ...and the text is still there once anything actually reads the notes.
    store.flushPendingEdits()
    check(store.getCurrentNote()?.content == "half a sentence",
          "flush lost the text: \(store.getCurrentNote()?.content ?? "nil")")
    checkUniformTypography(store.getCurrentNote()!.attributedContent, "flushed note")
} }

suite("a corner drag resizes from that corner and keeps the aspect ratio") {
    // 240x160 — a 3:2 picture — sitting well inside a roomy page.
    let original = CGRect(x: 200, y: 200, width: 240, height: 160)
    let page = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    let aspectRatio = original.width / original.height

    for corner in FloatingImageView.ResizeCorner.allCases {
        // Drag the corner outwards, diagonally away from its anchor.
        let anchor = corner.anchor(in: original)
        let target = CGPoint(x: anchor.x + (corner.growsLeftward ? -360 : 360),
                             y: anchor.y + (corner.growsUpward ? -240 : 240))
        let resized = FloatingImageView.resizedImageFrame(
            original: original, corner: corner, dragTo: target, within: page)

        check(abs(resized.width / resized.height - aspectRatio) < 0.001,
              "\(corner) gave \(resized.width)x\(resized.height), ratio \(resized.width / resized.height)")
        // The opposite corner is the one thing a corner drag must not move.
        let anchorAfter = corner.anchor(in: resized)
        check(abs(anchorAfter.x - anchor.x) < 0.001 && abs(anchorAfter.y - anchor.y) < 0.001,
              "\(corner) moved its anchor from \(anchor) to \(anchorAfter)")
        check(resized.width > original.width, "\(corner) dragged outwards but shrank")
    }
}

suite("each corner points its resize cursor along the right diagonal") {
    // On screen (y growing downward) top-left and bottom-right lie along "\\",
    // the other two along "/". Getting this backwards gives every corner a
    // cursor that contradicts the direction it actually resizes in.
    check(FloatingImageView.ResizeCorner.topLeft.isBackslashDiagonal, "top-left should be \\")
    check(FloatingImageView.ResizeCorner.bottomRight.isBackslashDiagonal, "bottom-right should be \\")
    check(!FloatingImageView.ResizeCorner.topRight.isBackslashDiagonal, "top-right should be /")
    check(!FloatingImageView.ResizeCorner.bottomLeft.isBackslashDiagonal, "bottom-left should be /")

    // And the direction each corner grows in, which is what the anchor maths
    // and the clamping both key off.
    check(FloatingImageView.ResizeCorner.topLeft.growsLeftward
            && FloatingImageView.ResizeCorner.topLeft.growsUpward, "top-left grows up and left")
    check(!FloatingImageView.ResizeCorner.bottomRight.growsLeftward
            && !FloatingImageView.ResizeCorner.bottomRight.growsUpward, "bottom-right grows down and right")
}

suite("a corner drag stays inside the page and above the minimum size") {
    let original = CGRect(x: 200, y: 200, width: 240, height: 160)
    let page = CGRect(x: 0, y: 0, width: 1000, height: 1000)

    // Dragged far past the edge of the page.
    let overshot = FloatingImageView.resizedImageFrame(
        original: original, corner: .bottomRight, dragTo: CGPoint(x: 5000, y: 5000), within: page)
    check(page.contains(overshot), "\(overshot) escaped the page")
    check(abs(overshot.width / overshot.height - 240.0 / 160.0) < 0.001,
          "clamping to the page broke the aspect ratio: \(overshot)")

    // Dragged back past its own anchor, which would otherwise invert it.
    let collapsed = FloatingImageView.resizedImageFrame(
        original: original, corner: .bottomRight, dragTo: CGPoint(x: 100, y: 100), within: page)
    check(collapsed.width >= FloatingImageView.minimumSide
            && collapsed.height >= FloatingImageView.minimumSide,
          "collapsed to \(collapsed.width)x\(collapsed.height)")
    check(abs(collapsed.width / collapsed.height - 240.0 / 160.0) < 0.001,
          "the minimum size broke the aspect ratio: \(collapsed)")
}

suite("moving an image keeps it on the page at its original size") {
    let original = CGRect(x: 200, y: 200, width: 240, height: 160)
    let page = CGRect(x: 0, y: 0, width: 1000, height: 1000)

    let moved = FloatingImageView.movedImageFrame(
        original: original, by: CGSize(width: 60, height: -40), within: page)
    check(moved == CGRect(x: 260, y: 160, width: 240, height: 160), "moved to \(moved)")

    for offset in [CGSize(width: -9999, height: -9999), CGSize(width: 9999, height: 9999)] {
        let shoved = FloatingImageView.movedImageFrame(original: original, by: offset, within: page)
        check(page.contains(shoved), "\(shoved) escaped the page")
        check(shoved.size == original.size, "moving resized it to \(shoved.size)")
    }
}

suite("the chrome ring does not swallow clicks meant for the text") {
    // The view is padded out beyond the picture to hold the corner points and
    // the remove badge; that padding must stay click-through or every image
    // would sit in a dead zone where the caret can't be placed.
    let image = NSImage(size: NSSize(width: 10, height: 10))
    image.lockFocus()
    NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 10, height: 10))
    image.unlockFocus()

    let host = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let picture = NSRect(x: 200, y: 200, width: 240, height: 160)
    let view = FloatingImageView(imageId: UUID(), image: image, imageFrame: picture)
    host.addSubview(view)

    check(view.imageFrame == picture, "imageFrame came back as \(view.imageFrame)")
    check(view.frame.insetBy(dx: FloatingImageView.chromePadding, dy: FloatingImageView.chromePadding) == picture,
          "the chrome ring is not centred on the picture: \(view.frame)")

    // Superview coordinates, which is what hitTest is given.
    check(view.hitTest(CGPoint(x: 300, y: 260)) === view, "a click on the picture missed it")
    for corner in FloatingImageView.ResizeCorner.allCases {
        let point = corner.position(in: picture)
        check(view.hitTest(point) === view, "the \(corner) point could not be grabbed")
    }
    // Empty ring: just outside the picture, away from every corner and badge.
    check(view.hitTest(CGPoint(x: 320, y: picture.maxY + 12)) == nil,
          "the empty chrome ring below the picture swallowed a click")
    check(view.hitTest(CGPoint(x: 600, y: 400)) == nil, "hit test claimed a point nowhere near it")
}

// A 1000pt writing column at the editor's own line height.
func testGrid() -> WrapGrid {
    WrapGrid(containerWidth: 1000,
             origin: CGPoint(x: 16, y: 40),
             lineHeight: 32)!
}

suite("the wrap grid divides the column into whole columns") {
    let grid = testGrid()
    check(abs(grid.containerWidth - 1000) < 0.001, "container width came back as \(grid.containerWidth)")
    check(grid.columnCount == 12, "expected 12 columns, got \(grid.columnCount)")
    // 12 columns and the 11 gutters between them fill the column exactly.
    check(abs(grid.width(spanning: 12) - 1000) < 0.001,
          "a full-width span is \(grid.width(spanning: 12)), not 1000")
    check(abs(grid.width(spanning: 1) - (grid.pitch - grid.gutter)) < 0.001, "one column is wrong")
    // Each span is the columns plus the gutters between them.
    check(abs(grid.width(spanning: 3) - (3 * grid.pitch - grid.gutter)) < 0.001, "three columns are wrong")

    check(grid.columnSpan(forWidth: grid.width(spanning: 4)) == 4, "a 4-column width did not read back as 4")
    check(grid.columnSpan(forWidth: 1) == 1, "a hairline width should still be one column")
    check(grid.columnSpan(forWidth: 99999) == 12, "an enormous width should cap at the full column")

    // Too narrow to carry a grid at all.
    check(WrapGrid(containerWidth: 40, origin: .zero, lineHeight: 32) == nil,
          "a 40pt column should have no grid")
}

suite("a picture snaps onto a column start and a line of type") {
    let grid = testGrid()
    let page = CGRect(x: 0, y: 0, width: 1032, height: 2000)
    let size = CGSize(width: grid.width(spanning: 4), height: 200)

    // Dropped at a deliberately awkward offset.
    let loose = CGRect(x: 16 + grid.pitch * 2 + 19, y: 40 + 32 * 5 + 11,
                       width: size.width, height: size.height)
    let snapped = grid.snappedOrigin(for: loose, within: page)

    let column = (snapped.x - grid.origin.x) / grid.pitch
    check(abs(column - column.rounded()) < 0.001, "x landed between columns at \(snapped.x)")
    check(Int(column.rounded()) == 2, "expected column 2, got \(column)")
    let line = (snapped.y - grid.origin.y) / grid.lineHeight
    check(abs(line - line.rounded()) < 0.001, "y landed between lines at \(snapped.y)")
    check(Int(line.rounded()) == 5, "expected line 5, got \(line)")

    // A picture shoved off the right edge comes back to the last column that
    // can hold it, rather than hanging over the edge.
    let overshot = CGRect(x: 5000, y: 40, width: size.width, height: size.height)
    let pulledBack = grid.snappedOrigin(for: overshot, within: page)
    let lastColumn = (pulledBack.x - grid.origin.x) / grid.pitch
    check(Int(lastColumn.rounded()) == 12 - 4, "a 4-column picture should stop at column 8, got \(lastColumn)")
    check(pulledBack.x + size.width <= grid.origin.x + grid.containerWidth + 0.001,
          "it still hangs off the right edge")

    // And never above the first line.
    let above = grid.snappedOrigin(for: CGRect(x: 16, y: -500, width: size.width, height: size.height),
                                   within: page)
    check(above.y == grid.origin.y, "a picture dragged above the text should stop at the first line")
}

suite("resizing lands on a whole number of columns") {
    let grid = testGrid()
    // 3:2, a bit wider than three columns.
    let loose = CGSize(width: grid.width(spanning: 3) + 22, height: (grid.width(spanning: 3) + 22) / 1.5)
    guard let snapped = grid.snappedSize(for: loose, fittingWidth: 1000, height: 2000, minimumSide: 40) else {
        check(false, "no snapped size came back")
        return
    }
    check(abs(snapped.width - grid.width(spanning: 3)) < 0.001,
          "expected 3 columns (\(grid.width(spanning: 3))), got \(snapped.width)")
    check(abs(snapped.width / snapped.height - 1.5) < 0.001,
          "snapping to columns broke the 3:2 ratio: \(snapped.width / snapped.height)")

    // When the space left won't hold the rounded-up span, it steps down a
    // column rather than overflowing.
    guard let squeezed = grid.snappedSize(for: loose, fittingWidth: grid.width(spanning: 2) + 5,
                                          height: 2000, minimumSide: 40) else {
        check(false, "no snapped size came back for the squeezed case")
        return
    }
    check(abs(squeezed.width - grid.width(spanning: 2)) < 0.001,
          "expected it to step down to 2 columns, got \(squeezed.width)")
}

suite("text stops at the picture's whole grid cell") {
    let grid = testGrid()
    // Three columns starting at column 2, snapped as a drag would leave it.
    let frame = CGRect(x: grid.origin.x + grid.pitch * 2, y: grid.origin.y + grid.lineHeight * 3,
                       width: grid.width(spanning: 3), height: 150)
    let cell = grid.exclusionCell(forImageFrame: frame)

    // Text on the left stops at the end of column 1; text on the right starts
    // at the start of column 5. Both are grid lines, which is the whole point:
    // every line beside the picture begins at the same x.
    check(abs(cell.minX - (grid.pitch * 2 - grid.gutter)) < 0.001,
          "the cell's left edge is \(cell.minX), not the end of column 1")
    check(abs(cell.maxX - grid.pitch * 5) < 0.001,
          "the cell's right edge is \(cell.maxX), not the start of column 5")

    // Whole lines down, so the text below resumes on a clean line.
    check(abs(cell.minY.truncatingRemainder(dividingBy: grid.lineHeight)) < 0.001,
          "the cell starts mid-line at \(cell.minY)")
    check(abs(cell.maxY.truncatingRemainder(dividingBy: grid.lineHeight)) < 0.001,
          "the cell ends mid-line at \(cell.maxY)")
    check(cell.minY <= grid.lineHeight * 3 && cell.maxY >= grid.lineHeight * 3 + 150,
          "the cell \(cell) does not cover the picture")

    // A picture at an arbitrary offset still produces a cell on the grid —
    // this is what stops a ragged left edge on the text beside it.
    let ragged = CGRect(x: grid.origin.x + 37, y: grid.origin.y + 19, width: 211, height: 97)
    let raggedCell = grid.exclusionCell(forImageFrame: ragged)
    check(abs((raggedCell.maxX / grid.pitch) - (raggedCell.maxX / grid.pitch).rounded()) < 0.001,
          "an off-grid picture gave an off-grid right edge at \(raggedCell.maxX)")
    check(raggedCell.maxX >= ragged.maxX - grid.origin.x, "the cell does not cover the picture's right edge")
    check(abs(raggedCell.maxY.truncatingRemainder(dividingBy: grid.lineHeight)) < 0.001,
          "an off-grid picture gave an off-grid bottom at \(raggedCell.maxY)")
}

suite("dragging a picture snaps it to the grid and reflows the text as it goes") {
    // The whole chain, driven by real mouse events: mouseDown on the picture,
    // a run of mouseDragged, mouseUp — through the snapping, out to the
    // exclusion paths, and into TextKit's layout.
    let frame = NSRect(x: 0, y: 0, width: 900, height: 620)
    let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
    let textView = FormattableTextView.makeWithTextKit1(frame: frame)
    textView.autoresizingMask = [.width]
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.minSize = .zero
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.font = EditorTypography.font()
    textView.textContainerInset = NSSize(width: 16, height: 40)
    textView.defaultParagraphStyle = EditorTypography.paragraphStyle
    textView.typingAttributes = EditorTypography.attributes(color: themeColor)

    let scrollView = NSScrollView(frame: frame)
    scrollView.documentView = textView
    window.contentView = scrollView
    window.contentView?.layoutSubtreeIfNeeded()
    hostWindows.append(window)

    textView.insertText(String(repeating: "the quick brown fox jumps over the lazy dog ", count: 40),
                        replacementRange: NSRange(location: 0, length: 0))

    guard let grid = textView.wrapGrid else {
        check(false, "no wrap grid")
        return
    }

    let picture = NSImage(size: NSSize(width: 300, height: 200))
    picture.lockFocus()
    NSColor.systemTeal.drawSwatch(in: NSRect(x: 0, y: 0, width: 300, height: 200))
    picture.unlockFocus()

    let start = NSRect(x: grid.origin.x, y: grid.origin.y, width: 300, height: 200)
    let view = FloatingImageView(imageId: UUID(), image: picture, imageFrame: start)
    textView.addSubview(view)

    // Wired the way RichTextEditor wires it: every step of the drag goes
    // straight to the text container.
    var liveFrames: [CGRect] = []
    var committed: CGRect?
    view.onFrameChanging = { _, moved in
        liveFrames.append(moved)
        textView.setImageExclusionFrames([moved])
    }
    view.onFrameChanged = { _, moved in committed = moved }
    textView.setImageExclusionFrames([start])

    func event(_ type: NSEvent.EventType, atViewPoint point: NSPoint) -> NSEvent? {
        NSEvent.mouseEvent(with: type, location: textView.convert(point, to: nil), modifierFlags: [],
                           timestamp: 0, windowNumber: window.windowNumber, context: nil,
                           eventNumber: 0, clickCount: 1, pressure: 1)
    }

    // Grab the middle of the picture — away from every corner — and walk it
    // across in small steps, the way a trackpad delivers a drag.
    let grab = NSPoint(x: start.midX, y: start.midY)
    guard let down = event(.leftMouseDown, atViewPoint: grab) else {
        check(false, "could not synthesise a mouse event")
        return
    }
    view.mouseDown(with: down)
    var dragEventsDelivered = 0
    for step in stride(from: 20, through: 320, by: 20) {
        if let dragged = event(.leftMouseDragged,
                               atViewPoint: NSPoint(x: grab.x + CGFloat(step), y: grab.y + CGFloat(step) / 2)) {
            view.mouseDragged(with: dragged)
            dragEventsDelivered += 1
        }
    }
    if let up = event(.leftMouseUp, atViewPoint: NSPoint(x: grab.x + 320, y: grab.y + 160)) {
        view.mouseUp(with: up)
    }

    // Live: the text was told about the move repeatedly, not once at the end.
    check(liveFrames.count > 1, "the drag reported \(liveFrames.count) intermediate positions, expected several")
    check(committed != nil, "the drag never committed a final position")
    check(committed == view.imageFrame, "the committed frame \(String(describing: committed)) is not where the picture ended up \(view.imageFrame)")
    check(view.imageFrame.origin != start.origin, "the picture never moved")
    check(view.imageFrame.size == start.size, "moving the picture resized it to \(view.imageFrame.size)")

    // Grid: every position it passed through sat on a column start and a line.
    for moved in liveFrames {
        let column = (moved.minX - grid.origin.x) / grid.pitch
        let line = (moved.minY - grid.origin.y) / grid.lineHeight
        check(abs(column - column.rounded()) < 0.001, "a drag step landed between columns at x=\(moved.minX)")
        check(abs(line - line.rounded()) < 0.001, "a drag step landed between lines at y=\(moved.minY)")
    }
    // Stepping, not sliding: the picture only reports a new position when it
    // changes slot, so a run of mouse events produces far fewer moves than
    // events. Free movement would give one move per event.
    check(liveFrames.count < dragEventsDelivered,
          "\(dragEventsDelivered) drag events produced \(liveFrames.count) moves; the picture is sliding, not stepping")
    check(Set(liveFrames.map { "\($0.minX),\($0.minY)" }).count == liveFrames.count,
          "the same slot was reported twice")

    // And the text really did reflow around where it ended up.
    guard let layoutManager = textView.layoutManager, let container = textView.textContainer else {
        check(false, "no TextKit 1 stack")
        return
    }
    layoutManager.ensureLayout(for: container)
    check(container.exclusionPaths.count == 1, "expected one exclusion path after the drag")

    let cell = grid.exclusionCell(forImageFrame: view.imageFrame)
    var leftEdges = Set<String>()
    layoutManager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs)) { _, used, _, _, _ in
        if used.midY > cell.minY && used.midY < cell.maxY {
            leftEdges.insert(String(format: "%.1f", used.minX))
        }
    }
    check(!leftEdges.isEmpty, "no text was laid out beside the picture after the drag")
    // The point of the grid: one straight edge, not a ragged one per line.
    check(leftEdges.count == 1,
          "the lines beside the picture start at \(leftEdges.count) different x positions: \(leftEdges.sorted())")
}

// MARK: - Report

print("\n\(checks - failures)/\(checks) checks passed")
if failures > 0 {
    print("\(failures) FAILED")
    exit(1)
}
print("all good")

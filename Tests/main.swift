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
    let textView = FormattableTextView(frame: frame)
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

// MARK: - Report

print("\n\(checks - failures)/\(checks) checks passed")
if failures > 0 {
    print("\(failures) FAILED")
    exit(1)
}
print("all good")

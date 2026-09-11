import AppKit

// The single source of truth for how note text looks.
//
// Every character in a note renders in PT Serif at one fixed size. Text that
// arrives from somewhere else — a paste or a drop from another app, a note
// written before this rule existed — carries its own font family, size and
// colour, which is what made pasted text show up smaller than what you typed
// around it. Anything entering the editor goes through `normalized(_:color:)`
// first, so there is exactly one size on screen and no way to change it.
enum EditorTypography {
    static let fontSize: CGFloat = 18
    static let lineSpacing: CGFloat = 8

    static func fontName(bold: Bool = false, italic: Bool = false) -> String {
        switch (bold, italic) {
        case (false, false): return "PTSerif-Regular"
        case (true, false): return "PTSerif-Bold"
        case (false, true): return "PTSerif-Italic"
        case (true, true): return "PTSerif-BoldItalic"
        }
    }

    static let bundledFontNames = [
        fontName(),
        fontName(bold: true),
        fontName(italic: true),
        fontName(bold: true, italic: true)
    ]

    /// PT Serif ships with the app rather than the system, so it has to be
    /// registered before any of it can be looked up by name.
    static func registerBundledFonts(in bundle: Bundle = .main) {
        for name in bundledFontNames {
            guard let url = bundle.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func font(bold: Bool = false, italic: Bool = false) -> NSFont {
        // The system font fallback only matters if the bundled TTFs failed to
        // register; it still has to honour the fixed size.
        return NSFont(name: fontName(bold: bold, italic: italic), size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize)
                .withTraits(bold: bold, italic: italic)
    }

    static var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        return style
    }

    static func attributes(bold: Bool = false, italic: Bool = false, color: NSColor) -> [NSAttributedString.Key: Any] {
        [
            .font: font(bold: bold, italic: italic),
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
    }

    // Rewrites `input` so it uses only this editor's font, size, colour and
    // paragraph style. Bold and italic survive — they're the one kind of
    // formatting the app itself offers, so copying bold text out of a note and
    // back in stays lossless — and every other inherited attribute (foreign
    // font family and size, highlight colours, kerning, baseline offsets) is
    // dropped rather than carried in.
    static func normalized(_ input: NSAttributedString, color: NSColor) -> NSAttributedString {
        let output = NSMutableAttributedString(string: input.string)
        let fullRange = NSRange(location: 0, length: output.length)
        guard output.length > 0 else { return output }

        output.beginEditing()
        // Seed every character, so runs that carry no font at all (plain text
        // from a terminal, say) still land on the editor's defaults.
        output.setAttributes(attributes(color: color), range: fullRange)
        input.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            guard let font = value as? NSFont else { return }
            let traits = font.fontDescriptor.symbolicTraits
            output.addAttribute(
                .font,
                value: self.font(bold: traits.contains(.bold), italic: traits.contains(.italic)),
                range: range
            )
        }
        output.endEditing()
        return output
    }
}

private extension NSFont {
    func withTraits(bold: Bool, italic: Bool) -> NSFont {
        var traits: NSFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        guard !traits.isEmpty else { return self }
        let descriptor = fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}

import SwiftUI
import AppKit

// NSTextView wrapper for rich text editing
struct RichTextEditor: NSViewRepresentable {
    @Binding var attributedText: NSAttributedString
    let noteId: UUID
    let textColor: NSColor
    let images: [NoteImage]
    let onTextChange: (NSAttributedString) -> Void
    let onImagePasted: (NSImage) -> Void
    let onImageFrameChanged: (UUID, CGRect) -> Void
    let onImageDeleted: (UUID) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let textView = FormattableTextView.makeWithTextKit1(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.onImagePasted = onImagePasted

        // The document view of a scroll view grows downward with the text and
        // tracks the clip view's width. Letting the autoresizing mask own the
        // height instead pins the text view to the visible area, which is what
        // used to swallow everything past the bottom of the window.
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)

        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.font = EditorTypography.font()
        textView.textColor = textColor
        textView.insertionPointColor = textColor
        textView.backgroundColor = .clear
        textView.drawsBackground = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 16, height: 40)

        textView.defaultParagraphStyle = EditorTypography.paragraphStyle
        textView.typingAttributes = EditorTypography.attributes(color: textColor)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? FormattableTextView else { return }
        let coordinator = context.coordinator
        // SwiftUI rebuilds this struct on every update; the coordinator
        // outlives them all, so it has to be pointed at the current one or it
        // keeps calling the closures captured when the editor first appeared.
        coordinator.parent = self

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
            // Notes written before the editor enforced one size can still hold
            // pasted-in fonts and sizes, so they're normalized on the way in
            // rather than left to render inconsistently forever.
            textView.textStorage?.setAttributedString(EditorTypography.normalized(attributedText, color: textColor))
            // Ranges are in UTF-16 units, which is what the text storage
            // counts in — `String.count` counts characters, and disagrees the
            // moment a note holds an emoji.
            if selectedRange.location <= (textView.textStorage?.length ?? 0) {
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
            textView.setImageExclusionFrames([])
        }

        // Fast path: most notes have no images, and this runs on every
        // SwiftUI update — skip the rest entirely rather than touching the
        // text container for nothing.
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
            let imageView = FloatingImageView(imageId: noteImage.id, image: image, imageFrame: frame)
            // Moving the image reflows the text as it goes; only the final
            // frame is written back to the store.
            imageView.onFrameChanging = { [weak textView] _, _ in
                guard let textView else { return }
                coordinator.applyExclusionFrames(to: textView)
            }
            imageView.onFrameChanged = { [weak textView] id, newFrame in
                if let textView { coordinator.applyExclusionFrames(to: textView, force: true) }
                onImageFrameChanged(id, newFrame)
            }
            imageView.onDelete = { id in
                onImageDeleted(id)
            }
            textView.addSubview(imageView)
            coordinator.imageViews[noteImage.id] = imageView
        }

        coordinator.applyExclusionFrames(to: textView)
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

        /// Hands the current picture rects to the text container so text wraps
        /// around them. Called on every step of a drag, so the text reflows
        /// under the image as it moves; the equality check is what keeps the
        /// ordinary SwiftUI updates (every keystroke, say) from paying for a
        /// full document relayout they don't need.
        func applyExclusionFrames(to textView: FormattableTextView, force: Bool = false) {
            let current = imageViews.mapValues { $0.imageFrame }
            guard force || current != lastExclusionFrames else { return }
            lastExclusionFrames = current
            textView.setImageExclusionFrames(Array(current.values))
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

                        // Driven by the store's own emptiness flag rather than
                        // by the note's text: typing deliberately no longer
                        // republishes the note on every keystroke.
                        if noteStore.isCurrentNoteEmpty {
                            Text(placeholderText)
                                .font(.custom("PTSerif-Regular", size: EditorTypography.fontSize))
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
            if noteStore.isCurrentNoteEmpty {
                placeholderText = placeholderOptions.randomElement() ?? ""
            }
        }
        .onChange(of: noteId) { _, _ in
            if noteStore.isCurrentNoteEmpty {
                placeholderText = placeholderOptions.randomElement() ?? ""
            }
        }
    }
}

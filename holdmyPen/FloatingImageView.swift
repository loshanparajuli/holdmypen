import AppKit

// A pasted image, floating over the text: drag the picture itself to move it,
// drag any of the four corner points to resize it (always keeping its aspect
// ratio), click the badge to remove it.
//
// The view is deliberately larger than the picture it shows. The corner points
// sit *on* the image's corners and the remove badge just outside them, so the
// chrome needs a ring of its own to live in — `chromePadding` wide all round.
// `imageFrame` is the picture itself, and that's what the rest of the app
// talks in: what gets stored, and what the text wraps around.
final class FloatingImageView: NSView {
    let imageId: UUID
    let image: NSImage

    /// Fired continuously while dragging, so the text reflows around the image
    /// as it moves rather than only once the mouse comes up.
    var onFrameChanging: ((UUID, CGRect) -> Void)?
    var onFrameChanged: ((UUID, CGRect) -> Void)?
    var onDelete: ((UUID) -> Void)?

    enum ResizeCorner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight

        /// The corner that stays put while this one is dragged.
        func anchor(in rect: CGRect) -> CGPoint {
            switch self {
            case .topLeft: return CGPoint(x: rect.maxX, y: rect.maxY)
            case .topRight: return CGPoint(x: rect.minX, y: rect.maxY)
            case .bottomLeft: return CGPoint(x: rect.maxX, y: rect.minY)
            case .bottomRight: return CGPoint(x: rect.minX, y: rect.minY)
            }
        }

        func position(in rect: CGRect) -> CGPoint {
            switch self {
            case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
            case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
            case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
            case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
            }
        }

        var growsLeftward: Bool { self == .topLeft || self == .bottomLeft }
        var growsUpward: Bool { self == .topLeft || self == .topRight }

        // Top-left and bottom-right lie on a "\" diagonal, the other two on "/".
        var isBackslashDiagonal: Bool { self == .topLeft || self == .bottomRight }
    }

    // Room around the picture for the corner points and the remove badge.
    static let chromePadding: CGFloat = 24
    static let minimumSide: CGFloat = 40

    private let cornerPointRadius: CGFloat = 4.5
    // Far more forgiving than what's drawn — a 9pt dot is not something anyone
    // can reliably hit with a trackpad.
    private let cornerGrabRadius: CGFloat = 13
    private let deleteBadgeRadius: CGFloat = 9

    private var dragStartLocation: NSPoint = .zero
    private var dragStartImageFrame: NSRect = .zero
    private var activeCorner: ResizeCorner?
    private var isDragging = false
    private var isShowingGrabCursor = false

    init(imageId: UUID, image: NSImage, imageFrame: NSRect) {
        self.imageId = imageId
        self.image = image
        super.init(frame: imageFrame.insetBy(dx: -Self.chromePadding, dy: -Self.chromePadding))
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    /// The picture, in the superview's coordinates — the rect the store holds
    /// and the text wraps around.
    var imageFrame: CGRect {
        get { frame.insetBy(dx: Self.chromePadding, dy: Self.chromePadding) }
        set { frame = newValue.insetBy(dx: -Self.chromePadding, dy: -Self.chromePadding) }
    }

    /// The picture in this view's own coordinates.
    private var imageRect: CGRect {
        bounds.insetBy(dx: Self.chromePadding, dy: Self.chromePadding)
    }

    private func grabRect(for corner: ResizeCorner) -> CGRect {
        let point = corner.position(in: imageRect)
        return CGRect(x: point.x - cornerGrabRadius, y: point.y - cornerGrabRadius,
                      width: cornerGrabRadius * 2, height: cornerGrabRadius * 2)
    }

    // Diagonally out from the top-right corner, clear of the corner point.
    private var deleteBadgeCenter: CGPoint {
        CGPoint(x: imageRect.maxX + 13, y: imageRect.minY - 13)
    }

    private var deleteBadgeRect: CGRect {
        CGRect(x: deleteBadgeCenter.x - deleteBadgeRadius, y: deleteBadgeCenter.y - deleteBadgeRadius,
               width: deleteBadgeRadius * 2, height: deleteBadgeRadius * 2)
    }

    private var deleteGrabRect: CGRect {
        deleteBadgeRect.insetBy(dx: -4, dy: -4)
    }

    // The chrome ring is mostly empty space. Letting it swallow clicks would
    // put a 24pt dead zone around every image where you couldn't place the
    // caret, so everything outside the picture and its controls falls through
    // to the text underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if imageRect.contains(local) || deleteGrabRect.contains(local) { return self }
        if ResizeCorner.allCases.contains(where: { grabRect(for: $0).contains(local) }) { return self }
        return nil
    }

    // The text view underneath is the first responder; without this the first
    // click on an image only activates the window and has to be repeated.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }

    // MARK: - Cursors

    // A double-headed arrow reads as "resize" the way a plain pointer doesn't;
    // AppKit has no public diagonal resize cursor, so this draws one. The same
    // path is used for the corner cursors in both diagonal directions.
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

    private static func diagonalResizeCursor(degrees: CGFloat) -> NSCursor {
        let size: CGFloat = 20
        let cursorImage = NSImage(size: NSSize(width: size, height: size))
        cursorImage.lockFocus()
        let center = NSPoint(x: size / 2, y: size / 2)
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.rotate(byDegrees: degrees)
        transform.translateX(by: -center.x, yBy: -center.y)
        transform.concat()

        let arrow = diagonalArrowPath(center: center, armLength: 7)
        // Dark underneath, light on top: legible over a light or dark image.
        NSColor.black.setStroke()
        arrow.stroke()
        NSColor.white.setStroke()
        arrow.lineWidth = 1
        arrow.stroke()

        cursorImage.unlockFocus()
        return NSCursor(image: cursorImage, hotSpot: center)
    }

    // The cursor image is drawn unflipped, so +45° points up-and-right ("/").
    private static let slashResizeCursor = diagonalResizeCursor(degrees: 45)
    private static let backslashResizeCursor = diagonalResizeCursor(degrees: -45)

    private static func cursor(for corner: ResizeCorner) -> NSCursor {
        corner.isBackslashDiagonal ? backslashResizeCursor : slashResizeCursor
    }

    /// The cursor this point should show, or nil where the view is
    /// click-through and the text underneath owns the cursor.
    private func cursor(at point: CGPoint) -> NSCursor? {
        // Corners first: their grab areas deliberately overlap the picture.
        if let corner = ResizeCorner.allCases.first(where: { grabRect(for: $0).contains(point) }) {
            return Self.cursor(for: corner)
        }
        if deleteGrabRect.contains(point) { return .pointingHand }
        // An open hand over the picture says "this can be moved".
        if imageRect.contains(point) { return isDragging ? .closedHand : .openHand }
        return nil
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(imageRect, cursor: isDragging ? .closedHand : .openHand)
        for corner in ResizeCorner.allCases {
            addCursorRect(grabRect(for: corner), cursor: Self.cursor(for: corner))
        }
        addCursorRect(deleteGrabRect, cursor: .pointingHand)
    }

    // Cursor rects alone are not enough here: the text view underneath keeps
    // its own, and reasserts the I-beam as the pointer moves. A tracking area
    // lets this view answer for the cursor directly while the pointer is over
    // it, which is what makes the hand and the two diagonal resize cursors
    // actually show up.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate],
            owner: self))
    }

    override func cursorUpdate(with event: NSEvent) {
        applyCursor(for: event)
    }

    override func mouseMoved(with event: NSEvent) {
        applyCursor(for: event)
    }

    override func mouseExited(with event: NSEvent) {
        // Hand the cursor back rather than leaving ours standing over the text.
        window?.invalidateCursorRects(for: self)
    }

    private func applyCursor(for event: NSEvent) {
        cursor(at: convert(event.locationInWindow, from: nil))?.set()
    }

    // MARK: - Drawing

    private static let deleteIcon: NSImage = {
        let base = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove image") ?? NSImage()
        let config = NSImage.SymbolConfiguration(paletteColors: [.white, .black.withAlphaComponent(0.65)])
        return base.withSymbolConfiguration(config) ?? base
    }()

    override func draw(_ dirtyRect: NSRect) {
        let picture = imageRect
        // Scaling a multi-megapixel original on every drag event is the
        // difference between a smooth drag and a stuttering one; the
        // interpolation only needs to be good once the drag settles.
        NSGraphicsContext.current?.imageInterpolation = isDragging ? .low : .high
        image.draw(in: picture)

        drawDottedBorder(around: picture)
        for corner in ResizeCorner.allCases {
            drawCornerPoint(at: corner.position(in: picture))
        }
        Self.deleteIcon.draw(in: deleteBadgeRect)
    }

    // Two dashed passes offset from each other, so the border stays visible
    // whether the image behind it is light, dark or busy.
    private func drawDottedBorder(around picture: CGRect) {
        let border = NSBezierPath(rect: picture.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        border.setLineDash([4, 4], count: 2, phase: 0)
        NSColor.black.withAlphaComponent(0.7).setStroke()
        border.stroke()
        border.setLineDash([4, 4], count: 2, phase: 4)
        NSColor.white.withAlphaComponent(0.9).setStroke()
        border.stroke()
    }

    private func drawCornerPoint(at point: CGPoint) {
        let dot = CGRect(x: point.x - cornerPointRadius, y: point.y - cornerPointRadius,
                         width: cornerPointRadius * 2, height: cornerPointRadius * 2)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: dot).fill()
        NSColor.black.withAlphaComponent(0.7).setStroke()
        let ring = NSBezierPath(ovalIn: dot.insetBy(dx: 0.5, dy: 0.5))
        ring.lineWidth = 1
        ring.stroke()
    }

    // MARK: - Resizing

    /// Where a corner drag lands the picture: the opposite corner stays put,
    /// the aspect ratio is kept, and the result stays inside `bounds`.
    static func resizedImageFrame(original: CGRect,
                                  corner: ResizeCorner,
                                  dragTo point: CGPoint,
                                  within bounds: CGRect) -> CGRect {
        guard original.width > 0, original.height > 0 else { return original }
        let aspectRatio = original.width / original.height
        let anchor = corner.anchor(in: original)

        var width = abs(point.x - anchor.x)
        var height = abs(point.y - anchor.y)
        // Whichever axis the pointer has moved further along drives the size;
        // the other is derived, which is what locks the aspect ratio.
        if width / aspectRatio >= height {
            height = width / aspectRatio
        } else {
            width = height * aspectRatio
        }

        // Only as far as the edge the corner is heading towards.
        let availableWidth = corner.growsLeftward ? anchor.x - bounds.minX : bounds.maxX - anchor.x
        let availableHeight = corner.growsUpward ? anchor.y - bounds.minY : bounds.maxY - anchor.y
        if width > 0, height > 0 {
            let fit = min(1, max(0, availableWidth) / width, max(0, availableHeight) / height)
            width *= fit
            height *= fit
        }

        if width < minimumSide {
            width = minimumSide
            height = width / aspectRatio
        }
        if height < minimumSide {
            height = minimumSide
            width = height * aspectRatio
        }

        return CGRect(x: corner.growsLeftward ? anchor.x - width : anchor.x,
                      y: corner.growsUpward ? anchor.y - height : anchor.y,
                      width: width,
                      height: height)
    }

    /// Where a move drag lands the picture, kept inside `bounds`.
    static func movedImageFrame(original: CGRect, by offset: CGSize, within bounds: CGRect) -> CGRect {
        var moved = original.offsetBy(dx: offset.width, dy: offset.height)
        moved.origin.x = max(bounds.minX, min(moved.origin.x, bounds.maxX - moved.width))
        moved.origin.y = max(bounds.minY, min(moved.origin.y, bounds.maxY - moved.height))
        return moved
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if deleteGrabRect.contains(local) {
            onDelete?(imageId)
            return
        }
        guard let superview = superview else { return }
        activeCorner = ResizeCorner.allCases.first { grabRect(for: $0).contains(local) }
        isDragging = true
        dragStartLocation = superview.convert(event.locationInWindow, from: nil)
        dragStartImageFrame = imageFrame
        // AppKit holds whatever cursor is set when a drag begins, so the grab
        // has to be shown here rather than from a cursor rect.
        if activeCorner == nil {
            NSCursor.closedHand.push()
            isShowingGrabCursor = true
        }
        window?.invalidateCursorRects(for: self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let superview = superview else { return }
        let current = superview.convert(event.locationInWindow, from: nil)

        let updated: CGRect
        if let corner = activeCorner {
            updated = Self.resizedImageFrame(original: dragStartImageFrame,
                                             corner: corner,
                                             dragTo: current,
                                             within: superview.bounds)
        } else {
            let offset = CGSize(width: current.x - dragStartLocation.x,
                                height: current.y - dragStartLocation.y)
            updated = Self.movedImageFrame(original: dragStartImageFrame,
                                           by: offset,
                                           within: superview.bounds)
        }

        guard updated != imageFrame else { return }
        imageFrame = updated
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        // Every step of the drag, so the text keeps up with the image rather
        // than snapping into place once the mouse is released.
        onFrameChanging?(imageId, updated)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        activeCorner = nil
        if isShowingGrabCursor {
            NSCursor.pop()
            isShowingGrabCursor = false
        }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        onFrameChanged?(imageId, imageFrame)
    }
}

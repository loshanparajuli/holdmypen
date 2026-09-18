import Foundation
import CoreGraphics

// The layout grid a floating image sits on.
//
// A newspaper never lets a picture land wherever it was dropped. It occupies a
// whole number of columns, its top lines up with a line of type, and the text
// beside it starts at a column edge rather than wherever the picture happens to
// end. That alignment is most of what makes a wrap read as deliberate rather
// than as text shoved out of the way — a picture at an arbitrary offset leaves
// every line beside it starting at its own ragged x, and the eye reads that as
// broken even when the wrap itself is working.
//
// Horizontal positions here are columns; vertical ones are lines of type.
struct WrapGrid: Equatable {
    /// Where the text container's (0, 0) sits in the text view's coordinates.
    let origin: CGPoint
    /// One column plus the gutter after it: the distance from a column's start
    /// to the next column's start.
    let pitch: CGFloat
    /// Clear space between a picture and the text beside it.
    let gutter: CGFloat
    let columnCount: Int
    /// One line of type, including the paragraph's line spacing.
    let lineHeight: CGFloat

    static let defaultColumnCount = 12
    static let defaultGutter: CGFloat = 16

    /// Nil when the column is too narrow to carry a grid at all.
    init?(containerWidth: CGFloat,
          origin: CGPoint,
          lineHeight: CGFloat,
          columnCount: Int = WrapGrid.defaultColumnCount,
          gutter: CGFloat = WrapGrid.defaultGutter) {
        guard containerWidth > 0, lineHeight > 0, columnCount > 0 else { return nil }
        let pitch = (containerWidth + gutter) / CGFloat(columnCount)
        guard pitch > gutter else { return nil }
        self.origin = origin
        self.pitch = pitch
        self.gutter = gutter
        self.columnCount = columnCount
        self.lineHeight = lineHeight
    }

    var containerWidth: CGFloat { pitch * CGFloat(columnCount) - gutter }

    /// The width of a picture spanning `columns` columns — the columns plus the
    /// gutters between them, but not the gutter after the last one.
    func width(spanning columns: Int) -> CGFloat {
        CGFloat(columns) * pitch - gutter
    }

    /// How many columns a loose width is closest to.
    func columnSpan(forWidth width: CGFloat) -> Int {
        min(columnCount, max(1, Int(((width + gutter) / pitch).rounded())))
    }

    // MARK: - Snapping

    /// A picture's size rounded to a whole number of columns, keeping its
    /// aspect ratio and staying inside the space the drag has to work with.
    /// Returns nil if not even one column will fit, leaving the caller to fall
    /// back to a loose size.
    func snappedSize(for size: CGSize,
                     fittingWidth availableWidth: CGFloat,
                     height availableHeight: CGFloat,
                     minimumSide: CGFloat) -> CGSize? {
        guard size.width > 0, size.height > 0 else { return nil }
        let aspectRatio = size.width / size.height

        var span = columnSpan(forWidth: size.width)
        while span > 1 {
            let candidate = width(spanning: span)
            if candidate <= availableWidth
                && candidate / aspectRatio <= availableHeight
                && candidate >= minimumSide {
                break
            }
            span -= 1
        }

        let snapped = width(spanning: span)
        guard snapped >= minimumSide, snapped <= availableWidth,
              snapped / aspectRatio <= availableHeight else { return nil }
        return CGSize(width: snapped, height: snapped / aspectRatio)
    }

    /// A picture's top-left corner moved onto the nearest column start and line
    /// of type. `frame` and the result are both in the text view's coordinates.
    func snappedOrigin(for frame: CGRect, within bounds: CGRect) -> CGPoint {
        let span = columnSpan(forWidth: frame.width)
        let lastStart = max(0, columnCount - span)
        let column = min(max(0, Int(((frame.minX - origin.x) / pitch).rounded())), lastStart)

        // Lines only, and never above the first one.
        var line = max(0, ((frame.minY - origin.y) / lineHeight).rounded())
        let lowestTop = bounds.maxY - origin.y - frame.height
        if lowestTop > 0 {
            line = min(line, (lowestTop / lineHeight).rounded(.down))
        } else {
            line = 0
        }

        return CGPoint(x: origin.x + CGFloat(column) * pitch,
                       y: origin.y + line * lineHeight)
    }

    // MARK: - Exclusion

    /// The grid cell a picture occupies, in the text container's coordinates:
    /// whole columns across, whole lines down.
    ///
    /// Text stops at the cell rather than at the picture, which is what leaves
    /// the column of text beside it on one straight edge, and what lets the
    /// text below it resume on a clean line instead of part-way through one.
    func exclusionCell(forImageFrame frame: CGRect) -> CGRect {
        let left = frame.minX - origin.x
        let right = frame.maxX - origin.x
        let top = frame.minY - origin.y
        let bottom = frame.maxY - origin.y

        let firstColumn = max(0, Int((left / pitch).rounded(.down)))
        let lastColumn = max(firstColumn, Int(((right + gutter) / pitch).rounded(.up)) - 1)

        // Out to the gutter before the picture's first column, and on to the
        // start of the first column after it.
        let cellLeft = CGFloat(firstColumn) * pitch - gutter
        let cellRight = CGFloat(lastColumn + 1) * pitch

        let cellTop = (top / lineHeight).rounded(.down) * lineHeight
        let cellBottom = (bottom / lineHeight).rounded(.up) * lineHeight

        return CGRect(x: cellLeft, y: cellTop, width: cellRight - cellLeft, height: cellBottom - cellTop)
    }
}

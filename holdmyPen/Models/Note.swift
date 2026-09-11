import Foundation
import AppKit

struct NoteImage: Identifiable, Codable, Equatable {
    let id: UUID
    var imageData: Data
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(id: UUID = UUID(), imageData: Data, x: Double, y: Double, width: Double, height: Double) {
        self.id = id
        self.imageData = imageData
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

struct Note: Identifiable, Codable, Equatable {
    let id: UUID
    var content: String
    var attributedContentData: Data?
    var createdAt: Date
    var modifiedAt: Date
    var images: [NoteImage]

    // Notes used to carry their own font and size. The editor now renders
    // every note at EditorTypography's single fixed size, so these are no
    // longer read — they're still written so a note saved by this build stays
    // readable if someone rolls back to an earlier one.
    private let legacyFontName = "System"
    private let legacyFontSize = 18.0

    init(
        id: UUID = UUID(),
        content: String = "",
        attributedContentData: Data? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        images: [NoteImage] = []
    ) {
        self.id = id
        self.content = content
        self.attributedContentData = attributedContentData
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.images = images
    }

    private enum CodingKeys: String, CodingKey {
        case id, content, attributedContentData, createdAt, modifiedAt, images
        case legacyFontName = "fontName"
        case legacyFontSize = "fontSize"
    }

    // Custom decoding so notes saved before `images` existed still load
    // (a missing key would otherwise fail the whole decode).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        attributedContentData = try container.decodeIfPresent(Data.self, forKey: .attributedContentData)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
        images = try container.decodeIfPresent([NoteImage].self, forKey: .images) ?? []
    }
    
    var attributedContent: NSAttributedString {
        get {
            if let data = attributedContentData,
               let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
               ) {
                return attributed
            }
            // Fallback to plain text with default attributes
            return NSAttributedString(
                string: content,
                attributes: [
                    .font: EditorTypography.font(),
                    .paragraphStyle: EditorTypography.paragraphStyle
                ]
            )
        }
        set {
            // Store as RTF data
            let range = NSRange(location: 0, length: newValue.length)
            if let rtfData = try? newValue.data(
                from: range,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            ) {
                self.attributedContentData = rtfData
            }
            // Also update plain text for preview and word count
            self.content = newValue.string
        }
    }
    
    var wordCount: Int {
        let words = content.split { $0.isWhitespace || $0.isNewline }.filter { !$0.isEmpty }
        return words.count
    }
    
    var preview: String {
        let firstLine = content.split(separator: "\n").first ?? ""
        return String(firstLine.prefix(50))
    }
    
    var timeAgo: String {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .day], from: modifiedAt, to: now)
        
        if let days = components.day, days > 0 {
            if days == 1 {
                return "Yesterday"
            } else if days < 7 {
                return "\(days) days ago"
            } else {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                return formatter.string(from: modifiedAt)
            }
        } else if let hours = components.hour {
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            return "Just now"
        }
    }
    
    mutating func updateContent(_ newContent: String) {
        self.content = newContent
        self.modifiedAt = Date()
    }
    
    mutating func updateAttributedContent(_ newAttributedContent: NSAttributedString) {
        self.attributedContent = newAttributedContent
        self.modifiedAt = Date()
    }
}


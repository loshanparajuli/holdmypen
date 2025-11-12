import Foundation
import AppKit

struct Note: Identifiable, Codable, Equatable {
    let id: UUID
    var content: String
    var attributedContentData: Data?
    var createdAt: Date
    var modifiedAt: Date
    var fontName: String
    var fontSize: Double
    
    init(
        id: UUID = UUID(),
        content: String = "",
        attributedContentData: Data? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        fontName: String = "System",
        fontSize: Double = 18
    ) {
        self.id = id
        self.content = content
        self.attributedContentData = attributedContentData
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.fontName = fontName
        self.fontSize = fontSize
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
            let font = NSFont(name: "PTSerif-Regular", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 8
            
            return NSAttributedString(
                string: content,
                attributes: [
                    .font: font,
                    .paragraphStyle: paragraphStyle
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


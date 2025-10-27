import Foundation

struct Note: Identifiable, Codable, Equatable {
    let id: UUID
    var content: String
    var createdAt: Date
    var modifiedAt: Date
    var fontName: String
    var fontSize: Double
    
    init(
        id: UUID = UUID(),
        content: String = "",
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        fontName: String = "System",
        fontSize: Double = 18
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.fontName = fontName
        self.fontSize = fontSize
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
}


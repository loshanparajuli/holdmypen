import SwiftUI

struct HistorySidebarView: View {
    let notes: [Note]
    let currentNoteId: UUID?
    let onSelectNote: (UUID) -> Void
    let onDeleteNote: (UUID) -> Void
    let backgroundColor: Color
    let textColor: Color
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Notes")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(textColor)
                
                Spacer()
                
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundColor(textColor.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            Divider()
            
            // Notes list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(notes) { note in
                        NoteListItemView(
                            note: note,
                            isSelected: note.id == currentNoteId,
                            textColor: textColor,
                            onSelect: {
                                onSelectNote(note.id)
                            },
                            onDelete: {
                                onDeleteNote(note.id)
                            }
                        )
                    }
                }
            }
            
            Spacer()
        }
        .frame(width: 280)
        .background(backgroundColor)
    }
}

struct NoteListItemView: View {
    let note: Note
    let isSelected: Bool
    let textColor: Color
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if !note.preview.isEmpty {
                        Text(note.preview)
                            .font(.system(size: 13))
                            .foregroundColor(textColor)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text("New note")
                            .font(.system(size: 13))
                            .foregroundColor(textColor.opacity(0.5))
                    }
                    
                    HStack(spacing: 4) {
                        Text(note.timeAgo)
                            .font(.system(size: 11))
                            .foregroundColor(textColor.opacity(0.5))
                        
                        if note.wordCount > 0 {
                            Text("•")
                                .foregroundColor(textColor.opacity(0.5))
                            Text("\(note.wordCount) words")
                                .font(.system(size: 11))
                                .foregroundColor(textColor.opacity(0.5))
                        }
                    }
                }
                
                Spacer()
                
                if isHovered {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(textColor.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? textColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}


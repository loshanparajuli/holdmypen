import Foundation
import SwiftUI
import AppKit

@MainActor
class NoteStore: ObservableObject {
    @Published var notes: [Note] = []
    @Published var currentNoteId: UUID?
    
    private let notesKey = "holdmyPen.notes"
    private let currentNoteIdKey = "holdmyPen.currentNoteId"
    private var saveTimer: Timer?

    // Live rich-text per note, kept in memory during editing so we don't
    // RTF-encode/decode the whole document on every keystroke. Only flushed
    // to `Note.attributedContentData` (RTF) when we actually persist.
    private var attributedCache: [UUID: NSAttributedString] = [:]
    private var dirtyNoteIds: Set<UUID> = []
    
    init() {
        loadNotes()
        if notes.isEmpty {
            createNewNote()
        } else if let currentId = UserDefaults.standard.string(forKey: currentNoteIdKey),
                  let uuid = UUID(uuidString: currentId) {
            currentNoteId = uuid
        } else {
            currentNoteId = notes.first?.id
        }
    }
    
    func getCurrentNote() -> Note? {
        guard let id = currentNoteId else { return nil }
        return notes.first { $0.id == id }
    }

    // Returns the live in-memory attributed content for a note, decoding
    // from stored RTF only once (on first access after load).
    func attributedContent(for id: UUID) -> NSAttributedString {
        if let cached = attributedCache[id] {
            return cached
        }
        guard let note = notes.first(where: { $0.id == id }) else {
            return NSAttributedString(string: "")
        }
        let decoded = note.attributedContent
        attributedCache[id] = decoded
        return decoded
    }

    func updateCurrentNote(content: String) {
        guard let index = notes.firstIndex(where: { $0.id == currentNoteId }) else { return }
        notes[index].updateContent(content)
        debouncedSave()
    }

    func updateCurrentNoteAttributed(attributedContent: NSAttributedString) {
        guard let id = currentNoteId,
              let index = notes.firstIndex(where: { $0.id == id }) else { return }
        // Cheap: update the plain-text mirror (for previews/word count) and
        // stash the rich text in memory. No RTF encoding on the typing path.
        attributedCache[id] = attributedContent
        notes[index].content = attributedContent.string
        notes[index].modifiedAt = Date()
        dirtyNoteIds.insert(id)
        debouncedSave()
    }
    
    private func debouncedSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.saveNotes()
            }
        }
    }
    
    func createNewNote() {
        let newNote = Note()
        notes.insert(newNote, at: 0)
        currentNoteId = newNote.id
        saveNotes()
    }
    
    func switchToNote(_ id: UUID) {
        currentNoteId = id
        UserDefaults.standard.set(id.uuidString, forKey: currentNoteIdKey)
    }
    
    func deleteNote(_ id: UUID) {
        notes.removeAll { $0.id == id }
        attributedCache.removeValue(forKey: id)
        dirtyNoteIds.remove(id)
        if currentNoteId == id {
            currentNoteId = notes.first?.id
        }
        saveNotes()
    }
    
    func updateNoteFont(_ id: UUID, fontName: String, fontSize: Double) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].fontName = fontName
        notes[index].fontSize = fontSize
        debouncedSave()
    }

    // Adds a pasted image to a note at a small cascading default position/size;
    // the user drags/resizes it afterward.
    func addImage(_ image: NSImage, to noteId: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == noteId }) else { return }
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }

        let maxDimension: Double = 240
        let sourceWidth = max(image.size.width, 1)
        let aspectRatio = image.size.height / sourceWidth
        let width = min(Double(sourceWidth), maxDimension)
        let height = width * Double(aspectRatio)

        let cascade = Double(notes[index].images.count % 6) * 20
        let newImage = NoteImage(imageData: pngData, x: 24 + cascade, y: 24 + cascade, width: width, height: height)
        notes[index].images.append(newImage)
        saveNotes()
    }

    func updateImageFrame(_ imageId: UUID, in noteId: UUID, x: Double, y: Double, width: Double, height: Double) {
        guard let index = notes.firstIndex(where: { $0.id == noteId }),
              let imageIndex = notes[index].images.firstIndex(where: { $0.id == imageId }) else { return }
        notes[index].images[imageIndex].x = x
        notes[index].images[imageIndex].y = y
        notes[index].images[imageIndex].width = width
        notes[index].images[imageIndex].height = height
        debouncedSave()
    }

    func removeImage(_ imageId: UUID, from noteId: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == noteId }) else { return }
        notes[index].images.removeAll { $0.id == imageId }
        saveNotes()
    }
    
    private func saveNotes() {
        // RTF-encode only the notes that actually changed since the last
        // save, and only once here (not on every keystroke).
        for id in dirtyNoteIds {
            guard let index = notes.firstIndex(where: { $0.id == id }),
                  let cached = attributedCache[id] else { continue }
            notes[index].updateAttributedContent(cached)
        }
        dirtyNoteIds.removeAll()

        if let encoded = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(encoded, forKey: notesKey)
        }
        if let id = currentNoteId {
            UserDefaults.standard.set(id.uuidString, forKey: currentNoteIdKey)
        }
    }
    
    private func loadNotes() {
        if let data = UserDefaults.standard.data(forKey: notesKey),
           let decoded = try? JSONDecoder().decode([Note].self, from: data) {
            notes = decoded
        }
    }
}


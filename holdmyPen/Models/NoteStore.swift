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
    
    func updateCurrentNote(content: String) {
        guard let index = notes.firstIndex(where: { $0.id == currentNoteId }) else { return }
        notes[index].updateContent(content)
        debouncedSave()
    }
    
    func updateCurrentNoteAttributed(attributedContent: NSAttributedString) {
        guard let index = notes.firstIndex(where: { $0.id == currentNoteId }) else { return }
        notes[index].updateAttributedContent(attributedContent)
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
    
    private func saveNotes() {
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


import Foundation
import SwiftUI
import AppKit

@MainActor
class NoteStore: ObservableObject {
    @Published var notes: [Note] = []
    @Published var currentNoteId: UUID?

    /// Whether the note being edited has no text yet — the one thing about the
    /// live document the UI needs between saves (it drives the placeholder).
    /// Published separately so a keystroke doesn't have to republish `notes`.
    @Published private(set) var isCurrentNoteEmpty: Bool = true

    private let notesKey = "holdmyPen.notes"
    private let currentNoteIdKey = "holdmyPen.currentNoteId"
    // Injectable so the headless tests can run against a throwaway suite
    // instead of the real app's saved notes.
    private let defaults: SendableDefaults
    private var saveTimer: Timer?

    // Live rich-text per note, kept in memory during editing so we don't
    // RTF-encode/decode the whole document on every keystroke. Only flushed
    // to `Note.attributedContentData` (RTF) when we actually persist.
    private var attributedCache: [UUID: NSAttributedString] = [:]
    private var dirtyNoteIds: Set<UUID> = []

    // JSON-encoding every note — image blobs included — is far too slow to sit
    // between keystrokes on the main thread.
    private let saveQueue = DispatchQueue(label: "com.holdmypen.notestore.save", qos: .utility)

    init(defaults: UserDefaults = .standard) {
        self.defaults = SendableDefaults(defaults)
        loadNotes()
        if notes.isEmpty {
            createNewNote()
        } else if let currentId = defaults.string(forKey: currentNoteIdKey),
                  let uuid = UUID(uuidString: currentId) {
            currentNoteId = uuid
        } else {
            currentNoteId = notes.first?.id
        }
        refreshEmptiness()
        observeAppLifecycle()
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

    func updateCurrentNoteAttributed(attributedContent: NSAttributedString) {
        guard let id = currentNoteId else { return }
        // Typing must not write into `notes`. It's @Published, so every
        // keystroke would rebuild the SwiftUI tree — and comparing a `Note`
        // means byte-comparing its RTF blob and every image it holds. The live
        // document lives here instead and is folded back in when we persist.
        attributedCache[id] = attributedContent
        dirtyNoteIds.insert(id)
        setEmptiness(attributedContent.length == 0)
        debouncedSave()
    }

    /// Folds the live editing cache back into `notes`. Anything that reads a
    /// note's text — persisting, the history sidebar's previews and word
    /// counts — has to go through here first, or it reads text as of the last
    /// save rather than as of the last keystroke.
    func flushPendingEdits() {
        guard !dirtyNoteIds.isEmpty else { return }
        for id in dirtyNoteIds {
            guard let index = notes.firstIndex(where: { $0.id == id }),
                  let cached = attributedCache[id] else { continue }
            notes[index].updateAttributedContent(cached)
        }
        dirtyNoteIds.removeAll()
    }

    private func setEmptiness(_ isEmpty: Bool) {
        // Only publishes on the keystroke that actually empties or fills the
        // note, not on the thousands in between.
        if isCurrentNoteEmpty != isEmpty {
            isCurrentNoteEmpty = isEmpty
        }
    }

    private func refreshEmptiness() {
        guard let id = currentNoteId else {
            isCurrentNoteEmpty = true
            return
        }
        if let cached = attributedCache[id] {
            setEmptiness(cached.length == 0)
        } else {
            setEmptiness(notes.first(where: { $0.id == id })?.content.isEmpty ?? true)
        }
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
        flushPendingEdits()
        let newNote = Note()
        notes.insert(newNote, at: 0)
        currentNoteId = newNote.id
        isCurrentNoteEmpty = true
        saveNotes()
    }

    func switchToNote(_ id: UUID) {
        flushPendingEdits()
        currentNoteId = id
        refreshEmptiness()
        defaults.store.set(id.uuidString, forKey: currentNoteIdKey)
    }

    func deleteNote(_ id: UUID) {
        dirtyNoteIds.remove(id)
        flushPendingEdits()
        notes.removeAll { $0.id == id }
        attributedCache.removeValue(forKey: id)
        if currentNoteId == id {
            currentNoteId = notes.first?.id
            refreshEmptiness()
        }
        saveNotes()
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

    // Quitting or switching away shouldn't cost the last couple of seconds of
    // writing that the debounce is still holding.
    private func observeAppLifecycle() {
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNotes() }
        }
        center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveAndWait() }
        }
    }

    /// Saves and blocks until the write has landed — only for termination,
    /// where the process won't be around for the background write to finish.
    func saveAndWait() {
        saveNotes()
        saveQueue.sync {}
    }

    private func saveNotes() {
        saveTimer?.invalidate()
        saveTimer = nil
        // RTF-encode only the notes that actually changed since the last save.
        flushPendingEdits()

        let snapshot = notes
        let currentId = currentNoteId?.uuidString
        let defaults = self.defaults
        let notesKey = self.notesKey
        let currentNoteIdKey = self.currentNoteIdKey
        saveQueue.async {
            if let encoded = try? JSONEncoder().encode(snapshot) {
                defaults.store.set(encoded, forKey: notesKey)
            }
            if let currentId {
                defaults.store.set(currentId, forKey: currentNoteIdKey)
            }
        }
    }

    private func loadNotes() {
        if let data = defaults.store.data(forKey: notesKey),
           let decoded = try? JSONDecoder().decode([Note].self, from: data) {
            notes = decoded
        }
    }
}

// UserDefaults is documented as thread-safe, which is what lets the background
// save write through it; the type just isn't marked Sendable, so this says so
// explicitly rather than leaving a warning at every capture.
private struct SendableDefaults: @unchecked Sendable {
    let store: UserDefaults
    init(_ store: UserDefaults) { self.store = store }
}

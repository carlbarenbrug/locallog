import SwiftUI
import AppKit

final class StorageLocationStore: ObservableObject {
    static let folderName = "Local Log"

    private enum DefaultsKey {
        static let customDirectoryBookmark = "storageLocation.customDirectoryBookmark"
    }

    enum StorageLocationError: LocalizedError {
        case destinationAlreadyContainsFiles(URL)

        var errorDescription: String? {
            switch self {
            case .destinationAlreadyContainsFiles(let url):
                return "The folder at \(url.path) already contains files. Choose an empty location or move your archive somewhere else first."
            }
        }
    }

    @Published private(set) var directory: URL

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let defaultDirectory: URL
    private var securityScopedDirectory: URL?

    init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.defaultDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Self.folderName, isDirectory: true)

        self.directory = Self.resolvePersistedDirectory(from: defaults, fallback: defaultDirectory)
        beginAccessIfNeeded(for: directory)
        ensureDirectoryExists(at: directory)
    }

    deinit {
        endAccessIfNeeded()
    }

    var defaultDirectoryPath: String {
        defaultDirectory.path
    }

    var isUsingDefaultLocation: Bool {
        directory.standardizedFileURL == defaultDirectory.standardizedFileURL
    }

    func chooseDirectory(using parentDirectory: URL, moveExistingFiles: Bool) throws {
        let newDirectory = normalizedParentDirectory(parentDirectory)
            .appendingPathComponent(Self.folderName, isDirectory: true)
            .standardizedFileURL
        try updateDirectory(to: newDirectory, moveExistingFiles: moveExistingFiles)
    }

    func resetToDefaultDirectory(moveExistingFiles: Bool) throws {
        try updateDirectory(to: defaultDirectory, moveExistingFiles: moveExistingFiles)
    }

    func revealInFinder() {
        ensureDirectoryExists(at: directory)
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    private func updateDirectory(to newDirectory: URL, moveExistingFiles: Bool) throws {
        let currentDirectory = directory.standardizedFileURL
        let destinationDirectory = newDirectory.standardizedFileURL

        guard destinationDirectory != currentDirectory else {
            ensureDirectoryExists(at: destinationDirectory)
            persist(directory: destinationDirectory)
            directory = destinationDirectory
            return
        }

        if moveExistingFiles {
            try moveContentsIfNeeded(from: currentDirectory, to: destinationDirectory)
        } else {
            ensureDirectoryExists(at: destinationDirectory)
        }

        endAccessIfNeeded()
        persist(directory: destinationDirectory)
        beginAccessIfNeeded(for: destinationDirectory)
        directory = destinationDirectory
    }

    private func moveContentsIfNeeded(from currentDirectory: URL, to destinationDirectory: URL) throws {
        guard fileManager.fileExists(atPath: currentDirectory.path) else {
            ensureDirectoryExists(at: destinationDirectory)
            return
        }

        if fileManager.fileExists(atPath: destinationDirectory.path) {
            let existingContents = try fileManager.contentsOfDirectory(at: destinationDirectory, includingPropertiesForKeys: nil)
            guard existingContents.isEmpty else {
                throw StorageLocationError.destinationAlreadyContainsFiles(destinationDirectory)
            }
            try fileManager.removeItem(at: destinationDirectory)
        }

        ensureDirectoryExists(at: destinationDirectory.deletingLastPathComponent())
        try fileManager.moveItem(at: currentDirectory, to: destinationDirectory)
    }

    private func persist(directory: URL) {
        guard directory.standardizedFileURL != defaultDirectory.standardizedFileURL else {
            defaults.removeObject(forKey: DefaultsKey.customDirectoryBookmark)
            return
        }

        let bookmarkData = try? directory.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(bookmarkData, forKey: DefaultsKey.customDirectoryBookmark)
    }

    private func ensureDirectoryExists(at url: URL) {
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func normalizedParentDirectory(_ url: URL) -> URL {
        let standardizedURL = url.standardizedFileURL
        guard standardizedURL.lastPathComponent == Self.folderName else {
            return standardizedURL
        }
        return standardizedURL.deletingLastPathComponent()
    }

    private func beginAccessIfNeeded(for url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        securityScopedDirectory = url
    }

    private func endAccessIfNeeded() {
        securityScopedDirectory?.stopAccessingSecurityScopedResource()
        securityScopedDirectory = nil
    }

    private static func resolvePersistedDirectory(from defaults: UserDefaults, fallback: URL) -> URL {
        guard let bookmarkData = defaults.data(forKey: DefaultsKey.customDirectoryBookmark) else {
            return fallback.standardizedFileURL
        }

        var isStale = false
        guard let resolvedURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            defaults.removeObject(forKey: DefaultsKey.customDirectoryBookmark)
            return fallback.standardizedFileURL
        }

        if isStale,
           let refreshedBookmark = try? resolvedURL.bookmarkData(
               options: [.withSecurityScope],
               includingResourceValuesForKeys: nil,
               relativeTo: nil
           ) {
            defaults.set(refreshedBookmark, forKey: DefaultsKey.customDirectoryBookmark)
        }

        return resolvedURL.standardizedFileURL
    }
}

struct StorageSettingsView: View {
    @EnvironmentObject private var storageLocation: StorageLocationStore

    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Journal Folder")
                    .font(.title3.weight(.semibold))

                Text("By default, Local Log stores everything in `~/Documents/Local Log`. You can point it somewhere else and optionally move the current archive.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Current Location")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(storageLocation.directory.path)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button("Change Location...") {
                        chooseLocation()
                    }

                    Button("Open in Finder") {
                        storageLocation.revealInFinder()
                    }

                    Button("Reset to Default") {
                        resetLocation()
                    }
                    .disabled(storageLocation.isUsingDefaultLocation)
                }
            }
        }
        .padding(24)
        .frame(width: 500, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .alert("Couldn’t Change Folder", isPresented: $showingError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "Please try a different location.")
        })
    }

    private func chooseLocation() {
        let panel = NSOpenPanel()
        panel.title = "Choose Where Local Log Lives"
        panel.message = "Select the folder that should contain the Local Log archive."
        panel.prompt = "Use Location"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = storageLocation.directory.deletingLastPathComponent()

        guard panel.runModal() == .OK, let selectedParentDirectory = panel.url else { return }
        guard let moveExistingFiles = migrationChoice(for: selectedParentDirectory) else { return }

        do {
            try storageLocation.chooseDirectory(using: selectedParentDirectory, moveExistingFiles: moveExistingFiles)
        } catch {
            present(error: error)
        }
    }

    private func resetLocation() {
        guard let moveExistingFiles = resetChoice() else { return }

        do {
            try storageLocation.resetToDefaultDirectory(moveExistingFiles: moveExistingFiles)
        } catch {
            present(error: error)
        }
    }

    private func migrationChoice(for parentDirectory: URL) -> Bool? {
        let destination = destinationPath(for: parentDirectory)

        let alert = NSAlert()
        alert.messageText = "Move your current archive?"
        alert.informativeText = "Local Log will use:\n\(destination)\n\nYou can move your existing entries there, or start using the new location without moving old files."
        alert.addButton(withTitle: "Move Existing Archive")
        alert.addButton(withTitle: "Use New Location")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return true
        case .alertSecondButtonReturn:
            return false
        default:
            return nil
        }
    }

    private func resetChoice() -> Bool? {
        let alert = NSAlert()
        alert.messageText = "Return to the default location?"
        alert.informativeText = "Local Log will use:\n\(storageLocation.defaultDirectoryPath)\n\nYou can move your current archive back to Documents or switch without moving existing files."
        alert.addButton(withTitle: "Move Existing Archive")
        alert.addButton(withTitle: "Use Default Location")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return true
        case .alertSecondButtonReturn:
            return false
        default:
            return nil
        }
    }

    private func present(error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        showingError = true
    }

    private func destinationPath(for selectedDirectory: URL) -> String {
        let normalizedDirectory: URL
        if selectedDirectory.lastPathComponent == StorageLocationStore.folderName {
            normalizedDirectory = selectedDirectory
        } else {
            normalizedDirectory = selectedDirectory.appendingPathComponent(StorageLocationStore.folderName, isDirectory: true)
        }
        return normalizedDirectory.standardizedFileURL.path
    }
}

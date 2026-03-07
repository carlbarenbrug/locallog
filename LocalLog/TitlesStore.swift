import Foundation

final class TitlesStore {
    private let fileURL: URL
    private var titlesById: [String: String] = [:]

    init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("titles.json")
        load()
    }

    func title(for id: UUID) -> String? {
        titlesById[id.uuidString]
    }

    func setTitle(_ title: String, for id: UUID) {
        titlesById[id.uuidString] = title
        save()
    }

    func removeTitle(for id: UUID) {
        titlesById.removeValue(forKey: id.uuidString)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            titlesById = [:]
            return
        }
        titlesById = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(titlesById) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

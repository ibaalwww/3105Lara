import SwiftUI
import UniformTypeIdentifiers

struct PListEditorView: View {
    @State private var entries: [Entry] = []
    @State private var fileURL: URL?
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var message = "No plist loaded"
    @State private var errorText: String?

    struct Entry: Identifiable {
        let id = UUID()
        var key: String
        var value: Bool
    }

    var body: some View {
        List {
            Section {
                Button {
                    showImporter = true
                } label: {
                    Label("Open plist", systemImage: "folder")
                }

                if !entries.isEmpty {
                    Button {
                        showExporter = true
                    } label: {
                        Label("Save working copy", systemImage: "square.and.arrow.down")
                    }
                }
            }

            Section("Status") {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !entries.isEmpty {
                Section("Daemons") {
                    ForEach($entries) { $entry in
                        Toggle(entry.key, isOn: $entry.value)
                    }
                }
            }
        }
        .navigationTitle("Plist Editor")
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.propertyList],
            allowsMultipleSelection: false
        ) { result in
            importPlist(result)
        }
        .fileExporter(
            isPresented: $showExporter,
            document: PlistDocument(entries: entries),
            contentType: .propertyList,
            defaultFilename: "disable"
        ) { result in
            switch result {
            case .success(let url):
                fileURL = url
                message = "Saved: \(url.lastPathComponent)"
            case .failure(let error):
                errorText = error.localizedDescription
            }
        }
        .alert(
            "Plist Error",
            isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                errorText = nil
            }
        } message: {
            Text(errorText ?? "")
        }
    }

    private func importPlist(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            load(url)

        case .failure(let error):
            errorText = error.localizedDescription
        }
    }

    private func load(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)

            var format = PropertyListSerialization.PropertyListFormat.xml

            let object = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: &format
            )

            guard let dictionary = object as? [String: Any] else {
                throw EditorError.invalidStructure
            }

            var result: [Entry] = []

            for key in dictionary.keys.sorted() {
                guard let value = dictionary[key] as? Bool else {
                    throw EditorError.invalidValue(key)
                }

                result.append(
                    Entry(
                        key: key,
                        value: value
                    )
                )
            }

            entries = result
            fileURL = url
            message = "Loaded \(result.count) entries"
            errorText = nil

        } catch let error as EditorError {
            errorText = error.localizedDescription
        } catch {
            errorText = "Unable to read plist: \(error.localizedDescription)"
        }
    }
}

// MARK: - FileDocument

private struct PlistDocument: FileDocument {

    static var readableContentTypes: [UTType] {
        [.propertyList]
    }

    var entries: [PListEditorView.Entry]

    init(entries: [PListEditorView.Entry]) {
        self.entries = entries
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw EditorError.invalidPlist
        }

        var format = PropertyListSerialization.PropertyListFormat.xml

        let object = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: &format
        )

        guard let dictionary = object as? [String: Any] else {
            throw EditorError.invalidStructure
        }

        var result: [PListEditorView.Entry] = []

        for key in dictionary.keys.sorted() {
            guard let value = dictionary[key] as? Bool else {
                throw EditorError.invalidValue(key)
            }

            result.append(
                PListEditorView.Entry(
                    key: key,
                    value: value
                )
            )
        }

        entries = result
    }

    func fileWrapper(
        configuration: WriteConfiguration
    ) throws -> FileWrapper {

        var dictionary: [String: Bool] = [:]

        for entry in entries {
            dictionary[entry.key] = entry.value
        }

        let data = try PropertyListSerialization.data(
            fromPropertyList: dictionary,
            format: .xml,
            options: 0
        )

        return FileWrapper(
            regularFileWithContents: data
        )
    }
}

// MARK: - Errors

private enum EditorError: LocalizedError {

    case invalidPlist
    case invalidStructure
    case invalidValue(String)

    var errorDescription: String? {
        switch self {
        case .invalidPlist:
            return "The selected file is not a valid plist."

        case .invalidStructure:
            return "The plist root must be a dictionary."

        case .invalidValue(let key):
            return "Invalid Boolean value for daemon: \(key)"
        }
    }
}

import SwiftUI
import UniformTypeIdentifiers

struct PListEditorView: View {

    @State private var entries: [DaemonEntry] = []
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var workingURL: URL?
    @State private var status = "No plist loaded"
    @State private var errorMessage: String?

    struct DaemonEntry: Identifiable {
        let id = UUID()
        var key: String
        var enabled: Bool
    }

    var body: some View {
        List {
            Section {
                Button {
                    showingImporter = true
                } label: {
                    Label("Open plist", systemImage: "folder")
                }

                if !entries.isEmpty {
                    Button {
                        exportWorkingCopy()
                    } label: {
                        Label("Save working copy", systemImage: "square.and.arrow.down")
                    }
                }
            }

            Section("Status") {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !entries.isEmpty {
                Section("Daemons") {
                    ForEach($entries) { $entry in
                        Toggle(entry.key, isOn: $entry.enabled)
                    }
                }
            }
        }
        .navigationTitle("Plist Editor")
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.propertyList],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: PlistDocument(entries: entries),
            contentType: .propertyList,
            defaultFilename: workingURL?.deletingPathExtension().lastPathComponent ?? "disable"
        ) { result in
            switch result {
            case .success(let url):
                workingURL = url
                status = "Saved: \(url.lastPathComponent)"
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert(
            "Plist Error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func handleImport(
        _ result: Result<[URL], Error>
    ) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            load(url)

        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func load(_ url: URL) {
        do {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)

            guard !data.isEmpty else {
                throw PlistEditorError.invalidPlist
            }

            var format = PropertyListSerialization.PropertyListFormat.xml
            let object = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: &format
            )

            guard let dictionary = object as? [String: Any] else {
                throw PlistEditorError.invalidStructure
            }

            var parsed: [DaemonEntry] = []

            for key in dictionary.keys.sorted() {
                guard let value = dictionary[key] as? Bool else {
                    throw PlistEditorError.invalidDaemonValue(key)
                }

                parsed.append(
                    DaemonEntry(
                        key: key,
                        enabled: value
                    )
                )
            }

            entries = parsed
            workingURL = url
            status = "Loaded \(parsed.count) daemon entries"
            errorMessage = nil

        } catch let error as PlistEditorError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "Unable to read plist: \(error.localizedDescription)"
        }
    }

    private func exportWorkingCopy() {
        showingExporter = true
    }
}

// MARK: - Document

private struct PlistDocument: FileDocument {

    static var readableContentTypes: [UTType] {
        [.propertyList]
    }

    var entries: [PListEditorView.DaemonEntry]

    init(entries: [PListEditorView.DaemonEntry] = []) {
        self.entries = entries
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw PlistEditorError.invalidPlist
        }

        var format = PropertyListSerialization.PropertyListFormat.xml

        let object = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: &format
        )

        guard let dictionary = object as? [String: Any] else {
            throw PlistEditorError.invalidStructure
        }

        var parsed: [PListEditorView.DaemonEntry] = []

        for key in dictionary.keys.sorted() {
            guard let value = dictionary[key] as? Bool else {
                throw PlistEditorError.invalidDaemonValue(key)
            }

            parsed.append(
                PListEditorView.DaemonEntry(
                    key: key,
                    enabled: value
                )
            )
        }

        entries = parsed
    }

    func fileWrapper(
        configuration: WriteConfiguration
    ) throws -> FileWrapper {

        var dictionary: [String: Bool] = [:]

        for entry in entries {
            dictionary[entry.key] = entry.enabled
        }

        let data = try PropertyListSerialization.data(
            fromPropertyList: dictionary,
            format: .xml,
            options: 0
        )

        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Errors

private enum PlistEditorError: LocalizedError {

    case invalidPlist
    case invalidStructure
    case invalidDaemonValue(String)

    var errorDescription: String? {
        switch self {
        case .invalidPlist:
            return "The selected file is not a valid plist."

        case .invalidStructure:
            return "The plist root must be a dictionary."

        case .invalidDaemonValue(let key):
            return "Invalid Boolean value for daemon: \(key)"
        }
    }
}

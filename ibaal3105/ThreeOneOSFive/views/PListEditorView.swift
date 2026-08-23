import SwiftUI
import UniformTypeIdentifiers

// MARK: - Plist Editor Model

enum IbaalPlistValueType: String, CaseIterable, Identifiable {
    case string = "String"
    case boolean = "Boolean"
    case number = "Number"
    case data = "Data"
    case date = "Date"
    case dictionary = "Dictionary"
    case array = "Array"

    var id: String {
        rawValue
    }

    var symbol: String {
        switch self {
        case .string:
            return "textformat"
        case .boolean:
            return "checkmark.circle"
        case .number:
            return "number"
        case .data:
            return "doc"
        case .date:
            return "calendar"
        case .dictionary:
            return "folder"
        case .array:
            return "list.bullet"
        }
    }
}

final class IbaalPlistNode: Identifiable, ObservableObject {
    let id = UUID()

    @Published var key: String
    @Published var type: IbaalPlistValueType
    @Published var value: String
    @Published var boolValue: Bool
    @Published var children: [IbaalPlistNode]

    init(
        key: String,
        type: IbaalPlistValueType,
        value: String = "",
        boolValue: Bool = false,
        children: [IbaalPlistNode] = []
    ) {
        self.key = key
        self.type = type
        self.value = value
        self.boolValue = boolValue
        self.children = children
    }

    var isContainer: Bool {
        type == .dictionary || type == .array
    }

    var displayValue: String {
        switch type {
        case .boolean:
            return boolValue ? "YES" : "NO"

        case .dictionary, .array:
            let count = children.count
            return "\(count) item" + (count == 1 ? "" : "s")

        default:
            return value.isEmpty ? "—" : value
        }
    }

    func foundationValue() -> Any {
        switch type {
        case .string:
            return value

        case .boolean:
            return boolValue

        case .number:
            if let intValue = Int(value) {
                return NSNumber(value: intValue)
            }

            if let doubleValue = Double(value) {
                return NSNumber(value: doubleValue)
            }

            return NSNumber(value: 0)

        case .data:
            return Data(base64Encoded: value) ?? Data()

        case .date:
            if let date = ISO8601DateFormatter().date(from: value) {
                return date
            }

            return Date(timeIntervalSince1970: 0)

        case .dictionary:
            var dictionary: [String: Any] = [:]

            for child in children {
                dictionary[child.key] = child.foundationValue()
            }

            return dictionary

        case .array:
            return children.map {
                $0.foundationValue()
            }
        }
    }

    static func from(
        _ object: Any,
        key: String
    ) -> IbaalPlistNode {

        if let dictionary = object as? [String: Any] {
            let children = dictionary.keys.sorted().compactMap {
                dictionary[$0].map {
                    from($0, key: $0)
                }
            }

            return IbaalPlistNode(
                key: key,
                type: .dictionary,
                children: children
            )
        }

        if let array = object as? [Any] {
            let children = array.enumerated().map {
                from(
                    $0.element,
                    key: String($0.offset)
                )
            }

            return IbaalPlistNode(
                key: key,
                type: .array,
                children: children
            )
        }

        if let boolValue = object as? Bool {
            return IbaalPlistNode(
                key: key,
                type: .boolean,
                boolValue: boolValue
            )
        }

        if let stringValue = object as? String {
            return IbaalPlistNode(
                key: key,
                type: .string,
                value: stringValue
            )
        }

        if let dataValue = object as? Data {
            return IbaalPlistNode(
                key: key,
                type: .data,
                value: dataValue.base64EncodedString()
            )
        }

        if let dateValue = object as? Date {
            return IbaalPlistNode(
                key: key,
                type: .date,
                value: ISO8601DateFormatter().string(
                    from: dateValue
                )
            )
        }

        if let numberValue = object as? NSNumber {
            return IbaalPlistNode(
                key: key,
                type: .number,
                value: numberValue.stringValue
            )
        }

        return IbaalPlistNode(
            key: key,
            type: .string,
            value: String(describing: object)
        )
    }
}

// MARK: - Editor Model

final class IbaalPlistEditorModel: ObservableObject {
    @Published var root: IbaalPlistNode?
    @Published var fileURL: URL?
    @Published var originalBytes: Int64 = 0
    @Published var editedBytes: Int64 = 0
    @Published var message: String?
    @Published var showingError = false
    @Published var isBusy = false

    let targetPath = "/var/db/com.apple.xpc.launchd/disable.plist"

    var difference: Int64 {
        editedBytes - originalBytes
    }

    var canOverwrite: Bool {
        root != nil &&
        originalBytes > 0 &&
        editedBytes > 0 &&
        editedBytes <= originalBytes
    }

    // MARK: Open System Target

    func openTarget() {
        isBusy = true
        defer {
            isBusy = false
        }

        do {
            let data = try SystemPlistOverwrite.readTarget()

            try SystemPlistOverwrite.validate(data)

            let object = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            )

            guard let dictionary = object as? [String: Any] else {
                throw SystemPlistOverwriteError.invalidStructure
            }

            root = IbaalPlistNode.from(
                dictionary,
                key: "Root"
            )

            fileURL = try SystemPlistOverwrite.targetURL()

            originalBytes = Int64(data.count)
            editedBytes = Int64(data.count)

            message = "Loaded \(fileURL?.lastPathComponent ?? "disable.plist")"

            log("plist editor: system target loaded")
        } catch {
            clear()

            message = error.localizedDescription
            showingError = true

            log("plist editor: target open failed")
        }
    }

    // MARK: Open Local File

    func open(_ url: URL) {
        isBusy = true
        defer {
            isBusy = false
        }

        do {
            let data = try Data(
                contentsOf: url,
                options: .mappedIfSafe
            )

            let object = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            )

            guard let dictionary = object as? [String: Any] else {
                throw IbaalPlistError.invalidStructure
            }

            root = IbaalPlistNode.from(
                dictionary,
                key: "Root"
            )

            fileURL = url

            originalBytes = Int64(data.count)
            editedBytes = Int64(data.count)

            message = "Loaded \(url.lastPathComponent)"
        } catch {
            clear()

            message = "Unable to open \(url.path): \(error.localizedDescription)"
            showingError = true
        }
    }

    // MARK: Refresh

    func refreshSize() {
        guard let root else {
            editedBytes = 0
            return
        }

        do {
            let data = try serialize(root)
            editedBytes = Int64(data.count)
        } catch {
            editedBytes = 0
        }
    }

    // MARK: Strict System Overwrite

    func overwrite() {
        guard let root else {
            return
        }

        isBusy = true
        defer {
            isBusy = false
        }

        do {
            let data = try serialize(root)

            guard Int64(data.count) <= originalBytes else {
                throw IbaalPlistError.editedFileLarger
            }

            try SystemPlistOverwrite.overwrite(
                data: data
            )

            let verifiedData = try SystemPlistOverwrite.readTarget()

            try SystemPlistOverwrite.validate(
                verifiedData
            )

            guard verifiedData == data else {
                throw SystemPlistOverwriteError.verificationFailed
            }

            originalBytes = Int64(verifiedData.count)
            editedBytes = Int64(verifiedData.count)

            fileURL = try? SystemPlistOverwrite.targetURL()

            message = "System plist overwritten and verified."

            log("plist editor: overwrite verified")
        } catch {
            message = error.localizedDescription
            showingError = true

            log("plist editor: overwrite failed")
        }
    }

    // MARK: Serialization

    private func serialize(
        _ root: IbaalPlistNode
    ) throws -> Data {

        let object = root.foundationValue()

        guard PropertyListSerialization.propertyList(
            object,
            isValidFor: .binary
        ) else {
            throw IbaalPlistError.invalidPlist
        }

        return try PropertyListSerialization.data(
            fromPropertyList: object,
            format: .binary,
            options: 0
        )
    }

    private func clear() {
        root = nil
        fileURL = nil
        originalBytes = 0
        editedBytes = 0
    }
}

// MARK: - Errors

enum IbaalPlistError: LocalizedError {
    case invalidPlist
    case invalidStructure
    case editedFileLarger

    var errorDescription: String? {
        switch self {
        case .invalidPlist:
            return "The selected file is not a valid property list."

        case .invalidStructure:
            return "The plist root must be a dictionary."

        case .editedFileLarger:
            return "The edited plist is larger than the original. Overwrite is blocked."
        }
    }
}

// MARK: - UI

struct IbaalPlistEditorView: View {
    @StateObject private var model = IbaalPlistEditorModel()

    @State private var search = ""
    @State private var showPicker = false
    @State private var selectedNode: IbaalPlistNode?
    @State private var addParent: IbaalPlistNode?

    var body: some View {
        NavigationStack {
            List {
                targetSection

                if let root = model.root {
                    Section {
                        IbaalPlistNodeView(
                            node: root,
                            search: search,
                            onEdit: {
                                selectedNode = $0
                            },
                            onDelete: {
                                delete($0, from: root)
                            },
                            onAdd: {
                                addParent = $0
                            }
                        )
                    } header: {
                        Text("Plist")
                    }
                } else {
                    emptyState
                }
            }
            .searchable(
                text: $search,
                prompt: "Search keys and values"
            )
            .navigationTitle("Plist Editor")
            .toolbar {
                ToolbarItemGroup(
                    placement: .navigationBarTrailing
                ) {
                    Button {
                        showPicker = true
                    } label: {
                        Image(systemName: "folder")
                    }

                    Button {
                        addParent = model.root
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(model.root == nil)
                }
            }
            .sheet(isPresented: $showPicker) {
                IbaalDocumentPicker { url in
                    model.open(url)
                }
            }
            .sheet(item: $selectedNode) { node in
                IbaalPlistEditSheet(node: node) {
                    model.refreshSize()
                }
            }
            .sheet(item: $addParent) { parent in
                IbaalPlistAddSheet(parent: parent) {
                    model.refreshSize()
                }
            }
            .alert(
                "Plist Editor",
                isPresented: $model.showingError
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(
                    model.message ??
                    "Unknown error"
                )
            }
            .safeAreaInset(edge: .bottom) {
                validationBar
            }
        }
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(
                systemName: "doc.badge.gearshape"
            )
            .font(.system(size: 34))
            .foregroundStyle(AppTheme.accent)

            Text("No Plist Loaded")
                .font(.headline)

            Text(
                "Open the system target or choose a local plist."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: Target Section

    private var targetSection: some View {
        Section("System Target") {
            HStack {
                Image(systemName: "target")
                    .foregroundStyle(AppTheme.accent)

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text("disable.plist")
                        .font(.headline)

                    Text(
                        model.fileURL?.path ??
                        model.targetPath
                    )
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }
            }

            HStack {
                Button("Open Target") {
                    model.openTarget()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)

                Button("Choose File") {
                    showPicker = true
                }
                .buttonStyle(.bordered)
                .disabled(model.isBusy)
            }
        }
    }

    // MARK: Validation Bar

    private var validationBar: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(
                        "Original \(formatBytes(model.originalBytes))"
                    )

                    Text(
                        "Edited \(formatBytes(model.editedBytes))"
                    )
                }
                .font(.caption.monospaced())

                Spacer()

                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        model.canOverwrite
                        ? AppTheme.accent
                        : .secondary
                    )
            }

            Button {
                model.overwrite()
            } label: {
                Label(
                    model.canOverwrite
                    ? "Overwrite System Plist"
                    : "Overwrite Unavailable",
                    systemImage:
                        model.canOverwrite
                        ? "arrow.down.doc"
                        : "lock"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                !model.canOverwrite ||
                model.isBusy
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var statusText: String {
        guard
            model.originalBytes > 0,
            model.editedBytes > 0
        else {
            return "No size"
        }

        if model.editedBytes <= model.originalBytes {
            return "✓ Safe"
        }

        return "⚠ Larger than original"
    }

    private func formatBytes(
        _ bytes: Int64
    ) -> String {
        ByteCountFormatter.string(
            fromByteCount: bytes,
            countStyle: .file
        )
    }

    // MARK: Delete

    private func delete(
        _ node: IbaalPlistNode,
        from root: IbaalPlistNode
    ) {
        guard node.id != root.id else {
            return
        }

        func remove(
            _ parent: IbaalPlistNode
        ) -> Bool {

            if let index = parent.children.firstIndex(
                where: {
                    $0.id == node.id
                }
            ) {
                parent.children.remove(
                    at: index
                )

                return true
            }

            for child in parent.children
            where child.isContainer {
                if remove(child) {
                    return true
                }
            }

            return false
        }

        _ = remove(root)

        model.refreshSize()
    }
}

// MARK: - Node View

private struct IbaalPlistNodeView: View {
    @ObservedObject var node: IbaalPlistNode

    let search: String
    let onEdit: (IbaalPlistNode) -> Void
    let onDelete: (IbaalPlistNode) -> Void
    let onAdd: (IbaalPlistNode) -> Void

    private var visibleChildren: [IbaalPlistNode] {
        guard !search.isEmpty else {
            return node.children
        }

        return node.children.filter {
            $0.key.localizedCaseInsensitiveContains(search)
            ||
            $0.displayValue.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        if node.isContainer {
            DisclosureGroup {
                ForEach(visibleChildren) { child in
                    IbaalPlistNodeView(
                        node: child,
                        search: search,
                        onEdit: onEdit,
                        onDelete: onDelete,
                        onAdd: onAdd
                    )
                }
            } label: {
                nodeLabel
            }
            .contextMenu {
                Button("Add Child") {
                    onAdd(node)
                }

                Button("Edit") {
                    onEdit(node)
                }

                if node.key != "Root" {
                    Button(
                        "Delete",
                        role: .destructive
                    ) {
                        onDelete(node)
                    }
                }
            }
        } else {
            nodeLabel
                .contextMenu {
                    Button("Edit") {
                        onEdit(node)
                    }

                    Button(
                        "Delete",
                        role: .destructive
                    ) {
                        onDelete(node)
                    }
                }
        }
    }

    private var nodeLabel: some View {
        HStack(spacing: 9) {
            Image(
                systemName: node.type.symbol
            )
            .foregroundStyle(AppTheme.accent)
            .frame(width: 22)

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(node.key)
                    .lineLimit(1)

                Text(
                    node.type == .boolean
                    ? "Boolean • \(node.displayValue)"
                    : "\(node.type.rawValue) • \(node.displayValue)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            if node.type == .boolean {
                Text(
                    node.boolValue
                    ? "YES"
                    : "NO"
                )
                .font(
                    .caption.weight(.semibold)
                )
                .foregroundStyle(
                    node.boolValue
                    ? AppTheme.accent
                    : .secondary
                )
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Edit Sheet

private struct IbaalPlistEditSheet: View {
    @ObservedObject var node: IbaalPlistNode

    let onSave: () -> Void

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Key") {
                    TextField(
                        "Key",
                        text: $node.key
                    )
                }

                if node.type == .boolean {
                    Toggle(
                        "Boolean",
                        isOn: $node.boolValue
                    )
                } else if !node.isContainer {
                    Section("Value") {
                        TextField(
                            "Value",
                            text: $node.value,
                            axis: .vertical
                        )
                        .lineLimit(3...8)
                    }
                } else {
                    Section {
                        Text(
                            "\(node.children.count) children"
                        )
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .navigationBarLeading
                ) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement: .navigationBarTrailing
                ) {
                    Button("Done") {
                        onSave()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Add Sheet

private struct IbaalPlistAddSheet: View {
    @ObservedObject var parent: IbaalPlistNode

    let onSave: () -> Void

    @Environment(\.dismiss)
    private var dismiss

    @State private var key = "NewItem"
    @State private var type: IbaalPlistValueType = .boolean
    @State private var value = ""
    @State private var boolValue = true

    var body: some View {
        NavigationStack {
            Form {
                Section("New Item") {
                    TextField(
                        "Key",
                        text: $key
                    )

                    Picker(
                        "Type",
                        selection: $type
                    ) {
                        ForEach(
                            IbaalPlistValueType.allCases
                        ) { type in
                            Text(type.rawValue)
                                .tag(type)
                        }
                    }

                    if type == .boolean {
                        Toggle(
                            "Value",
                            isOn: $boolValue
                        )
                    } else if
                        type == .dictionary ||
                        type == .array
                    {
                        Text(
                            "An empty \(type.rawValue.lowercased()) will be created."
                        )
                        .foregroundStyle(.secondary)
                    } else {
                        TextField(
                            "Value",
                            text: $value,
                            axis: .vertical
                        )
                    }
                }
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .navigationBarLeading
                ) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement: .navigationBarTrailing
                ) {
                    Button("Add") {
                        let trimmedKey = key.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )

                        let node = IbaalPlistNode(
                            key:
                                parent.type == .array
                                ? String(parent.children.count)
                                : trimmedKey,
                            type: type,
                            value: value,
                            boolValue: boolValue
                        )

                        parent.children.append(node)

                        onSave()

                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(
                        parent.type == .dictionary &&
                        key.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }
            }
        }
    }
}

// MARK: - Document Picker

private struct IbaalDocumentPicker:
    UIViewControllerRepresentable {

    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onPick: onPick
        )
    }

    func makeUIViewController(
        context: Context
    ) -> UIDocumentPickerViewController {

        let controller =
            UIDocumentPickerViewController(
                forOpeningContentTypes: [
                    UTType.propertyList,
                    UTType.data
                ],
                asCopy: true
            )

        controller.allowsMultipleSelection = false
        controller.delegate = context.coordinator

        return controller
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    final class Coordinator:
        NSObject,
        UIDocumentPickerDelegate {

        let onPick: (URL) -> Void

        init(
            onPick: @escaping (URL) -> Void
        ) {
            self.onPick = onPick
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            guard let url = urls.first else {
                return
            }

            onPick(url)
        }
    }
}

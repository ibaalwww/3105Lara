import Foundation

enum PlistWorkingCopyError: LocalizedError {
    case unreadable
    case invalidPlist
    case invalidRoot
    case writeFailed
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "Unable to read the plist."
        case .invalidPlist:
            return "The file is not a valid plist."
        case .invalidRoot:
            return "The plist root must be a dictionary."
        case .writeFailed:
            return "Unable to write the working copy."
        case .verificationFailed:
            return "Working-copy verification failed."
        }
    }
}

enum PlistWorkingCopyService {

    // MARK: - Read

    static func read(_ url: URL) throws -> [String: Any] {
        let data: Data

        do {
            data = try Data(
                contentsOf: url,
                options: .mappedIfSafe
            )
        } catch {
            throw PlistWorkingCopyError.unreadable
        }

        return try parse(data)
    }

    // MARK: - Validate

    static func validate(_ url: URL) throws {
        _ = try read(url)
    }

    static func validate(data: Data) throws -> [String: Any] {
        try parse(data)
    }

    // MARK: - Working Copy

    @discardableResult
    static func makeWorkingCopy(
        from sourceURL: URL
    ) throws -> URL {

        let sourceDictionary = try read(sourceURL)

        let data: Data

        do {
            data = try PropertyListSerialization.data(
                fromPropertyList: sourceDictionary,
                format: .xml,
                options: 0
            )
        } catch {
            throw PlistWorkingCopyError.invalidPlist
        }

        let caches = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0]

        let directory = caches.appendingPathComponent(
            "ibaal3105-plist",
            isDirectory: true
        )

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw PlistWorkingCopyError.writeFailed
        }

        let workingURL = directory.appendingPathComponent(
            "working-\(UUID().uuidString).plist"
        )

        do {
            try data.write(
                to: workingURL,
                options: [.atomic]
            )
        } catch {
            throw PlistWorkingCopyError.writeFailed
        }

        let verification = try read(workingURL)

        guard dictionariesEqual(
            sourceDictionary,
            verification
        ) else {
            try? FileManager.default.removeItem(at: workingURL)
            throw PlistWorkingCopyError.verificationFailed
        }

        log("plist: working copy created")
        log("plist: \(workingURL.path)")

        return workingURL
    }

    // MARK: - Write Edited Working Copy

    static func write(
        dictionary: [String: Any],
        to url: URL
    ) throws {

        guard !dictionary.isEmpty || isValidEmptyDictionary(dictionary) else {
            throw PlistWorkingCopyError.invalidRoot
        }

        let data: Data

        do {
            data = try PropertyListSerialization.data(
                fromPropertyList: dictionary,
                format: .xml,
                options: 0
            )
        } catch {
            throw PlistWorkingCopyError.invalidPlist
        }

        do {
            try data.write(
                to: url,
                options: [.atomic]
            )
        } catch {
            throw PlistWorkingCopyError.writeFailed
        }

        let result = try read(url)

        guard dictionariesEqual(dictionary, result) else {
            throw PlistWorkingCopyError.verificationFailed
        }

        log("plist: working copy write verified")
    }

    // MARK: - Parser

    private static func parse(
        _ data: Data
    ) throws -> [String: Any] {

        guard !data.isEmpty else {
            throw PlistWorkingCopyError.invalidPlist
        }

        let object: Any

        do {
            object = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            )
        } catch {
            throw PlistWorkingCopyError.invalidPlist
        }

        guard let dictionary = object as? [String: Any] else {
            throw PlistWorkingCopyError.invalidRoot
        }

        return dictionary
    }

    // MARK: - Equality

    private static func dictionariesEqual(
        _ lhs: [String: Any],
        _ rhs: [String: Any]
    ) -> Bool {

        NSDictionary(dictionary: lhs).isEqual(
            to: NSDictionary(dictionary: rhs)
        )
    }

    private static func isValidEmptyDictionary(
        _ dictionary: [String: Any]
    ) -> Bool {
        dictionary.isEmpty
    }
}

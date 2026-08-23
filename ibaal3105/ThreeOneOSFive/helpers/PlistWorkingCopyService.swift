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

    static func read(_ url: URL) throws -> [String: Any] {
        let data: Data

        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw PlistWorkingCopyError.unreadable
        }

        return try parse(data)
    }

    static func validate(_ url: URL) throws {
        _ = try read(url)
    }

    @discardableResult
    static func makeWorkingCopy(
        from sourceURL: URL
    ) throws -> URL {

        let dictionary = try read(sourceURL)

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

        let directory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0]

        let workingDirectory = directory
            .appendingPathComponent(
                "ibaal3105-plist",
                isDirectory: true
            )

        try? FileManager.default.createDirectory(
            at: workingDirectory,
            withIntermediateDirectories: true
        )

        let workingURL = workingDirectory
            .appendingPathComponent(
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

        guard NSDictionary(dictionary: dictionary).isEqual(
            to: NSDictionary(dictionary: verification)
        ) else {
            throw PlistWorkingCopyError.verificationFailed
        }

        log("plist: working copy created")
        log("plist: \(workingURL.path)")

        return workingURL
    }

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
}

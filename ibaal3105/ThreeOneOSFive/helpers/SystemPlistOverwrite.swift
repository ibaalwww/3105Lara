import Foundation

enum SystemPlistOverwriteError: LocalizedError {
    case invalidPlist
    case invalidStructure
    case invalidDaemonValue(String)
    case targetNotFound
    case writeFailed
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .invalidPlist:
            return "The selected file is not a valid plist."
        case .invalidStructure:
            return "The plist root must be a dictionary."
        case .invalidDaemonValue(let key):
            return "Invalid value for daemon: \(key)"
        case .targetNotFound:
            return "System disable.plist target was not found."
        case .writeFailed:
            return "Failed to overwrite the system plist."
        case .verificationFailed:
            return "The overwritten plist failed verification."
        }
    }
}

enum SystemPlistOverwrite {

    private static let targetPaths = [
        "/var/db/com.apple.xpc.launchd/disabled.plist",
        "/var/db/com.apple.xpc.launchd/disable.plist"
    ]

    // MARK: - Target Detection

    static func targetURL() throws -> URL {
        let fm = FileManager.default

        for path in targetPaths {
            let url = URL(fileURLWithPath: path)

            if fm.fileExists(atPath: url.path) {
                return url
            }
        }

        throw SystemPlistOverwriteError.targetNotFound
    }

    // MARK: - Strict Plist Parser

    private static func parse(
        _ data: Data
    ) throws -> [String: Any] {

        guard !data.isEmpty else {
            throw SystemPlistOverwriteError.invalidPlist
        }

        let object: Any

        do {
            object = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            )
        } catch {
            throw SystemPlistOverwriteError.invalidPlist
        }

        guard let dictionary = object as? [String: Any] else {
            throw SystemPlistOverwriteError.invalidStructure
        }

        for (key, value) in dictionary {

            guard !key.isEmpty else {
                throw SystemPlistOverwriteError.invalidStructure
            }

            guard value is Bool else {
                throw SystemPlistOverwriteError.invalidDaemonValue(key)
            }
        }

        return dictionary
    }

    // MARK: - Working Copy Validation

    static func validate(
        sourceURL: URL
    ) throws -> Data {

        let data: Data

        do {
            data = try Data(
                contentsOf: sourceURL,
                options: .mappedIfSafe
            )
        } catch {
            throw SystemPlistOverwriteError.invalidPlist
        }

        _ = try parse(data)

        return data
    }

    // MARK: - Strict Overwrite

    static func overwrite(
        sourceURL: URL
    ) throws {

        log("plist: validating working copy")

        let sourceData = try validate(
            sourceURL: sourceURL
        )

        let sourceDictionary = try parse(
            sourceData
        )

        let targetURL = try targetURL()

        log("plist: target = \(targetURL.path)")

        let fm = FileManager.default
        let directory = targetURL.deletingLastPathComponent()

        let temporaryURL = directory.appendingPathComponent(
            ".ibaal3105-\(UUID().uuidString).plist"
        )

        defer {
            try? fm.removeItem(at: temporaryURL)
        }

        // Write temporary file.
        log("plist: writing temporary file")

        do {
            try sourceData.write(
                to: temporaryURL,
                options: [.atomic]
            )
        } catch {
            throw SystemPlistOverwriteError.writeFailed
        }

        // Validate temporary file.
        let temporaryData: Data

        do {
            temporaryData = try Data(
                contentsOf: temporaryURL,
                options: .mappedIfSafe
            )
        } catch {
            throw SystemPlistOverwriteError.writeFailed
        }

        let temporaryDictionary = try parse(
            temporaryData
        )

        guard NSDictionary(
            dictionary: sourceDictionary
        ).isEqual(
            to: NSDictionary(
                dictionary: temporaryDictionary
            )
        ) else {
            throw SystemPlistOverwriteError.invalidPlist
        }

        // Replace target.
        log("plist: replacing system file")

        do {
            _ = try fm.replaceItemAt(
                targetURL,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: []
            )
        } catch {
            throw SystemPlistOverwriteError.writeFailed
        }

        // Read-back verification.
        log("plist: verifying system file")

        let resultData: Data

        do {
            resultData = try Data(
                contentsOf: targetURL,
                options: .mappedIfSafe
            )
        } catch {
            throw SystemPlistOverwriteError.verificationFailed
        }

        let resultDictionary: [String: Any]

        do {
            resultDictionary = try parse(
                resultData
            )
        } catch {
            throw SystemPlistOverwriteError.verificationFailed
        }

        guard NSDictionary(
            dictionary: sourceDictionary
        ).isEqual(
            to: NSDictionary(
                dictionary: resultDictionary
            )
        ) else {
            throw SystemPlistOverwriteError.verificationFailed
        }

        log("plist: overwrite verified successfully")
    }
}

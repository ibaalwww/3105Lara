import Foundation

enum SystemPlistOverwriteError: LocalizedError {
    case invalidPlist
    case invalidStructure
    case targetNotFound
    case writeFailed
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .invalidPlist:
            return "The plist is not valid."
        case .invalidStructure:
            return "The plist root must be a dictionary."
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
        "/var/db/com.apple.xpc.launchd/disable.plist",
        "/var/db/com.apple.xpc.launchd/disabled.plist"
    ]

    // MARK: - Target

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

    // MARK: - Read

    static func readTarget() throws -> Data {
        let url = try targetURL()

        do {
            return try Data(
                contentsOf: url,
                options: .mappedIfSafe
            )
        } catch {
            throw SystemPlistOverwriteError.invalidPlist
        }
    }

    // MARK: - Validate

    static func validate(_ data: Data) throws {

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

        guard object is [String: Any] else {
            throw SystemPlistOverwriteError.invalidStructure
        }

        guard PropertyListSerialization.propertyList(
            object,
            isValidFor: .binary
        ) else {
            throw SystemPlistOverwriteError.invalidPlist
        }
    }

    // MARK: - Strict Overwrite

    static func overwrite(data: Data) throws {

        try validate(data)

        let targetURL = try targetURL()
        let fm = FileManager.default

        let directory = targetURL.deletingLastPathComponent()

        let temporaryURL = directory.appendingPathComponent(
            ".ibaal3105-\(UUID().uuidString).plist"
        )

        defer {
            try? fm.removeItem(at: temporaryURL)
        }

        log("plist: target = \(targetURL.path)")
        log("plist: validating edited data")

        // Write staging file.
        do {
            try data.write(
                to: temporaryURL,
                options: [.atomic]
            )
        } catch {
            throw SystemPlistOverwriteError.writeFailed
        }

        // Validate staging file again.
        let stagedData: Data

        do {
            stagedData = try Data(
                contentsOf: temporaryURL,
                options: .mappedIfSafe
            )
        } catch {
            throw SystemPlistOverwriteError.writeFailed
        }

        do {
            try validate(stagedData)
        } catch {
            throw SystemPlistOverwriteError.writeFailed
        }

        // Replace target.
        log("plist: replacing target")

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

        // Read back.
        log("plist: verifying target")

        let resultData: Data

        do {
            resultData = try Data(
                contentsOf: targetURL,
                options: .mappedIfSafe
            )
        } catch {
            throw SystemPlistOverwriteError.verificationFailed
        }

        do {
            try validate(resultData)
        } catch {
            throw SystemPlistOverwriteError.verificationFailed
        }

        guard resultData == data else {
            throw SystemPlistOverwriteError.verificationFailed
        }

        log("plist: overwrite verified successfully")
    }
}

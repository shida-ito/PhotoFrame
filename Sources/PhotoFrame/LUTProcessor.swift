import CoreImage
import Foundation

struct LUTCube: Sendable {
    let dimension: Int
    let cubeData: Data
}

enum LUTError: LocalizedError {
    case missingFile
    case cannotReadFile
    case unsupportedFormat
    case invalidCubeSize
    case invalidCubeData

    var errorDescription: String? {
        switch self {
        case .missingFile:
            return "The selected LUT file could not be found."
        case .cannotReadFile:
            return "The LUT file could not be read."
        case .unsupportedFormat:
            return "Only .cube LUT files are supported."
        case .invalidCubeSize:
            return "The LUT file does not contain a valid 3D cube size."
        case .invalidCubeData:
            return "The LUT file contains invalid cube data."
        }
    }
}

enum LUTProcessor {
    private static let cache = LUTCache()

    static func cube(for configuration: LUTConfiguration?) throws -> LUTCube? {
        guard let configuration,
              configuration.isEnabled,
              let fileURL = configuration.resolvedURL else {
            return nil
        }

        guard fileURL.pathExtension.lowercased() == "cube" else {
            throw LUTError.unsupportedFormat
        }

        return try cache.cube(for: fileURL)
    }

    private final class LUTCache: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String: LUTCube] = [:]

        func cube(for fileURL: URL) throws -> LUTCube {
            let cacheKey = fileURL.standardizedFileURL.path

            lock.lock()
            if let cached = storage[cacheKey] {
                lock.unlock()
                return cached
            }
            lock.unlock()

            let parsed = try parseCubeFile(at: fileURL)

            lock.lock()
            storage[cacheKey] = parsed
            lock.unlock()

            return parsed
        }
    }

    private static func parseCubeFile(at fileURL: URL) throws -> LUTCube {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw LUTError.missingFile
        }

        guard let rawText = try? String(contentsOf: fileURL, encoding: .utf8) else {
            throw LUTError.cannotReadFile
        }

        var cubeSize: Int?
        var values: [Float] = []

        for rawLine in rawText.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let keyword = tokens.first else { continue }

            switch keyword.uppercased() {
            case "TITLE", "DOMAIN_MIN", "DOMAIN_MAX", "LUT_3D_INPUT_RANGE":
                continue
            case "LUT_1D_SIZE":
                throw LUTError.unsupportedFormat
            case "LUT_3D_SIZE":
                guard tokens.count >= 2, let size = Int(tokens[1]), size > 1 else {
                    throw LUTError.invalidCubeSize
                }
                cubeSize = size
            default:
                guard tokens.count >= 3,
                      let red = Float(tokens[0]),
                      let green = Float(tokens[1]),
                      let blue = Float(tokens[2]) else {
                    throw LUTError.invalidCubeData
                }
                values.append(red)
                values.append(green)
                values.append(blue)
                values.append(1.0)
            }
        }

        guard let cubeSize else {
            throw LUTError.invalidCubeSize
        }

        let expectedValueCount = cubeSize * cubeSize * cubeSize * 4
        guard values.count == expectedValueCount else {
            throw LUTError.invalidCubeData
        }

        let data = values.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }

        return LUTCube(dimension: cubeSize, cubeData: data)
    }
}

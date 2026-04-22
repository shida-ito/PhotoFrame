import Foundation

enum PresetCodecError: Error {
    case invalidPresetFile
}

enum PresetCodec {
    static func decodeStoredPresets(from data: Data) -> [Preset] {
        guard !data.isEmpty else { return [] }
        let presets = (try? JSONDecoder().decode([Preset].self, from: data)) ?? []
        return sortedPresets(presets)
    }

    static func encodeStoredPresets(_ presets: [Preset]) -> Data? {
        try? JSONEncoder().encode(sortedPresets(presets))
    }

    static func decodeTransferPayload(from data: Data) throws -> [Preset] {
        let decoder = JSONDecoder()
        if let presets = try? decoder.decode([Preset].self, from: data) {
            return presets
        }
        if let preset = try? decoder.decode(Preset.self, from: data) {
            return [preset]
        }
        throw PresetCodecError.invalidPresetFile
    }

    static func encodeTransferPayload(for presets: [Preset]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let jsonData: Data
        if presets.count == 1, let preset = presets.first {
            jsonData = try encoder.encode(preset)
        } else {
            jsonData = try encoder.encode(presets)
        }

        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw PresetCodecError.invalidPresetFile
        }

        let asciiString = makeASCIIJSONString(from: jsonString)
        guard let asciiData = asciiString.data(using: .ascii) else {
            throw PresetCodecError.invalidPresetFile
        }

        return asciiData
    }

    static func mergedPresets(existing: [Preset], imported: [Preset]) -> [Preset] {
        var merged = existing
        var usedIDs = Set(existing.map(\.id))

        for var preset in imported {
            while usedIDs.contains(preset.id) {
                preset.id = UUID()
            }
            usedIDs.insert(preset.id)
            merged.append(preset)
        }

        return sortedPresets(merged)
    }

    static func sortedPresets(_ presets: [Preset]) -> [Preset] {
        presets.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func sanitizedFileNameComponent(from presetName: String) -> String {
        let trimmedName = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = trimmedName.isEmpty ? "PhotoFrame-Preset" : trimmedName
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return fallbackName
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
    }

    private static func makeASCIIJSONString(from string: String) -> String {
        var asciiString = ""
        asciiString.reserveCapacity(string.count)

        for scalar in string.unicodeScalars {
            if scalar.isASCII {
                asciiString.unicodeScalars.append(scalar)
                continue
            }

            for codeUnit in String(scalar).utf16 {
                asciiString += String(format: "\\u%04X", codeUnit)
            }
        }

        return asciiString
    }
}

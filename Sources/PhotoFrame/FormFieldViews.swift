import SwiftUI

private enum NumericFieldFormatterCache {
    static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 3
        return formatter
    }()
}

struct NumericField<T: BinaryFloatingPoint>: View {
    @Binding var value: T
    @State private var text: String = ""

    private func formattedValue(_ value: T) -> String {
        NumericFieldFormatterCache.formatter.string(from: NSNumber(value: Double(value))) ?? ""
    }

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .onChange(of: text) { _, newValue in
                if let doubleValue = Double(newValue) {
                    value = T(doubleValue)
                }
            }
            .onChange(of: value) { _, newValue in
                let formatted = formattedValue(newValue)
                if text != formatted {
                    text = formatted
                }
            }
            .onAppear {
                text = formattedValue(value)
            }
    }
}

struct DebouncedTextField: View {
    let placeholder: String
    @Binding var text: String
    @State private var draftText = ""
    @State private var task: Task<Void, Never>? = nil

    var body: some View {
        TextField(placeholder, text: $draftText)
            .textFieldStyle(.roundedBorder)
            .onChange(of: draftText) { _, newValue in
                task?.cancel()
                task = Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard !Task.isCancelled else { return }
                    text = newValue
                }
            }
            .onChange(of: text) { _, newValue in
                if draftText != newValue {
                    draftText = newValue
                }
            }
            .onAppear {
                draftText = text
            }
    }
}

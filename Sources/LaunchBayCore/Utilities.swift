import Foundation

extension String {
    public var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func truncatedDigest(length: Int = 12) -> String {
        let value: String
        if let colon = firstIndex(of: ":") {
            value = String(self[index(after: colon)...])
        } else {
            value = self
        }
        return String(value.prefix(max(1, length)))
    }
}

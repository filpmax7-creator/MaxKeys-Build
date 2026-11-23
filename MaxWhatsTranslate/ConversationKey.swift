import Foundation
import CryptoKit

private func stableValue(_ value: Any, depth: Int = 0) -> String? {
    guard depth < 7 else { return nil }
    if let text = value as? String { return text.isEmpty ? nil : "s\(text.utf8.count):\(text)" }
    if let id = value as? UUID { return id.uuidString }
    if let id = value as? NSNumber { return "n" + id.stringValue }
    let mirror = Mirror(reflecting: value)
    guard !mirror.children.isEmpty, mirror.children.count <= 12,
          [.optional, .struct, .tuple, .enum].contains(mirror.displayStyle) else { return nil }
    var components = [String]()
    for child in mirror.children {
        guard let part = stableValue(child.value, depth: depth + 1) else { return nil }
        components.append("\(child.label ?? "")=\(part.utf8.count):\(part)")
    }
    return components.joined(separator: "|")
}

@_cdecl("MXCopyConversationKey")
public func conversationKey(_ raw: UnsafeRawPointer) -> UnsafeMutableRawPointer? {
    let screen = Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
    guard let id = Mirror(reflecting: screen).children.first(where: { $0.label == "conversationID" })?.value,
          let stable = stableValue(id) else { return nil }
    let hash = SHA256.hash(data: Data(stable.utf8)).map { String(format: "%02x", $0) }.joined()
    return Unmanaged.passRetained(("twitter.dm.swift." + hash) as NSString).toOpaque()
}

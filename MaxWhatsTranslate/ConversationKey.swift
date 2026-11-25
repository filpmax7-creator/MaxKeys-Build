import UIKit
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


@_cdecl("MXOutgoingMessage")
public func outgoingMessage(_ raw: UnsafeRawPointer) -> Int32 {
    let holder = Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
    func inspect(_ value: Any, depth: Int) -> Int32 {
        guard depth < 5 else { return -1 }
        let mirror = Mirror(reflecting: value)
        for child in mirror.children {
            let key = child.label ?? ""
            if ["isOutgoing","isMine","isFromMe","isSentByMe","isSender","isCurrentUser","isOwnMessage","isIncoming"].contains(key),
               let flag = child.value as? Bool {
                return (key == "isIncoming" ? !flag : flag) ? 1 : 0
            }
        }
        for child in mirror.children where mirror.displayStyle == .optional || ["message","viewModel","configuration","direction","deliveryDirection"].contains(child.label ?? "") {
            let result = inspect(child.value, depth: depth + 1)
            if result >= 0 { return result }
        }
        return -1
    }
    return inspect(holder, depth: 0)
}

private func sileoField<T>(_ owner: AnyObject, _ names: [String], as type: T.Type) -> T? {
    var mirror: Mirror? = Mirror(reflecting: owner)
    while let current = mirror {
        for child in current.children where names.contains(child.label ?? "") {
            if let value = child.value as? T { return value }
        }
        mirror = current.superclassMirror
    }
    return nil
}

@_cdecl("MXDepictionRoot")
public func depictionRoot(_ raw: UnsafeRawPointer) -> UnsafeMutableRawPointer? {
    let owner = Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
    guard let view = sileoField(owner, ["depictionView", "depiction", "$__lazy_storage_$_depiction"], as: UIView.self) else { return nil }
    return Unmanaged.passRetained(view).toOpaque()
}

@_cdecl("MXDepictionText")
public func depictionText(_ raw: UnsafeRawPointer) -> UnsafeMutableRawPointer? {
    let owner = Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
    let rich = sileoField(owner, ["attributedString", "attributedText"], as: NSAttributedString.self)
    guard let text = rich?.string, !text.isEmpty else { return nil }
    return Unmanaged.passRetained(text as NSString).toOpaque()
}

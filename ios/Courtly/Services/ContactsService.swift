import Contacts
import CryptoKit
import Foundation

/// A contact's hashed email, with the name from the address book for display.
struct HashedContact {
    let hash: String
    let displayName: String
}

/// Reads the address book and hashes every email address in it, on the device.
/// Only the hashes are sent to the backend; raw numbers never leave the device.
struct ContactsService {
    func requestAccess() async -> Bool {
        let store = CNContactStore()
        return await withCheckedContinuation { continuation in
            store.requestAccess(for: .contacts) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Emails only: they're verified at sign-in, while a phone number on a profile isn't, so matching
    /// on phones would let someone pose as a contact. The server caps a check at 1,000.
    func hashedContacts(limit: Int = 1000) throws -> [HashedContact] {
        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var result: [HashedContact] = []
        var seen = Set<String>()
        try store.enumerateContacts(with: request) { contact, stop in
            let name = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            let values = contact.emailAddresses.map { String($0.value).lowercased().trimmingCharacters(in: .whitespaces) }
            for value in values {
                if result.count >= limit { stop.pointee = true; break }
                let hash = Self.hash(value)
                if seen.insert(hash).inserted {
                    result.append(HashedContact(hash: hash, displayName: name))
                }
            }
        }
        return result
    }

    static func hash(_ value: String) -> String {
        let key = SymmetricKey(data: Data(AppConfig.contactsPepper.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }
}

import Contacts
import CryptoKit
import Foundation

/// A contact's hashed phone number or email, with the name from the address book for display.
struct HashedContact {
    let hash: String
    let displayName: String
}

/// Reads the address book and hashes every phone number and email on the phone.
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

    func hashedContacts(limit: Int = 5000) throws -> [HashedContact] {
        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var result: [HashedContact] = []
        var seen = Set<String>()
        try store.enumerateContacts(with: request) { contact, stop in
            let name = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            var values: [String] = contact.phoneNumbers.compactMap { Self.normalizePhone($0.value.stringValue) }
            values += contact.emailAddresses.map { String($0.value).lowercased().trimmingCharacters(in: .whitespaces) }
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

    /// E.164 for US numbers: "(561) 555-0142" → "+15615550142". Anything unrecognized is skipped.
    static func normalizePhone(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        if raw.hasPrefix("+"), digits.count >= 10 { return "+" + digits }
        if digits.count == 10 { return "+1" + digits }
        if digits.count == 11, digits.hasPrefix("1") { return "+" + digits }
        return nil
    }

    static func hash(_ value: String) -> String {
        let key = SymmetricKey(data: Data(AppConfig.contactsPepper.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }
}

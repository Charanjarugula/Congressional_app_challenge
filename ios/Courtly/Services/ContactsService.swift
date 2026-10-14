import Contacts
import Foundation

/// Asks for contacts access. Matching against Courtly players happens in the backend
/// integration using hashed phone numbers; until then the people list uses sample data.
struct ContactsService {
    func requestAccess() async -> Bool {
        let store = CNContactStore()
        return await withCheckedContinuation { continuation in
            store.requestAccess(for: .contacts) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }
}

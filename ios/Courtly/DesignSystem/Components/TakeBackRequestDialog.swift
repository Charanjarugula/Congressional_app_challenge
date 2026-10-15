import SwiftUI

/// Someone the viewer sent a friend request to, about to be asked whether to take it back.
struct PendingFriendRequest: Identifiable, Equatable {
    let id: UUID
    let firstName: String
}

extension View {
    /// One question everywhere a "Requested" button takes a friend request back,
    /// so a stray tap never quietly withdraws it.
    func takeBackRequestDialog(_ pending: Binding<PendingFriendRequest?>, perform: @escaping (UUID) -> Void) -> some View {
        confirmationDialog(
            "Cancel your friend request to \(pending.wrappedValue?.firstName ?? "them")?",
            isPresented: Binding(get: { pending.wrappedValue != nil }, set: { if !$0 { pending.wrappedValue = nil } }),
            titleVisibility: .visible,
            presenting: pending.wrappedValue
        ) { request in
            Button("Cancel request", role: .destructive) { perform(request.id) }
            Button("Keep it", role: .cancel) {}
        }
    }
}

import SwiftUI

/// Where a tap inside a tab can go. Payloads are ids so routes stay small and hashable.
enum AppRoute: Hashable {
    case hit(UUID)
    case request(UUID)
    case chat(UUID)
    case groupInfo(UUID)
    case player(UUID, hitID: UUID? = nil)
    case addFriends
    case newGroup
    case account
    case blockedPlayers
}

/// Pushes screens onto the current tab's stack from anywhere in its tree.
struct NavigateAction {
    var push: (AppRoute) -> Void = { _ in }
    var replaceTop: (AppRoute) -> Void = { _ in }
    var pop: () -> Void = {}

    func callAsFunction(_ route: AppRoute) { push(route) }
}

extension EnvironmentValues {
    @Entry var navigate = NavigateAction()
}

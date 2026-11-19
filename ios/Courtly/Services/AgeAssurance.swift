import SwiftUI
import UIKit
#if canImport(DeclaredAgeRange)
import DeclaredAgeRange
#endif

/// Apple's Declared Age Range check (Texas App Store Accountability Act and similar laws).
/// Where the law applies (iOS 26.2+, region and account eligible), Apple tells us whether the person
/// is 18 or older; Courtly is 18+, so anyone younger is stopped. Everywhere else nothing is asked:
/// the App Store's 18+ rating covers it, and Courtly never asks for a date of birth.
enum AgeAssurance {
    /// Courtly is for adults: players arrange to meet in person, so the app is rated 18+.
    static let minimumAge = 18

    enum Result: Hashable {
        /// Apple confirmed 18 or older.
        case adult
        /// Apple says under 18: no account.
        case minor
        /// The law doesn't apply here, this iOS can't ask, or Apple couldn't answer: nothing to check.
        case notRequired
        /// The law applies but Apple didn't give an answer (declined or unavailable): ask again.
        case mustConfirm

        /// Sign-up carries on without showing anything.
        var letsThrough: Bool { self == .adult || self == .notRequired }
    }

    @MainActor
    static func check() async -> Result {
        #if canImport(DeclaredAgeRange)
        guard #available(iOS 26.2, *) else { return .notRequired }
        // Apple's own answer to "does age assurance apply to this person" decides. (The regulatory
        // feature list alone isn't enough: the simulator lists it while saying the person isn't eligible.)
        guard (try? await AgeRangeService.shared.isEligibleForAgeFeatures) == true else { return .notRequired }
        guard let presenter = topViewController() else { return .notRequired }
        do {
            switch try await AgeRangeService.shared.requestAgeRange(ageGates: minimumAge, in: presenter) {
            case .sharing(let range):
                if let lower = range.lowerBound, lower >= minimumAge { return .adult }
                return .minor   // no lower bound means below the gate
            case .declinedSharing:
                return .mustConfirm   // where the law applies, a declined check doesn't let anyone through
            @unknown default:
                return .mustConfirm
            }
        } catch {
            // Apple couldn't answer (service unavailable, no Apple Account): never lock everyone out on an outage.
            return .notRequired
        }
        #else
        return .notRequired
        #endif
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var controller = scene?.keyWindow?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }
}


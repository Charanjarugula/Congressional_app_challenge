import Foundation

/// Plain-English text for the short codes database functions raise.
enum BackendMessages {
    static func text(for code: String) -> String {
        switch code {
        case "hit_full", "spot_taken": "That spot was just taken."
        case "hit_closed", "invite_closed": "This hit isn’t open anymore."
        case "hit_not_found", "invite_not_found": "This hit is no longer available."
        case "hit_started": "The hit has already started."
        case "hit_not_played": "You can answer this once the hit has been played."
        case "already_requested": "You already asked to join."
        case "already_declined": "The host already answered this one."
        case "overlaps_hit": "You already have a hit at that time."
        case "attendance_closed": "The window to answer this has closed."
        case "already_in": "You’re already in this hit."
        case "request_not_found", "request_closed": "This request was already answered."
        case "not_host": "Only the host can do that."
        case "host_cannot_leave": "Hosts cancel the hit instead of leaving it."
        case "not_a_player", "not_a_member", "not_for_you": "You’re not part of this one."
        case "starts_in_past": "Pick a time at least 15 minutes from now."
        case "too_far_ahead": "Hits can be planned up to 30 days ahead."
        case "invalid_spots": "Choose between 1 and 7 spots."
        case "invalid_duration": "Choose 60, 90 or 120 minutes."
        case "invalid_expiry": "That invite would close after the hit starts."
        case "court_not_found": "Pick a court first."
        case "missing_name": "Add a name first."
        case "invalid_photo": "That photo couldn’t be used. Pick it again."
        case "not_friends": "Add them as a friend to message them."
        case "player_unavailable": "That player isn’t available."
        case "empty_message": "Type a message first."
        case "message_too_long": "Keep messages under 2,000 characters."
        case "filtered": "That message can’t be sent."
        case "rate_limited": "Slow down a little and try again."
        case "onboarding_incomplete", "missing_birthday", "missing_level", "missing_formats", "missing_location": "Finish setting up your profile first."
        case "underage": "Courtly is for players 18 and older."
        case "age_required": "Add your birthday first."
        case "too_long": "That’s too long. Shorten it and try again."
        case "invalid_token": "Notifications couldn’t be set up on this device."
        case "missing_members": "Pick at least one friend."
        case "not_a_group": "That isn’t a group chat."
        case "cannot_add_self", "cannot_block_self", "cannot_report_self": "That’s you."
        case "invalid_radius", "invalid_visibility", "invalid_mask": "That choice isn’t available."
        case "not_signed_in": "You’re signed out."
        case "no_profile": "We couldn’t find your profile. Sign in again."
        case "account_suspended": "This account has been suspended."
        case "account_deleted": "This account was deleted."
        case "too_many_hashes": "That’s more contacts than we can check at once."
        case "invalid_time_zone": "That time zone isn’t recognised."
        default: code.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

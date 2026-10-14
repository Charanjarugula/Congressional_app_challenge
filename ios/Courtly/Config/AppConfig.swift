import Foundation

/// Environment-specific values. Debug builds talk to courtly-dev, release builds to courtly-prod.
/// The key below is the project's public client key (Project Settings → API Keys). Both projects
/// were created with the new key format, so use the `sb_publishable_…` key there, not the legacy
/// `eyJ…` one; row-level security protects the data either way.
enum AppConfig {
    #if DEBUG
    static let supabaseURL = URL(string: "https://letuvtazmtjkvivattfy.supabase.co")!
    static let supabaseAnonKey = "sb_publishable_2om3uiw5HBgQxNaBFEUZYA_g8Wfkxp6"
    static let apnsEnvironment = "sandbox"
    #else
    static let supabaseURL = URL(string: "https://jrlocgfyskutnusscenf.supabase.co")!
    static let supabaseAnonKey = "sb_publishable_gt6oatTEPQt7rP3xHjHpKw_vPL2jtI3"
    static let apnsEnvironment = "production"
    #endif

    static let bundleID = "com.courtly.ios"

    /// Google OAuth iOS client id ("1234-abc.apps.googleusercontent.com"). Empty until the Google Cloud
    /// project exists; the Google button explains that it is not set up yet.
    static let googleClientID = ""

    /// Key used to hash phone numbers and emails on the phone before matching. Only hashes are sent.
    static let contactsPepper = "courtly-contacts-v1"

    /// App Review signs in with this address and a fixed code, which is that account's password.
    static let reviewerEmail = "reviewer@courtly.app"

    /// The `site` folder deployed on Vercel. CI's config check fails while this is still the placeholder.
    static let siteURL = URL(string: "https://courtly-sage.vercel.app")!
    static var privacyURL: URL { siteURL.appending(path: "privacy") }
    static var termsURL: URL { siteURL.appending(path: "terms") }
    static let supportEmail = "courtly.support@gmail.com"
}

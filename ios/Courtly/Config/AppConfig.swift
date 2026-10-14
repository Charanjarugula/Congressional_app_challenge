import Foundation

/// Environment-specific values. Debug builds talk to courtly-dev, release builds to courtly-prod.
/// The anon key is a public client key by design; row-level security protects the data.
enum AppConfig {
    #if DEBUG
    static let supabaseURL = URL(string: "https://letuvtazmtjkvivattfy.supabase.co")!
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxldHV2dGF6bXRqa3ZpdmF0dGZ5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE5NTA5NTYsImV4cCI6MjEwNzUyNjk1Nn0.yOJ36Knjz5SrnCJTlMze28Vbkbfd-XSZirwexanaxa8"
    static let apnsEnvironment = "sandbox"
    #else
    static let supabaseURL = URL(string: "https://jrlocgfyskutnusscenf.supabase.co")!
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpybG9jZ2Z5c2t1dG51c3NjZW5mIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE5NTEwMzYsImV4cCI6MjEwNzUyNzAzNn0.jOQERNP3OuIehtTxt-gellqX1SvIjnFfLKH7sFs2wKg"
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
}

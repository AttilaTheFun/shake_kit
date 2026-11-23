import Foundation

/// What ShakeKit signs in with and how it reports, from the host's Info.plist
/// (stamped by its CI) or given in code.
public struct ShakeKitConfiguration: Sendable, Equatable {
    /// The OAuth App ShakeKit signs in with when the host names none: the
    /// owner's `logan-shire-shake` (docs/Design.md, section 5).
    public static let defaultClientID = "Ov23liV9P5ku0ntejoEc"
    /// What its token is asked to reach: `public_repo` for a public
    /// repository, `repo` for a private one.
    public static let defaultScope = "public_repo"

    public static let clientIDKey = "ShakeKitClientID"
    public static let scopeKey = "ShakeKitScope"

    public var clientID: String
    public var scope: String
    /// The keychain service ShakeKit's own sign-in is kept under, in the
    /// app's default access group.
    public var keychainService: String
    /// How far back the logs go.
    public var logWindow: TimeInterval
    /// The most log text put in the issue, newest kept. GitHub takes 65,536
    /// characters in a body.
    public var logLimit: Int
    /// The log subsystems included; empty for the app's bundle id alone.
    public var logSubsystems: [String]
    /// The labels the issue gets.
    public var labels: [String]
    /// Extra patterns (regular expressions) blanked out of the logs.
    public var redactions: [String]

    public init(
        clientID: String = Self.defaultClientID,
        scope: String = Self.defaultScope,
        keychainService: String = "shake-kit.sign-in",
        logWindow: TimeInterval = 15 * 60,
        logLimit: Int = 40_000,
        logSubsystems: [String] = [],
        labels: [String] = ["shake-report"],
        redactions: [String] = []
    ) {
        self.clientID = clientID
        self.scope = scope
        self.keychainService = keychainService
        self.logWindow = logWindow
        self.logLimit = logLimit
        self.logSubsystems = logSubsystems
        self.labels = labels
        self.redactions = redactions
    }

    /// The configuration an Info.plist gives: its `ShakeKitClientID` and
    /// `ShakeKitScope` where set (a value a build didn't fill in, `$(…)`,
    /// counts as none), the defaults otherwise.
    public static func from(info: [String: Any]?) -> ShakeKitConfiguration {
        func value(_ key: String) -> String? {
            guard let text = (info?[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty, !text.hasPrefix("$(") else { return nil }
            return text
        }
        var configuration = ShakeKitConfiguration()
        if let clientID = value(clientIDKey) { configuration.clientID = clientID }
        if let scope = value(scopeKey) { configuration.scope = scope }
        return configuration
    }

    /// The main bundle's.
    public static var main: ShakeKitConfiguration { from(info: Bundle.main.infoDictionary) }
}

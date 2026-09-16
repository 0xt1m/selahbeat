import Foundation

/// What this copy of the app is, for the About screen and for support requests.
///
/// Read from the bundle rather than hard-coded: the release pipeline stamps
/// both numbers in at build time, so anything written here by hand would drift.
public enum AppInfo {
    public static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    public static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    /// "1.1.5 (247)" - the build number is what support needs to identify an
    /// exact binary, since several builds can share a version.
    public static var displayVersion: String { "\(version) (\(build))" }
}

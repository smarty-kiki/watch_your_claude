import Foundation

/// Resource lookup that works both in the packaged .app and under `swift run`.
///
/// The SPM-generated `Bundle.module` accessor only looks for its resource bundle
/// at the app bundle root (which `codesign` rejects as unsealed contents) or at
/// an absolute build path baked in at compile time, so a packaged app crashes on
/// access. Instead, resources are kept loose in Contents/Resources where
/// Bundle.main finds them, with a fallback to the SPM bundle for `swift run`.
enum AppResources {
    static func url(forResource name: String, withExtension ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        let bundleName = "WatchYourClaude_WatchYourClaude.bundle"
        let bundleCandidates = [
            Bundle.main.bundleURL.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(bundleName),
        ]
        for candidate in bundleCandidates {
            if let bundle = Bundle(url: candidate),
               let url = bundle.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        return nil
    }
}

import Foundation

enum SeedPolicy {
    /// First line of a seed file the app may refresh. Deleting it keeps a user's own copy.
    static let managedMarker = "# managed-by: typeless-rev"

    /// The first release's `default.custom.yaml`, written before the marker existed. A copy that
    /// is still exactly this was never edited, so it is refreshed like a managed file.
    static let legacyDefaultCustom = """
        # Typeless-Rev defaults. Copied into the Rime user data directory on first run
        # and never overwritten afterwards, so edit it freely.
        patch:
          schema_list:
            - schema: luna_pinyin_simp
            - schema: luna_pinyin

        """

    /// Whether the bundled seed file should be written over what is in the user data directory.
    /// A missing file is always written; an existing one only when it is still managed and stale.
    static func shouldInstall(existing: String?, bundled: String) -> Bool {
        guard let existing else { return true }
        return (isManaged(existing) || existing == legacyDefaultCustom) && existing != bundled
    }

    static func isManaged(_ contents: String) -> Bool {
        contents.prefix(while: { $0 != "\n" }).trimmingCharacters(in: .whitespaces) == managedMarker
    }
}

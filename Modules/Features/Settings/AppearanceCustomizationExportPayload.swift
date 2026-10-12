import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// The whole customised look as one `.yuedustyle` for 導出主題's `ShareLink`: themes,
/// page backgrounds, bottom-tab icons, launch images and the reading backgrounds,
/// every image embedded — see `AppearanceCustomizationBundle`.
///
/// Holds only the cheap snapshot (values and file names). Every disk read and
/// base64 happens inside the transfer closure, because this backs a visible row
/// and the finished bundle can run to tens of megabytes.
struct AppearanceCustomizationExportPayload: Transferable {
    /// Filename including the extension. Build it with `filename(for:)`.
    let filename: String
    let snapshot: AppearanceCustomizationSnapshot

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .yueduReaderStyle) { payload in
            let bundle = AppearanceCustomizationBundle(snapshot: payload.snapshot)
            let stylePayload = try ReaderStylePackagePayload.encode(
                bundle,
                kind: .appearance,
                assetIDs: payload.snapshot.readerStyleAssetIDs
            )
            let data = try await ReaderStylePackage.export(
                stylePayload,
                assetStore: .shared
            )
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(payload.filename)
            try data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }

    /// The theme's name as a filename — what 導出主題 names the file after. Names are
    /// user-entered and can arrive in an imported pack, so path separators and newlines
    /// are replaced.
    static func filename(for label: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.newlines)
        let cleaned = label
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleaned.isEmpty ? "appearance" : String(cleaned.prefix(60))
        return "\(base).yuedustyle"
    }
}

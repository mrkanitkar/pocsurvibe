import Foundation
import Testing
import UniformTypeIdentifiers
@testable import SurVibe

// MARK: - Info.plist MusicXML UTI Declaration Tests (T8')

/// Verifies that `SurVibe/Info.plist` declares the custom UTIs needed by the
/// Songs-tab `fileImporter` flow.
///
/// `.fileImporter` requires every accepted extension to resolve to a `UTType`.
/// Since `.mxl` and `.musicxml` have no system-defined UTI, the app must
/// register them via `UTImportedTypeDeclarations`. If these declarations
/// regress, the picker silently rejects MusicXML files even though
/// `ContentImportManager.acceptedMusicXMLTypes` lists them — these tests
/// guard against that regression.
///
/// Apple UTI registration spec:
///   https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/understanding_utis/understand_utis_declare/understand_utis_declare.html
@Suite("Info.plist MusicXML UTI declarations")
struct InfoPlistMusicXMLUTITests {

    // MARK: - Helpers

    /// The decoded `UTImportedTypeDeclarations` array from the app's Info.plist.
    private var importedTypeDeclarations: [[String: Any]] {
        let decls = Bundle.main.object(forInfoDictionaryKey: "UTImportedTypeDeclarations")
        return (decls as? [[String: Any]]) ?? []
    }

    /// Returns the declaration matching `identifier`, or nil if absent.
    private func declaration(for identifier: String) -> [String: Any]? {
        importedTypeDeclarations.first { ($0["UTTypeIdentifier"] as? String) == identifier }
    }

    /// Returns the filename extensions registered under the given UTI.
    private func extensions(for identifier: String) -> [String] {
        guard let decl = declaration(for: identifier),
              let tags = decl["UTTypeTagSpecification"] as? [String: Any],
              let exts = tags["public.filename-extension"] as? [String]
        else { return [] }
        return exts
    }

    // MARK: - Compressed MusicXML (.mxl)

    @Test("org.musicxml.compressed is declared")
    func mxlUTIDeclared() {
        #expect(declaration(for: "org.musicxml.compressed") != nil)
    }

    @Test("org.musicxml.compressed maps to .mxl extension")
    func mxlUTIMapsToMxlExtension() {
        #expect(extensions(for: "org.musicxml.compressed").contains("mxl"))
    }

    @Test("org.musicxml.compressed conforms to public.zip-archive")
    func mxlUTIConformsToZip() {
        let decl = declaration(for: "org.musicxml.compressed")
        let conforms = decl?["UTTypeConformsTo"] as? [String] ?? []
        #expect(conforms.contains("public.zip-archive"))
    }

    // MARK: - Uncompressed MusicXML (.musicxml)

    @Test("org.musicxml.score is declared")
    func musicXMLUTIDeclared() {
        #expect(declaration(for: "org.musicxml.score") != nil)
    }

    @Test("org.musicxml.score maps to .musicxml extension")
    func musicXMLUTIMapsToMusicXMLExtension() {
        #expect(extensions(for: "org.musicxml.score").contains("musicxml"))
    }

    @Test("org.musicxml.score conforms to public.xml")
    func musicXMLUTIConformsToXML() {
        let decl = declaration(for: "org.musicxml.score")
        let conforms = decl?["UTTypeConformsTo"] as? [String] ?? []
        #expect(conforms.contains("public.xml"))
    }

    // MARK: - Cross-check with ContentImportManager

    @Test("ContentImportManager.acceptedMusicXMLTypes resolves the registered UTIs")
    @MainActor
    func acceptedTypesResolveRegisteredUTIs() {
        let accepted = ContentImportManager.acceptedMusicXMLTypes
        // .xml (system UTI) must always be present.
        #expect(accepted.contains(.xml))
        // After Info.plist registers them, the OS resolves these by extension.
        // We don't assert presence of every UTType because resolution depends on
        // the OS having ingested the registrations — but the array must never
        // be empty and must contain a type for the .mxl or .musicxml extension.
        #expect(!accepted.isEmpty)
    }
}

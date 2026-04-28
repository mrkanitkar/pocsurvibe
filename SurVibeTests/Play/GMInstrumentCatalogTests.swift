import Testing

@testable import SurVibe

struct GMInstrumentCatalogTests {
    @Test
    func allOneHundredTwentyEightProgramsHaveNonEmptyNames() {
        for program in UInt8(0)...UInt8(127) {
            let name = GMInstrumentCatalog.name(for: program)
            #expect(!name.isEmpty, "Program \(program) has empty name")
        }
    }

    @Test
    func sixteenCategoriesEachWithEightInstruments() {
        let categories = GMInstrumentCategory.allCases
        #expect(categories.count == 16)
        for category in categories {
            let entries = GMInstrumentCatalog.entries(in: category)
            #expect(
                entries.count == 8,
                "\(category) has \(entries.count) entries (expected 8)"
            )
        }
    }

    @Test
    func programZeroIsAcousticGrand() {
        #expect(GMInstrumentCatalog.name(for: 0) == "Acoustic Grand Piano")
    }

    @Test
    func program127IsGunshot() {
        #expect(GMInstrumentCatalog.name(for: 127) == "Gunshot")
    }

    @Test
    func categoryForProgram24IsGuitar() {
        #expect(GMInstrumentCatalog.category(for: 24) == .guitar)
    }
}

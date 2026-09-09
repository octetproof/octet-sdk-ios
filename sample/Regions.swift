import Foundation

// The country picker's data — the ISO 3166-1 alpha-2 list, localized to the
// device and sorted by display name. Extracted from the original single-screen
// sample unchanged so the Generate screen keeps the same region choices.

/// Display row in the country picker. `id` is the ISO alpha-2 code — the shape
/// `OctetRegion.country(isoCode:)` accepts.
struct Country: Identifiable, Hashable {
    let id: String   // ISO alpha-2
    let name: String
}

/// ISO 3166-1 codes for dependent territories / overseas departments — dropped
/// from the picker. Diplomatically-contested edges are kept, not asserted here.
private let dependentTerritoryCodes: Set<String> = [
    "AQ", "AX", "BV", "CC", "CX", "EH", "FK", "FO", "GF", "GG",
    "GI", "GL", "GP", "GS", "GU", "HK", "HM", "IM", "IO", "JE",
    "KY", "MF", "MO", "MP", "MQ", "MS", "NC", "NF", "PF", "PM",
    "PN", "PR", "RE", "SH", "SJ", "TC", "TF", "TK", "UM", "VG",
    "VI", "WF", "YT",
]

/// Full alpha-2 list minus dependent territories, localized + name-sorted.
/// Pulled from `Locale.Region.isoRegions` so there's no decaying hardcoded table.
let demoCountries: [Country] = {
    let locale = Locale.current
    return Locale.Region.isoRegions
        .map { $0.identifier }
        .filter { iso in iso.count == 2 && !dependentTerritoryCodes.contains(iso) }
        .compactMap { iso -> Country? in
            guard let name = locale.localizedString(forRegionCode: iso) else { return nil }
            return Country(id: iso, name: name)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}()

/// Default selection — device region, else US, else first entry.
let defaultCountry: Country = {
    let deviceCode = Locale.current.region?.identifier ?? ""
    return demoCountries.first(where: { $0.id == deviceCode })
        ?? demoCountries.first(where: { $0.id == "US" })
        ?? demoCountries[0]
}()

/// Localized country name for an ISO code (for imported proofs whose envelope
/// only carries the code), falling back to the code itself.
func countryName(for iso: String) -> String {
    Locale.current.localizedString(forRegionCode: iso) ?? iso
}

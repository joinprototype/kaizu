import Foundation

extension ArcImport {
    private typealias Candidate = (space: SpaceRecord, sharedAddresses: Int)

    static func matchDestinations(
        _ sidebar: ArcSidebar, profiles: [ProfileRecord], spaces: [SpaceRecord]
    ) -> (spaces: [Int: SpaceRecord], profiles: [String: UUID]) {
        let byName = Dictionary(grouping: spaces) { $0.name.folding(options: .caseInsensitive, locale: nil) }
        let candidates: [[Candidate]] = sidebar.spaces.map { arc in
            let named = byName[arc.name.folding(options: .caseInsensitive, locale: nil)] ?? []
            guard named.count > 1 else { return named.map { ($0, 0) } }
            let sourceTabs = Set((arc.pinned.tabs + arc.today).map(\.url))
            let sourceFavorites = Set((sidebar.favorites[arc.profile] ?? []).map(\.url))
            return named.map { space -> Candidate in
                let tabs = (space.pinned.tabs + space.today).compactMap { $0.pinnedURL ?? $0.url }
                let favorites = profiles.first { $0.id == space.profileID }?.favorites ?? []
                let score = sourceTabs.intersection(tabs).count
                    + sourceFavorites.intersection(favorites.compactMap { $0.pinnedURL ?? $0.url }).count
                return (space, score)
            }.sorted { $0.sharedAddresses > $1.sharedAddresses } // Stable ties keep sidebar order.
        }

        var profileIDs = inferredProfiles(sidebar, candidates: candidates)
        let defaultSpaces = sidebar.spaces.indices.filter { sidebar.spaces[$0].profile == ArcSidebar.defaultProfile }
        if !defaultSpaces.isEmpty, profileIDs[ArcSidebar.defaultProfile] == nil {
            let reserved = Set(profileIDs.values)
            let existing = defaultSpaces.lazy.compactMap { index in
                candidates[index].first { !reserved.contains($0.space.profileID) }?.space
            }.first
            profileIDs[ArcSidebar.defaultProfile] = (existing ?? spaces.first { !reserved.contains($0.profileID) })?.profileID
        }

        var matches: [Int: SpaceRecord] = [:]
        var taken: Set<UUID> = []
        for (index, arc) in sidebar.spaces.enumerated() {
            let match = candidates[index].first { candidate in
                let space = candidate.space
                guard !taken.contains(space.id) else { return false }
                if let id = profileIDs[arc.profile] { return space.profileID == id }
                return !profileIDs.values.contains(space.profileID)
            }
            guard let space = match?.space else { continue }
            matches[index] = space
            taken.insert(space.id)
            profileIDs[arc.profile] = space.profileID
        }
        return (matches, profileIDs)
    }

    /// Resolve repeated space names across the whole export before an earlier row can claim an account.
    private static func inferredProfiles(_ sidebar: ArcSidebar, candidates: [[Candidate]]) -> [String: UUID] {
        var claims: [String: UUID] = [:]
        var needsDisambiguation = Set<String>()
        for (profile, rows) in Dictionary(grouping: sidebar.spaces.indices, by: { sidebar.spaces[$0].profile }) {
            var sharedOwners: Set<UUID>?
            var addressMatches = Set<UUID>()
            for row in rows {
                let named = candidates[row]
                guard let best = named.first else { continue }
                let owners = Set(named.map { $0.space.profileID })
                sharedOwners = sharedOwners?.intersection(owners) ?? owners
                guard owners.count > 1 else { continue }
                needsDisambiguation.insert(profile)
                if best.sharedAddresses > 0 {
                    let leaders = named.prefix { $0.sharedAddresses == best.sharedAddresses }
                    let bestOwners = Set(leaders.map { $0.space.profileID })
                    if bestOwners.count == 1 { addressMatches.formUnion(bestOwners) }
                }
            }
            // A known pin or favorite in one Inbox outweighs a coincidentally named sibling.
            let owners = addressMatches.isEmpty ? sharedOwners : addressMatches
            if let owners, owners.count == 1 { claims[profile] = owners.first }
        }
        // A destination claimed by two source profiles still needs ordinary one-to-one matching.
        let claimants = Dictionary(grouping: claims.values, by: { $0 })
        return claims.filter { needsDisambiguation.contains($0.key) && claimants[$0.value]?.count == 1 }
    }
}

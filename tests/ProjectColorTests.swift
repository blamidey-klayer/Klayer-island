import Foundation

/// An agent's colour (IslandConst.colorForProject): the fixed colour of a known project, else one of
/// the four fallback colours, the same at every launch (0.3.6). Before, the fallback came from
/// `hashValue`, seeded per process: an unknown agent changed colour at each launch, and `abs` of
/// `Int.min` trapped.
@main
enum ProjectColorTests {
    static func main() {
        let cases: [(String, () -> Void)] = [
            ("the_hash_is_fnv1a_64", theHashIsFNV1a64),
            ("an_unknown_project_gets_the_same_colour_at_every_launch", anUnknownProjectGetsTheSameColour),
            ("case_and_outer_spaces_do_not_change_the_colour", caseAndSpacesDoNotChangeTheColour),
            ("known_projects_keep_their_colour", knownProjectsKeepTheirColour),
            ("a_name_with_two_known_projects_always_gets_the_same_one", aNameWithTwoKnownProjects),
            ("every_fallback_is_one_of_the_four", everyFallbackIsOneOfTheFour),
        ]
        for (name, run) in cases {
            run()
            print("  ok  \(name)")
        }
        print("Project colours: \(cases.count) cases passed")
    }

    /// The published FNV-1a 64-bit test vectors, and two of our own computed apart (Python).
    static func theHashIsFNV1a64() {
        precondition(IslandConst.stableHash("") == 0xcbf2_9ce4_8422_2325, "offset basis for the empty text")
        precondition(IslandConst.stableHash("a") == 0xaf63_dc4c_8601_ec8c, "the published vector for « a »")
        precondition(IslandConst.stableHash("essai-a") == 0x94f9_391d_3d36_92a6, "essai-a")
        precondition(IslandConst.stableHash("données") == 0x6dff_91af_d97e_6bd4, "over the UTF-8 bytes")
    }

    /// Fixed expectations: a per-process hash would match all five only by chance (1 in 1 024).
    static func anUnknownProjectGetsTheSameColour() {
        let expected: [(String, String)] = [
            ("mon-projet", "#60A5FA"),
            ("essai-a", "#60A5FA"),
            ("essai-b", "#E879F9"),
            ("ventes q4", "#E879F9"),
            ("données", "#22C55E"),
        ]
        for (name, colour) in expected {
            let got = IslandConst.colorForProject(name)
            precondition(got == colour, "\(name): \(colour) expected, got \(got)")
        }
    }

    static func caseAndSpacesDoNotChangeTheColour() {
        precondition(IslandConst.colorForProject("Ventes Q4") == IslandConst.colorForProject("ventes q4"),
                     "the case does not count")
        precondition(IslandConst.colorForProject("  essai-b ") == IslandConst.colorForProject("essai-b"),
                     "outer spaces do not count")
    }

    static func knownProjectsKeepTheirColour() {
        precondition(IslandConst.colorForProject("Korus") == "#FF5A4E", "exact name")
        precondition(IslandConst.colorForProject("korus-api") == "#FF5A4E", "a name that starts with a project")
        precondition(IslandConst.colorForProject("Notch Buddy") == "#EC4899", "with a space")
    }

    /// « korus klayer » contains « klayer » and « korus »: the keys are tried in sorted order, so it is
    /// always « klayer », where the dictionary's own order changed with each launch.
    static func aNameWithTwoKnownProjects() {
        precondition(IslandConst.colorForProject("korus klayer") == "#3E7280", "klayer, before korus")
    }

    static func everyFallbackIsOneOfTheFour() {
        for i in 0..<200 {
            let colour = IslandConst.colorForProject("projet-\(i)")
            precondition(IslandConst.fallbackColors.contains(colour), "\(colour) is not a fallback colour")
        }
    }
}

/// IslandTypes.swift (compiled here for `IslandConst`) names `EyeShape`, which BotEngine.swift
/// defines with SwiftUI. This stand-in lets it build with Foundation only.
enum EyeShape: Equatable {}

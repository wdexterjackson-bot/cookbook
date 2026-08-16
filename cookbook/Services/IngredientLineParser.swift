//
//  IngredientLineParser.swift
//  cookbook
//
//  Deterministic (non-AI) ingredient-line parsing, for the two paths that
//  never go through FoundationModelsLineImportService: importing directly
//  from a Discover result (CreateEditRecipeView's .importing case), and
//  RecipeQuantityStandardizer retrofitting a recipe whose ingredients
//  never got split into quantity/unit/name in the first place. Reuses
//  LeadingQuantityToken for the actual number-parsing rather than
//  duplicating it, and returns the same ParsedIngredientLine shape the AI
//  import path uses, so both paths — and Standardize, which is meant to
//  "always incorporate the rule from import" — share one definition of
//  what a well-formed ingredient line looks like.
//

import Foundation

enum IngredientLineParser {
    /// A leading bullet/list-marker glyph a source document might prefix
    /// each ingredient with — stripped before any number parsing, since a
    /// bullet sitting directly against a quantity ("•7 Bananas") would
    /// otherwise fail to parse as a number at all, and a plain "." bullet
    /// directly against a digit (".7 Bananas") would otherwise silently
    /// misparse as the decimal 0.7 — the exact "bullet point reads as a
    /// decimal" bug reported 2026-08-15.
    private static let bulletCharacters: Set<Character> = ["•", "◦", "▪", "‣", "·", "∙", "●", "▸", "○", "■", "-", "–", "—", "*", "."]

    private static func strippingLeadingBullet(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespaces)
        guard let first = result.first, bulletCharacters.contains(first) else { return result }
        // Only a bullet if it's a standalone marker — either the whole
        // token (followed by whitespace) or trailing content that isn't
        // itself a digit (so "-2 potatoes" and ".7 cups" don't get
        // treated as a real negative/decimal quantity here; those are rare
        // in a recipe context and this app's own commonUnits/UI never
        // produces a leading '-' or bare '.' on a legitimate amount).
        result.removeFirst()
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Parses one raw ingredient line into name/quantity/unit/range,
    /// matching how `RecipeFileImportCoordinator.displayText(for:)`
    /// composes them back together. Always returns a value — `quantity`
    /// and `unit` are simply nil when nothing recognizable was found, and
    /// `name` falls back to the (bullet-stripped) line as typed.
    static func parse(_ rawLine: String, knownUnits: [String]) -> ParsedIngredientLine {
        let withoutBullet = strippingLeadingBullet(rawLine)
        guard !withoutBullet.isEmpty else {
            return ParsedIngredientLine(name: rawLine.trimmingCharacters(in: .whitespaces), quantity: nil, unit: nil)
        }

        if let ranged = parseRange(withoutBullet, knownUnits: knownUnits) {
            return ranged
        }
        return parseSingle(withoutBullet, knownUnits: knownUnits)
    }

    /// "7 Bananas to 8 Bananas", "1/4 to 1/2 tsp cinnamon" — anything of
    /// the shape "<quantity> [text] to <quantity> [text]". Returns nil
    /// (not a range) unless a real quantity is found on *both* sides of
    /// " to " — otherwise a line that just happens to contain the word
    /// "to" for some other reason (an ingredient name, a prep note) would
    /// be misread as a range.
    private static func parseRange(_ text: String, knownUnits: [String]) -> ParsedIngredientLine? {
        guard let toRange = text.range(of: " to ", options: [.caseInsensitive]) else { return nil }
        let beforeTo = String(text[text.startIndex..<toRange.lowerBound])
        let afterTo = String(text[toRange.upperBound...])

        guard let first = LeadingQuantityToken.parse(from: beforeTo),
              let second = LeadingQuantityToken.parse(from: afterTo)
        else { return nil }

        let remainder1 = String(beforeTo.trimmingCharacters(in: .whitespaces).dropFirst(first.matchedText.count)).trimmingCharacters(in: .whitespaces)
        let remainder2 = String(afterTo.trimmingCharacters(in: .whitespaces).dropFirst(second.matchedText.count)).trimmingCharacters(in: .whitespaces)

        // The fuller remainder (usually the second — "1/2 tsp cinnamon"
        // carries the unit and name, "1/4" alone carries neither) is
        // where the real unit/name live; fall back to the other side only
        // if it's empty.
        let (unit, name) = splitUnitAndName(remainder2.isEmpty ? remainder1 : remainder2, knownUnits: knownUnits)

        let smallerIsFirst = first.value <= second.value
        let smallerToken = smallerIsFirst ? first : second
        let largerToken = smallerIsFirst ? second : first

        return ParsedIngredientLine(
            name: name,
            quantity: smallerToken.value,
            unit: unit,
            rangeUpperText: largerToken.matchedText
        )
    }

    private static func parseSingle(_ text: String, knownUnits: [String]) -> ParsedIngredientLine {
        guard let leading = LeadingQuantityToken.parse(from: text) else {
            return ParsedIngredientLine(name: text, quantity: nil, unit: nil)
        }
        let remainder = String(text.dropFirst(leading.matchedText.count)).trimmingCharacters(in: .whitespaces)
        let (unit, name) = splitUnitAndName(remainder, knownUnits: knownUnits)
        return ParsedIngredientLine(name: name, quantity: leading.value, unit: unit)
    }

    /// Common real-world abbreviations/misspellings — full home-cook
    /// reference table (2026-08-15) — normalized to their canonical unit
    /// (always one of `CreateEditRecipeView.commonUnits`) before the
    /// exact/plural match below runs, so e.g. a source file's "tblsp" or
    /// "fl.oz." ends up stored as "tbsp"/"fl oz" like every other amount
    /// in that unit, not left unrecognized. Keyed lowercase (looked up via
    /// `normalizedAlias`, which case-folds before checking here) — the one
    /// exception is "T" vs "t" (tablespoon vs teaspoon), a genuinely
    /// case-sensitive pair in common use, handled separately so it isn't
    /// silently merged into one meaning.
    private static let unitAliases: [String: String] = [
        // bag
        "bagg": "bag", "bags": "bag", "bg": "bag", "bg.": "bag", "bgs": "bag",
        // bottle
        "bot": "bottle", "botl": "bottle", "botls": "bottle", "bott": "bottle",
        "bottles": "bottle", "btl": "bottle", "btl.": "bottle", "btls": "bottle",
        // box
        "boxes": "box", "boxs": "box", "bx": "box", "bx.": "box", "bxs": "box",
        // bunch
        "bch": "bunch", "bchs": "bunch", "bnch": "bunch", "bu": "bunch",
        "bunches": "bunch", "bunchs": "bunch",
        // can
        "canned": "can", "cans": "can", "cn": "can", "cn.": "can", "cns": "can",
        "tin": "can", "tins": "can",
        // carton
        "cartn": "carton", "cartons": "carton", "ctn": "carton", "ctn.": "carton", "ctns": "carton",
        // clove
        "cl": "clove", "clov": "clove", "clove.": "clove", "cloves": "clove",
        "clv": "clove", "clvs": "clove", "clvs.": "clove",
        // container
        "cont": "container", "cont.": "container", "containers": "container",
        "containr": "container", "contnr": "container", "ctnr": "container", "ctnrs": "container",
        // cup
        "c": "cup", "c.": "cup", "cp": "cup", "cps": "cup", "cu": "cup",
        "cupful": "cup", "cupfuls": "cup", "cups": "cup",
        // dash
        "dash.": "dash", "dashes": "dash", "dashs": "dash", "ds": "dash", "ds.": "dash", "dsh": "dash",
        // dozen
        "doz": "dozen", "doz.": "dozen", "dozens": "dozen", "dozn": "dozen", "dozns": "dozen",
        "dz": "dozen", "dz.": "dozen",
        // drop
        "dp": "drop", "dp.": "drop", "drop.": "drop", "drops": "drop", "drp": "drop", "drps": "drop",
        // fl oz
        "fl ounce": "fl oz", "fl oz.": "fl oz", "fl ozs": "fl oz", "fl-oz": "fl oz",
        "fl. oz": "fl oz", "fl. oz.": "fl oz", "fl.oz.": "fl oz", "floz": "fl oz",
        "fluid ounce": "fl oz", "fluid ounces": "fl oz", "fluid oz": "fl oz", "fluid ozs": "fl oz",
        "fluidounce": "fl oz", "fluidounces": "fl oz", "fulid ounce": "fl oz",
        // gal
        "gal.": "gal", "gall": "gal", "gallon": "gal", "gallon.": "gal", "gallons": "gal",
        "galn": "gal", "galons": "gal", "gals": "gal", "gals.": "gal",
        // g
        "g.": "g", "gm": "g", "gm.": "g", "gms": "g", "gr": "g", "gr.": "g",
        "gram": "g", "gramm": "g", "gramms": "g", "grams": "g", "grm": "g", "grms": "g",
        // handful
        "hand full": "handful", "hand-full": "handful", "handfull": "handful",
        "handfulls": "handful", "handfuls": "handful",
        // jar
        "jarr": "jar", "jars": "jar", "jr": "jar", "jr.": "jar", "jrs": "jar",
        // kg
        "kg.": "kg", "kgram": "kg", "kgs": "kg", "kgs.": "kg", "kilo": "kg",
        "kilogram": "kg", "kilogramme": "kg", "kilogrammes": "kg", "kilograms": "kg", "kilos": "kg",
        // large
        "larg": "large", "large.": "large", "lg": "large", "lg.": "large", "lge": "large", "lrg": "large",
        // liter
        "l": "liter", "L": "liter", "L.": "liter", "leter": "liter", "liter.": "liter",
        "liters": "liter", "litre": "liter", "litres": "liter", "litres.": "liter",
        "litters": "liter", "ltr": "liter", "ltrs": "liter",
        // medium
        "md": "medium", "md.": "medium", "med": "medium", "med.": "medium",
        "medium.": "medium", "medm": "medium",
        // mg
        "mg.": "mg", "mgs": "mg", "miligram": "mg", "miligrams": "mg",
        "milligram": "mg", "milligramme": "mg", "milligrams": "mg",
        // mL
        "cc": "mL", "mililiter": "mL", "millileter": "mL", "milliliter": "mL",
        "milliliters": "mL", "millilitre": "mL", "millilitres": "mL", "millilitres.": "mL",
        "ml": "mL", "ml.": "mL", "mL.": "mL",
        // oz
        "oc": "oz", "ocs": "oz", "onz": "oz", "ounc": "oz", "ounce": "oz",
        "ounce wt": "oz", "ounces": "oz", "ounces.": "oz", "ounze": "oz", "ounzes": "oz",
        "oz.": "oz", "ozes": "oz", "ozs": "oz", "ozs.": "oz", "wt oz": "oz",
        // package
        "pack": "package", "packages": "package", "packet": "package", "packs": "package",
        "pak": "package", "pckg": "package", "pckgs": "package", "pk": "package", "pk.": "package",
        "pkg": "package", "pkg.": "package", "pkgd": "package", "pkge": "package", "pkges": "package",
        "pkgs": "package", "pkgs.": "package", "pks": "package", "pkt": "package",
        // piece
        "ea": "piece", "each": "piece", "pc": "piece", "pc.": "piece", "pce": "piece",
        "pces": "piece", "pcs": "piece", "peice": "piece", "peices": "piece", "pieces": "piece",
        // pinch
        "pch": "pinch", "pich": "pinch", "pinch.": "pinch", "pinches": "pinch",
        "pinchs": "pinch", "pn": "pinch", "pn.": "pinch",
        // pint
        "pint.": "pint", "pints": "pint", "pnt": "pint", "pnts": "pint",
        "pt": "pint", "pt.": "pint", "pts": "pint", "pts.": "pint",
        // lb
        "#": "lb", "lb.": "lb", "lbs": "lb", "lbs.": "lb", "lbss": "lb", "pd": "lb", "pd.": "lb",
        "pds": "lb", "pnd": "lb", "pnds": "lb", "pound": "lb", "pound.": "lb", "pounds": "lb",
        // qt
        "qrt": "qt", "qt.": "qt", "qts": "qt", "qts.": "qt", "quart": "qt",
        "quarts": "qt", "quarts.": "qt", "qurt": "qt",
        // slice
        "sl": "slice", "sl.": "slice", "slc": "slice", "slcs": "slice", "sli": "slice",
        "slice.": "slice", "slices": "slice",
        // small
        "sm": "small", "sm.": "small", "small.": "small", "sml": "small",
        // stick
        "sticks": "stick", "stik": "stick", "stk": "stick", "stk.": "stick", "stks": "stick", "stks.": "stick",
        // tbsp (see normalizedAlias for "T"/"T.")
        "table spoon": "tbsp", "table spoons": "tbsp", "tablespon": "tbsp",
        "tablespoon": "tbsp", "tablespoons": "tbsp", "tb": "tbsp", "tbl": "tbsp", "tbl.": "tbsp",
        "tbls": "tbsp", "tblsp": "tbsp", "tblspn": "tbsp", "tblspoon": "tbsp", "tbs": "tbsp",
        "tbs.": "tbsp", "Tbsp": "tbsp", "tbsp.": "tbsp", "Tbsp.": "tbsp", "tbsps": "tbsp",
        // tsp (see normalizedAlias for "t")
        "tea spoon": "tsp", "tea spoons": "tsp", "teasp": "tsp", "teaspon": "tsp",
        "teaspoon": "tsp", "teaspoons": "tsp", "teaspoonsful": "tsp", "ts": "tsp", "ts.": "tsp",
        "tsp.": "tsp", "tspn": "tsp", "tspns": "tsp", "tsps": "tsp",
    ]

    /// "T" (tablespoon) vs "t" (teaspoon) is the one genuinely
    /// case-sensitive abbreviation pair in common use — checked with exact
    /// case before the case-insensitive `unitAliases` lookup below, or a
    /// lowercase "t" would incorrectly resolve to tbsp (whose own alias
    /// table is keyed case-insensitively for everything else).
    private static func normalizedAlias(_ rawCandidate: String) -> String {
        if rawCandidate == "T" || rawCandidate == "T." { return "tbsp" }
        if rawCandidate == "t" { return "tsp" }
        return unitAliases[rawCandidate.lowercased()] ?? rawCandidate
    }

    /// `candidate`, normalized through the alias table (or as-is), if it —
    /// exactly or as a naive plural — matches something in `knownUnits`;
    /// nil if it doesn't look like a unit at all.
    private static func normalizedUnit(_ candidate: String, knownUnits: [String]) -> String? {
        let aliased = normalizedAlias(candidate)
        let matchesKnownUnit = knownUnits.contains { $0.caseInsensitiveCompare(aliased) == .orderedSame }
            || knownUnits.contains { $0.caseInsensitiveCompare(aliased.trimmingCharacters(in: CharacterSet(charactersIn: "s"))) == .orderedSame && aliased.count > 1 }
        return matchesKnownUnit ? aliased : nil
    }

    /// "cups flour" → ("cups", "flour"), "fl oz milk" → ("fl oz", "milk").
    /// A two-word candidate ("fl oz", "table spoon") is tried before
    /// falling back to one word, since several canonical units and their
    /// aliases are inherently two words — a two-word attempt that isn't a
    /// recognized unit just falls through to the one-word case. No match
    /// at all (e.g. "Bananas", "potatoes" — a countable item with no
    /// separate unit) leaves the whole remainder as the name, unit nil.
    private static func splitUnitAndName(_ remainder: String, knownUnits: [String]) -> (unit: String?, name: String) {
        guard !remainder.isEmpty else { return (nil, "") }
        let words = remainder.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let first = words.first else { return (nil, remainder) }

        if words.count >= 2 {
            let twoWordCandidate = "\(words[0]) \(words[1])"
            if let normalized = normalizedUnit(twoWordCandidate, knownUnits: knownUnits) {
                return (normalized, words.dropFirst(2).joined(separator: " "))
            }
        }

        if let normalized = normalizedUnit(first, knownUnits: knownUnits) {
            return (normalized, words.dropFirst(1).joined(separator: " "))
        }

        return (nil, remainder)
    }
}

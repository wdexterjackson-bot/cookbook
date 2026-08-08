//
//  CookbookCoverStyleCatalog.swift
//  cookbook
//
//  Pre-made cover designs offered in CookbookConfigurationView's "Cover
//  Style" section, bundled as image assets under Assets.xcassets/CoverStyles.
//  Cookbook.coverStyleImageName stores imageAssetName directly, so
//  Image(coverStyleImageName) always resolves without a lookup.
//

import Foundation

struct CookbookCoverStyle: Identifiable, Equatable {
    var imageAssetName: String
    var displayName: String

    var id: String { imageAssetName }
}

enum CookbookCoverStyleCatalog {
    static let allStyles: [CookbookCoverStyle] = [
        CookbookCoverStyle(imageAssetName: "01-forest-laurel", displayName: "Forest Laurel"),
        CookbookCoverStyle(imageAssetName: "02-olive-parchment", displayName: "Olive Parchment"),
        CookbookCoverStyle(imageAssetName: "03-tomato-terracotta", displayName: "Tomato Terracotta"),
        CookbookCoverStyle(imageAssetName: "04-mint-herbarium", displayName: "Mint Herbarium"),
        CookbookCoverStyle(imageAssetName: "05-midnight-lemon", displayName: "Midnight Lemon"),
        CookbookCoverStyle(imageAssetName: "06-blush-floral", displayName: "Blush Floral"),
        CookbookCoverStyle(imageAssetName: "07-mustard-wildflower", displayName: "Mustard Wildflower"),
        CookbookCoverStyle(imageAssetName: "08-cream-terrazzo", displayName: "Cream Terrazzo"),
        CookbookCoverStyle(imageAssetName: "09-blue-gingham", displayName: "Blue Gingham"),
        CookbookCoverStyle(imageAssetName: "10-green-utensils", displayName: "Green Utensils"),
        CookbookCoverStyle(imageAssetName: "11-citrus-branch", displayName: "Citrus Branch"),
        CookbookCoverStyle(imageAssetName: "12-brown-folk-floral", displayName: "Brown Folk Floral"),
        CookbookCoverStyle(imageAssetName: "13-lilac-wisteria", displayName: "Lilac Wisteria"),
        CookbookCoverStyle(imageAssetName: "14-indigo-watercolor", displayName: "Indigo Watercolor"),
        CookbookCoverStyle(imageAssetName: "15-coral-monstera", displayName: "Coral Monstera"),
        CookbookCoverStyle(imageAssetName: "16-cream-confetti", displayName: "Cream Confetti"),
        CookbookCoverStyle(imageAssetName: "17-olive-minimal", displayName: "Olive Minimal"),
        CookbookCoverStyle(imageAssetName: "18-teal-tile", displayName: "Teal Tile"),
        CookbookCoverStyle(imageAssetName: "19-lemon-grove", displayName: "Lemon Grove"),
        CookbookCoverStyle(imageAssetName: "20-black-produce", displayName: "Black Produce"),
        CookbookCoverStyle(imageAssetName: "21-poppy-field", displayName: "Poppy Field"),
        CookbookCoverStyle(imageAssetName: "22-sage-hills", displayName: "Sage Hills"),
        CookbookCoverStyle(imageAssetName: "23-rainbow-sprinkles", displayName: "Rainbow Sprinkles"),
        CookbookCoverStyle(imageAssetName: "24-lavender-botanical", displayName: "Lavender Botanical"),
        CookbookCoverStyle(imageAssetName: "25-cobalt-citrus", displayName: "Cobalt Citrus"),
        CookbookCoverStyle(imageAssetName: "26-coral-grid", displayName: "Coral Grid"),
        CookbookCoverStyle(imageAssetName: "27-modern-geometry", displayName: "Modern Geometry"),
        CookbookCoverStyle(imageAssetName: "28-linen-stripe", displayName: "Linen Stripe"),
        CookbookCoverStyle(imageAssetName: "29-chili-red", displayName: "Chili Red"),
        CookbookCoverStyle(imageAssetName: "30-eucalyptus-mint", displayName: "Eucalyptus Mint"),
        CookbookCoverStyle(imageAssetName: "31-embroidered-meadow", displayName: "Embroidered Meadow"),
        CookbookCoverStyle(imageAssetName: "32-dark-modernist", displayName: "Dark Modernist"),
        CookbookCoverStyle(imageAssetName: "33-orange-grove", displayName: "Orange Grove"),
        CookbookCoverStyle(imageAssetName: "34-navy-pinstripe", displayName: "Navy Pinstripe"),
        CookbookCoverStyle(imageAssetName: "35-parsley-paper", displayName: "Parsley Paper"),
        CookbookCoverStyle(imageAssetName: "36-black-gold-garden", displayName: "Black Gold Garden"),
    ]

    static func style(named imageAssetName: String?) -> CookbookCoverStyle? {
        guard let imageAssetName else { return nil }
        return allStyles.first { $0.imageAssetName == imageAssetName }
    }
}

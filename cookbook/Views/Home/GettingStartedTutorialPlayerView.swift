//
//  GettingStartedTutorialPlayerView.swift
//  cookbook
//
//  The "Watch a Getting Started Tutorial" video from Home's Getting
//  Started card. Two bundled files (cookbook/Resources/Videos), not one —
//  a 3x4 portrait cut for phones and tablets held in portrait, and a 16x9
//  landscape cut for tablets held in landscape (and, if this ever grows a
//  tvOS target, Apple TV, which has no other orientation to speak of).
//  The right one is picked once, when the player is presented, not
//  reactively via GeometryReader the way AppBackground's orientation
//  switching is — restarting playback mid-watch because the device
//  rotated would be a worse experience than a fixed aspect ratio for the
//  duration of a 90-second video.
//

import SwiftUI
import AVKit

enum GettingStartedTutorialAsset {
    static func filename(isLandscape: Bool) -> String {
        isLandscape ? "GettingStartedTutorial-Landscape" : "GettingStartedTutorial-Portrait"
    }

    #if os(iOS)
    static func currentURL() -> URL? {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let isLandscape = isPad && isCurrentlyLandscape()
        return Bundle.main.url(forResource: filename(isLandscape: isLandscape), withExtension: "mp4")
    }

    /// `UIDevice.current.orientation` can read `.unknown`/`.faceUp` right
    /// after a fresh presentation, before the accelerometer has reported
    /// anything — falls back to the window scene's actual interface
    /// orientation (always meaningful) rather than defaulting to portrait
    /// on a device that's really being held sideways.
    private static func isCurrentlyLandscape() -> Bool {
        let deviceOrientation = UIDevice.current.orientation
        if deviceOrientation.isLandscape { return true }
        if deviceOrientation.isPortrait { return false }
        let interfaceOrientation = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.interfaceOrientation }
            .first
        return interfaceOrientation?.isLandscape ?? false
    }
    #else
    static func currentURL() -> URL? {
        Bundle.main.url(forResource: filename(isLandscape: true), withExtension: "mp4")
    }
    #endif
}

struct GettingStartedTutorialPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            Group {
                if let player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea(edges: .bottom)
                        .onAppear { player.play() }
                        .onDisappear { player.pause() }
                } else {
                    ContentUnavailableView(
                        "Video Unavailable",
                        systemImage: "video.slash",
                        description: Text("The Getting Started video couldn't be found.")
                    )
                }
            }
            .navigationTitle("Getting Started")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            if let url = GettingStartedTutorialAsset.currentURL() {
                player = AVPlayer(url: url)
            }
        }
    }
}

#Preview {
    GettingStartedTutorialPlayerView()
}

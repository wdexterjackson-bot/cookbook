//
//  PresentationAnchor.swift
//  cookbook
//
//  GIDSignIn needs a concrete presenting view controller — SwiftUI has no
//  native way to hand one over, so this reaches into UIKit for it.
//

#if os(iOS)
import UIKit

@MainActor
enum PresentationAnchor {
    static func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return nil
        }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}
#endif

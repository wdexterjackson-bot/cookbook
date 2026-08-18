//
//  PendingFileImportState.swift
//  cookbook
//
//  Dragging a file onto a running app in the Simulator (or "Open In…"
//  from another app on a real device) delivers it straight into this
//  app's own sandboxed Documents/Inbox — nowhere a document picker can
//  browse to, since this app doesn't expose its container to Files
//  (no UIFileSharingEnabled). onOpenURL (cookbookApp.swift) is the only
//  way to actually receive it; this holds that URL until RootTabView's
//  top-level sheet picks it up and routes it into the same bulk-import
//  flow ImportRecipesFileView's own "Choose File" button uses. No
//  UserDefaults persistence — purely transient within one launch.
//

import Foundation
import Observation

@MainActor
@Observable
final class PendingFileImportState {
    var url: URL?
}

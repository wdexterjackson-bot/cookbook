//
//  TestModelContainer.swift
//  cookbookTests
//
//  Swift Testing runs suites in parallel by default, and every test
//  file's own makeInMemoryContext() independently calls
//  ModelContainer(for:configurations:) — which, under real concurrent
//  load, races inside CoreData's own internal model-caching code
//  (NSManagedObjectModel/NSEntityDescription encoding during
//  -[NSSQLiteConnection connect]) and segfaults (observed directly: a
//  SIGSEGV inside -[NSSQLEntity_DerivedAttributesExtension
//  _generateTriggerSQL] -> -[__NSDictionaryM setObject:forKey:], with
//  half a dozen other threads mid-way through the exact same
//  saveCachedModel: call stack at the same instant). This isn't this
//  app's bug — it's CoreData's model-cache machinery not being
//  thread-safe against itself — but every test-side ModelContainer
//  construction has to go through this one lock to avoid tripping it.
//

import Foundation
import SwiftData

enum TestModelContainer {
    private static let lock = NSLock()

    static func make(schema: Schema, isStoredInMemoryOnly: Bool = true) throws -> ModelContainer {
        lock.lock()
        defer { lock.unlock() }
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isStoredInMemoryOnly)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

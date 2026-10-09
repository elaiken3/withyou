//
//  AITimeout.swift
//  WithYou
//

import Foundation

/// Runs AI work with a deadline, so a slow model never keeps the person waiting.
nonisolated enum AITimeout {
    /// Thrown when the deadline passes first.
    nonisolated struct Expired: Error, Equatable {}

    /// Returns `operation`'s result, or throws `Expired` after `seconds`.
    /// Whichever finishes second is cancelled.
    nonisolated static func run<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                throw Expired()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw Expired()
            }
            return first
        }
    }
}

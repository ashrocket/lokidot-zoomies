import Darwin
import Foundation

/// AppKit frees a closed window's objects, but malloc keeps the empty pages
/// dirty, so Activity Monitor still counts them. After a window, a reminder
/// card or a lap goes away, hand the empty pages back to macOS.
enum MemoryRelief {
    private static var pending: DispatchWorkItem?

    /// Runs once, `delay` seconds after the last call, on the main queue.
    /// The delay lets autorelease pools and Core Animation free their objects first.
    static func soon(after delay: TimeInterval = 2) {
        dispatchPrecondition(condition: .onQueue(.main))
        pending?.cancel()
        let work = DispatchWorkItem {
            pending = nil
            _ = malloc_zone_pressure_relief(nil, 0)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

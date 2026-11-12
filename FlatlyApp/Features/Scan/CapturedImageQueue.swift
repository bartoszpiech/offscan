import CoreGraphics

/// The pages of one camera session, handed out one at a time. The queue is their only owner, so
/// each full-size image is released as soon as its page has been processed. A `Task` closure that
/// captures the `[CGImage]` itself would keep every image alive until the whole batch is done.
@MainActor
final class CapturedImageQueue {
    let count: Int
    /// Reversed so `next()` is a cheap `popLast()`; a fresh buffer nobody else references.
    private var remaining: [CGImage]

    init(_ images: [CGImage]) {
        count = images.count
        remaining = Array(images.reversed())
    }

    /// The next image in capture order, or nil once all have been handed out.
    func next() -> CGImage? {
        remaining.popLast()
    }

    /// Drops every image not yet handed out, so `next()` returns nil from now on. Used by Stop:
    /// the images are released at once.
    func discardRemaining() {
        remaining.removeAll()
    }
}

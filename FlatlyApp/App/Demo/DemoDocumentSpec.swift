#if DEBUG
import Foundation

/// One document of the demo library: its title, folder, age and pages.
struct DemoDocumentSpec: Sendable {
    let title: String
    let folder: DemoFolder?
    /// How long ago the document was scanned; used as its created and modified date.
    let age: TimeInterval
    let pages: [DemoPageSpec]
}
#endif

import SwiftUI

/// Alerts with a text field shown by the library (rename / new folder).
enum LibraryTextPrompt {
    case renameDocument(ScanDocument)
    case renameFolder(Folder)
    case newFolder

    var title: Text {
        switch self {
        case .renameDocument: Text("Rename Document")
        case .renameFolder: Text("Rename Folder")
        case .newFolder: Text("New Folder")
        }
    }

    var placeholder: LocalizedStringKey {
        switch self {
        case .renameDocument: "Title"
        case .renameFolder, .newFolder: "Folder name"
        }
    }

    var confirmTitle: LocalizedStringKey {
        switch self {
        case .renameDocument, .renameFolder: "Rename"
        case .newFolder: "Create"
        }
    }

    /// Text the field starts with.
    var initialText: String {
        switch self {
        case .renameDocument(let document): document.title
        case .renameFolder(let folder): folder.name
        case .newFolder: ""
        }
    }
}

import SwiftUI
import FlatlyCore

/// Sets or removes the password of the PDF being exported, pushed from `ExportSheet`.
///
/// The password is typed twice and must be printable ASCII (`PDFExporter.isSupportedPassword`).
/// It is written to `password` only by Set and lives in the Export sheet's view state, so it
/// applies to that one export and is never stored. The system back button cancels.
struct PDFPasswordView: View {
    @Binding var password: String?

    @Environment(\.dismiss) private var dismiss

    @State private var draft = ""
    @State private var confirmation = ""
    @FocusState private var focused: Field?

    private enum Field { case password, confirmation }

    private var isValid: Bool {
        PDFExporter.isSupportedPassword(draft) && draft == confirmation
    }

    /// Shown once the confirmation is as long as the password but still differs.
    private var showsMismatch: Bool {
        !confirmation.isEmpty && confirmation.count >= draft.count && confirmation != draft
    }

    var body: some View {
        Form {
            Section {
                SecureField("Password", text: $draft)
                    .focused($focused, equals: .password)
                    .submitLabel(.next)
                    .onSubmit { focused = .confirmation }
                    .keyboardType(.asciiCapable)
                    .accessibilityIdentifier("export.password.field")

                SecureField("Confirm Password", text: $confirmation)
                    .focused($focused, equals: .confirmation)
                    .submitLabel(.done)
                    .onSubmit { if isValid { apply() } }
                    .keyboardType(.asciiCapable)
                    .accessibilityIdentifier("export.password.confirmField")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if !draft.isEmpty && !PDFExporter.isSupportedPassword(draft) {
                        Text("Use only letters without accents, digits, spaces and symbols.")
                            .foregroundStyle(.red)
                    } else if showsMismatch {
                        Text("The passwords don't match.")
                            .foregroundStyle(.red)
                    }
                    Text("Anyone opening the PDF will need this password. Offscan doesn't keep it and can't recover it.")
                }
            }

            if password != nil {
                Section {
                    Button("Remove Password", role: .destructive) {
                        password = nil
                        dismiss()
                    }
                    .accessibilityIdentifier("export.password.removeButton")
                }
            }
        }
        .navigationTitle(Text("PDF Password"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The only trailing item; the system back button cancels.
            ToolbarItem(placement: .confirmationAction) {
                Button("Set") { apply() }
                    .disabled(!isValid)
                    .accessibilityIdentifier("export.password.setButton")
            }
        }
        .onAppear { focused = .password }
    }

    private func apply() {
        password = draft
        dismiss()
    }
}

#if DEBUG
struct PDFPasswordView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            PDFPasswordView(password: .constant("flatly"))
        }
    }
}
#endif

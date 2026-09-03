import AppKit
import SwiftUI

/// Compact capture field for the menubar: title + optional sniffed clipboard link.
struct CapturePopoverView: View {
    @Binding var title: String
    var detectedLink: String?
    var detectedKind: String?
    var statusMessage: String?
    var isSubmitting: Bool
    var onCapture: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Capture to inbox")
                .font(.headline)

            TextField("What’s on your mind?", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit { onCapture() }

            if let detectedLink, !detectedLink.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(detectedKind.map { "Clipboard \($0)" } ?? "Clipboard link")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(detectedLink)
                            .font(.caption2)
                            .lineLimit(2)
                            .foregroundStyle(.primary)
                    }
                }
            }

            if let statusMessage, !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isSubmitting ? "Capturing…" : "Capture") {
                    onCapture()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
        }
        .padding(14)
        .frame(width: 340)
    }
}

import AmnesiaCore
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Amnesia")
                .font(.headline)

            ForEach(SessionSource.allCases) { source in
                LabeledContent(source.displayName, value: "Not scanned")
            }

            Divider()

            Button("Quit Amnesia") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 280)
    }
}

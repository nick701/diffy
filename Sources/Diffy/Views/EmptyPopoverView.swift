import SwiftUI

struct EmptyPopoverView: View {
    @ObservedObject var store: DiffyStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diffy")
                .font(.headline)

            Text("Add a local git repository to start watching diff stats.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Add Repository") {
                    RepositoryPicker.addRepository(to: store)
                }

                SettingsLink {
                    Text("Settings")
                }
            }
        }
        .padding()
        .frame(width: 340, height: 160)
    }
}

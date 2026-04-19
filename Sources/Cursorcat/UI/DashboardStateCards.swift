import SwiftUI

struct LoadingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Today")
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Loading…")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct LoggedOutCard: View {
    let actions: DashboardActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Not logged in")
                .font(.headline)
            Text("Log in to Cursor to see your spend, quotas, and billing cycle.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open Cursor to log in", action: actions.openCursor)
                    .buttonStyle(.glassProminent)
                Spacer()
                Button("Quit", action: actions.quit)
                    .buttonStyle(.glass)
            }
        }
    }
}

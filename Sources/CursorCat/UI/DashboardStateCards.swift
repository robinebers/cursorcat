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

struct FailedCard: View {
    let message: String?
    let actions: DashboardActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Update Failed")
            if let message {
                ErrorBanner(message: message)
            } else {
                Text("CursorCat couldn’t refresh your usage right now.")
                    .foregroundStyle(.secondary)
            }
            Button(action: actions.refresh) {
                Text("Try Again")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
    }
}

struct LoggedOutCard: View {
    let actions: DashboardActions

    var body: some View {
        VStack(alignment: .center, spacing: 14) {
            VStack(alignment: .center, spacing: 6) {
                Text("Not logged in")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("Once signed in, CursorCat keeps track of your spending and model activity.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            VStack(spacing: 6) {
                Button(action: actions.openCursor) {
                    Text("Open Cursor to log in")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

                Button(action: actions.refresh) {
                    Text("Try again")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }
}

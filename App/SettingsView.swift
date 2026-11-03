import SwiftUI

struct SettingsView: View {
    #if !APP_STORE
    @AppStorage(UpdateChecker.betaKey) private var betaUpdates = UpdateChecker.runningBeta
    #endif

    var body: some View {
        Form {
            #if APP_STORE
            Section("General") {
                Text("Nothing to set yet.").foregroundStyle(.secondary)
            }
            #else
            Section {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { UpdateChecker.shared.automaticChecks },
                    set: { UpdateChecker.shared.automaticChecks = $0 }))
                Toggle("Download and install updates automatically", isOn: Binding(
                    get: { UpdateChecker.shared.automaticDownloads },
                    set: { UpdateChecker.shared.automaticDownloads = $0 }))
                Toggle("Get beta versions", isOn: $betaUpdates)
                Button("Check Now") { UpdateChecker.shared.checkForUpdates() }
            } header: {
                Text("Updates")
            } footer: {
                Text("Once a day, Phin Tech Store asks GitHub for a newer release and installs it, so it's there the next time you open the store. "
                    + "Betas come out before a release and may have rough edges; when the release ships, you move on to it.")
                    .foregroundStyle(.secondary)
            }
            #endif
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }
}

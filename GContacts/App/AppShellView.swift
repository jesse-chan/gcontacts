import SwiftUI

struct AppShellView: View {
    @Environment(ContactStore.self) private var contactStore
    @Environment(GoogleAuthService.self) private var googleAuthService

    var body: some View {
        TabView {
            NavigationStack {
                ContactsListView()
            }
            .tabItem {
                Label("tab.contacts", systemImage: "person.crop.circle")
            }

            NavigationStack {
                LabelsView()
            }
            .tabItem {
                Label("tab.labels", systemImage: "tag")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("tab.settings", systemImage: "gearshape")
            }
        }
        .onChange(of: googleAuthService.user) { _, user in
            Task {
                if user == nil {
                    contactStore.clear()
                } else {
                    await contactStore.load()
                }
            }
        }
    }
}

#Preview {
    AppShellView()
        .environment(ContactStore(service: MockGoogleContactsService()))
}

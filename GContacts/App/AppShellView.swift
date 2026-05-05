import SwiftUI

struct AppShellView: View {
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
    }
}

#Preview {
    AppShellView()
        .environment(ContactStore(service: MockGoogleContactsService()))
}


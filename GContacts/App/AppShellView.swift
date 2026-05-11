import SwiftUI

enum AppTab: Hashable {
    case contacts
    case labels
    case settings
}

struct ContactLabelSelection: Equatable {
    var id: String?
    var name: String

    static let all = ContactLabelSelection(id: nil, name: String(localized: "labels.all"))
}

struct AppShellView: View {
    @Environment(ContactStore.self) private var contactStore
    @Environment(GoogleAuthService.self) private var googleAuthService
    @State private var selectedTab: AppTab = .contacts
    @State private var selectedLabel = ContactLabelSelection.all
    @State private var contactListScrollToTopTrigger = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ContactsListView(
                    selectedLabel: selectedLabel,
                    scrollToTopTrigger: contactListScrollToTopTrigger
                )
            }
            .tabItem {
                Label("tab.contacts", systemImage: "person.crop.circle")
            }
            .tag(AppTab.contacts)

            NavigationStack {
                LabelsView(selectedLabel: $selectedLabel) {
                    contactListScrollToTopTrigger += 1
                    selectedTab = .contacts
                }
            }
            .tabItem {
                Label("tab.labels", systemImage: "tag")
            }
            .tag(AppTab.labels)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("tab.settings", systemImage: "gearshape")
            }
            .tag(AppTab.settings)
        }
        .onChange(of: googleAuthService.user) { _, user in
            Task {
                if user == nil {
                    contactStore.clear()
                    selectedLabel = .all
                } else {
                    await contactStore.load()
                }
            }
        }
        .onChange(of: contactStore.labels) { _, labels in
            guard let selectedLabelID = selectedLabel.id else { return }
            if let label = labels.first(where: { $0.id == selectedLabelID }) {
                selectedLabel = ContactLabelSelection(id: label.id, name: label.name)
            } else {
                selectedLabel = .all
            }
        }
        .task {
            if googleAuthService.user != nil && contactStore.contacts.isEmpty && contactStore.labels.isEmpty {
                await contactStore.load()
            }
        }
    }
}

#Preview {
    AppShellView()
        .environment(ContactStore(service: MockGoogleContactsService()))
}

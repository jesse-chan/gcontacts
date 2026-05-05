import SwiftUI

struct ContactDetailView: View {
    @Environment(ContactStore.self) private var store
    @State private var draft: Contact
    @State private var isEditing = false

    init(contact: Contact) {
        _draft = State(initialValue: contact)
    }

    var body: some View {
        List {
            Section("section.labels") {
                Text(store.labelNames(for: draft.labelIDs).emptyFallback(String(localized: "labels.none")))
            }

            ContactFieldSection(title: "section.names", items: draft.names.map(\.displayName))
            ContactFieldSection(title: "section.nicknames", items: draft.nicknames.map(\.value))
            ContactFieldSection(title: "section.emails", items: draft.emailAddresses.map(\.value))
            ContactFieldSection(title: "section.phones", items: draft.phoneNumbers.map(\.value))
            ContactFieldSection(title: "section.addresses", items: draft.addresses.map { [$0.streetAddress, $0.city, $0.region, $0.postalCode, $0.country].joinedNonEmpty(separator: ", ") })
            ContactFieldSection(title: "section.organizations", items: draft.organizations.map { [$0.name, $0.department, $0.title].joinedNonEmpty(separator: " · ") })
            ContactFieldSection(title: "section.birthdays", items: draft.birthdays.map { [$0.year, $0.month, $0.day].joinedNonEmpty(separator: "/") })
            ContactFieldSection(title: "section.events", items: draft.events.map { "\($0.label): \([$0.date.year, $0.date.month, $0.date.day].joinedNonEmpty(separator: "/"))" })
            ContactFieldSection(title: "section.urls", items: draft.urls.map(\.value))
            ContactFieldSection(title: "section.relations", items: draft.relations.map { "\($0.label): \($0.person)" })
            ContactFieldSection(title: "section.biographies", items: draft.biographies)
            ContactFieldSection(title: "section.userDefined", items: draft.userDefined.map { "\($0.key): \($0.value)" })
        }
        .navigationTitle(draft.displayName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("action.edit") {
                    isEditing = true
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            ContactEditorView(contact: draft)
        }
        .onChange(of: store.contacts) { _, contacts in
            if let updated = contacts.first(where: { $0.id == draft.id }) {
                draft = updated
            }
        }
    }
}

private struct ContactFieldSection: View {
    let title: LocalizedStringKey
    let items: [String]

    var body: some View {
        Section(title) {
            if items.filter({ !$0.isEmpty }).isEmpty {
                Text("field.empty")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items.filter { !$0.isEmpty }, id: \.self) { item in
                    Text(item)
                }
            }
        }
    }
}

private extension String {
    func emptyFallback(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}

private extension Array where Element == String {
    func joinedNonEmpty(separator: String) -> String {
        filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: separator)
    }
}


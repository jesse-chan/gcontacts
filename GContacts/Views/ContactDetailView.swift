import SwiftUI

struct ContactDetailView: View {
    @Environment(ContactStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Contact
    @State private var isEditing = false
    @State private var isConfirmingDelete = false

    init(contact: Contact) {
        _draft = State(initialValue: contact)
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 28) {
                    Button {
                        Task { await toggleStar() }
                    } label: {
                        Image(systemName: draft.isStarred ? "star.fill" : "star")
                            .font(.title3)
                            .foregroundStyle(draft.isStarred ? .yellow : .primary)
                            .frame(width: 44, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(draft.isStarred ? Text("action.unstar") : Text("action.star"))

                    Button {
                        isEditing = true
                    } label: {
                        Text("action.edit")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 10)
                            .background(.blue, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.title3)
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("action.delete"))
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            .listSectionSpacing(.compact)

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
        .sheet(isPresented: $isEditing) {
            ContactEditorView(contact: draft)
        }
        .confirmationDialog("contacts.delete.title", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("action.delete", role: .destructive) {
                Task {
                    await store.delete(draft)
                    dismiss()
                }
            }
            Button("action.cancel", role: .cancel) {}
        } message: {
            Text("contacts.delete.message")
        }
        .onChange(of: store.contacts) { _, contacts in
            if let updated = contacts.first(where: { $0.id == draft.id }) {
                draft = updated
            }
        }
    }

    private func toggleStar() async {
        var updated = draft
        if updated.isStarred {
            updated.labelIDs.remove(Contact.starredLabelID)
        } else {
            updated.labelIDs.insert(Contact.starredLabelID)
        }

        if let saved = await store.save(updated) {
            draft = saved
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

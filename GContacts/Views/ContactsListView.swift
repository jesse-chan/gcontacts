import SwiftUI

struct ContactsListView: View {
    @Environment(ContactStore.self) private var store
    @State private var searchText = ""
    @State private var contactToEdit: Contact?

    private var filteredContacts: [Contact] {
        guard !searchText.isEmpty else { return store.contacts }
        return store.contacts.filter { contact in
            contact.displayName.localizedStandardContains(searchText)
                || contact.emailAddresses.contains { $0.value.localizedStandardContains(searchText) }
                || contact.phoneNumbers.contains { $0.value.localizedStandardContains(searchText) }
        }
    }

    private var favoriteContacts: [Contact] {
        filteredContacts.filter(\.isStarred)
    }

    private var regularContacts: [Contact] {
        filteredContacts.filter { !$0.isStarred }
    }

    var body: some View {
        VStack(spacing: 0) {
            ContactSearchField(text: $searchText)
                .padding(.horizontal)
                .padding(.bottom, 8)

            List {
                if store.isLoading {
                    ProgressView()
                }

                if !favoriteContacts.isEmpty {
                    Section {
                        ForEach(favoriteContacts) { contact in
                            NavigationLink(value: contact) {
                                ContactRowView(contact: contact, labels: store.labelNames(for: contact.labelIDs))
                            }
                        }
                        .onDelete { offsets in
                            let contactsToDelete = offsets.map { favoriteContacts[$0] }
                            Task { await store.delete(contactsToDelete) }
                        }
                    } header: {
                        Label {
                            Text("contacts.favorites \(favoriteContacts.count)")
                        } icon: {
                            Image(systemName: "star.fill")
                        }
                    }
                }

                if !regularContacts.isEmpty {
                    Section("contacts.title") {
                        ForEach(regularContacts) { contact in
                            NavigationLink(value: contact) {
                                ContactRowView(contact: contact, labels: store.labelNames(for: contact.labelIDs))
                            }
                        }
                        .onDelete { offsets in
                            let contactsToDelete = offsets.map { regularContacts[$0] }
                            Task { await store.delete(contactsToDelete) }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("contacts.title")
        .navigationDestination(for: Contact.self) { contact in
            ContactDetailView(contact: contact)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    contactToEdit = .empty
                } label: {
                    Label("contacts.add", systemImage: "plus")
                }
            }
        }
        .sheet(item: $contactToEdit) { contact in
            ContactEditorView(contact: contact)
        }
        .task {
            if store.contacts.isEmpty {
                await store.load()
            }
        }
        .alert("error.title", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("action.ok", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

private struct ContactSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("contacts.search", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("contacts.search.clear")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Color(.secondarySystemBackground), in: Capsule())
    }
}

private struct ContactRowView: View {
    let contact: Contact
    let labels: String

    var body: some View {
        HStack(spacing: 12) {
            ContactAvatarView(contact: contact)

            VStack(alignment: .leading, spacing: 4) {
                Text(contact.displayName)
                    .font(.headline)

                if let email = contact.emailAddresses.first?.value, !email.isEmpty {
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !labels.isEmpty {
                    Text(labels)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

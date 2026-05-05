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

    var body: some View {
        List {
            if store.isLoading {
                ProgressView()
            }

            ForEach(filteredContacts) { contact in
                NavigationLink(value: contact) {
                    ContactRowView(contact: contact, labels: store.labelNames(for: contact.labelIDs))
                }
            }
            .onDelete { offsets in
                Task { await store.deleteContacts(at: offsets) }
            }
        }
        .navigationTitle("contacts.title")
        .navigationDestination(for: Contact.self) { contact in
            ContactDetailView(contact: contact)
        }
        .searchable(text: $searchText, prompt: "contacts.search")
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

private struct ContactRowView: View {
    let contact: Contact
    let labels: String

    var body: some View {
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
        .padding(.vertical, 4)
    }
}


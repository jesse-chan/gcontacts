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

private struct ContactAvatarView: View {
    let contact: Contact

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            avatar

            if contact.isStarred {
                Image(systemName: "star.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(.yellow, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(.background, lineWidth: 2)
                    }
                    .offset(x: 2, y: 2)
            }
        }
        .frame(width: 48, height: 48)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var avatar: some View {
        if let photoURL = contact.photoURL {
            AsyncImage(url: photoURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure, .empty:
                    fallbackAvatar
                @unknown default:
                    fallbackAvatar
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
        } else {
            fallbackAvatar
        }
    }

    private var fallbackAvatar: some View {
        Circle()
            .fill(avatarColor)
            .overlay {
                Text(initial)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
            }
    }

    private var initial: String {
        contact.displayName.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init) ?? "?"
    }

    private var avatarColor: Color {
        let colors: [Color] = [.purple, .blue, .teal, .green, .orange, .pink, .indigo]
        let hash = abs(contact.displayName.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) })
        return colors[hash % colors.count]
    }
}

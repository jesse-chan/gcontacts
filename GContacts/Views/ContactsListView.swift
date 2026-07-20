import SwiftUI

struct ContactsListView: View {
    @Environment(ContactStore.self) private var store
    @Environment(\.locale) private var locale
    @Binding var selectedLabel: ContactLabelSelection
    let scrollToTopTrigger: Int
    @State private var searchText = ""
    @State private var contactToEdit: Contact?
    @State private var isShowingLabelFilter = false

    private var filteredContacts: [Contact] {
        let labelFilteredContacts = if let labelID = selectedLabel.id {
            store.contacts.filter { $0.labelIDs.contains(labelID) }
        } else {
            store.contacts
        }

        guard !searchText.isEmpty else { return labelFilteredContacts }
        return labelFilteredContacts.filter { contact in
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
            .id(listIdentity)
            .refreshable {
                await store.load()
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle(navigationTitle)
        .navigationDestination(for: Contact.self) { contact in
            ContactDetailView(contact: contact)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task {
                        await store.load()
                    }
                } label: {
                    if store.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("contacts.sync", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(store.isLoading)
                .accessibilityLabel("contacts.sync")

                Button {
                    isShowingLabelFilter = true
                } label: {
                    Label("contacts.filter", systemImage: "line.3.horizontal.decrease.circle")
                }

                Button {
                    contactToEdit = .empty
                } label: {
                    Label("contacts.add", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingLabelFilter) {
            ContactLabelFilterSheet(selectedLabel: $selectedLabel)
        }
        .sheet(item: $contactToEdit) { contact in
            ContactEditorView(contact: contact)
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

    private var navigationTitle: String {
        let contactsTitle = String(localized: "contacts.title", locale: locale)
        guard selectedLabel.id != nil else {
            return contactsTitle
        }
        return "\(contactsTitle) - \(selectedLabel.name)"
    }

    private var listIdentity: String {
        "\(selectedLabel.id ?? "all")-\(scrollToTopTrigger)"
    }
}

private struct ContactLabelFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ContactStore.self) private var store
    @Binding var selectedLabel: ContactLabelSelection

    private var sortedLabels: [ContactLabel] {
        store.labels.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ContactLabelFilterRow(
                    title: String(localized: "labels.all"),
                    subtitle: String(localized: "labels.count \(store.contacts.count)"),
                    isSelected: selectedLabel.id == nil
                ) {
                    selectedLabel = .all
                    dismiss()
                }

                ForEach(sortedLabels) { label in
                    ContactLabelFilterRow(
                        title: label.name,
                        subtitle: String(localized: "labels.count \(label.contactCount)"),
                        isSelected: selectedLabel.id == label.id
                    ) {
                        selectedLabel = ContactLabelSelection(id: label.id, name: label.name)
                        dismiss()
                    }
                }
            }
            .navigationTitle("contacts.filter")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ContactLabelFilterRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

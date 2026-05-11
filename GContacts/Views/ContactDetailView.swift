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
                VStack(spacing: 20) {
                    ContactHeaderTitleView(contact: draft)

                    ContactAvatarView(contact: draft, size: 128)
                        .frame(maxWidth: .infinity)

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
                }
                .padding(.top, 4)
                .padding(.bottom, 2)
                .listRowBackground(Color.clear)
            }
            .listSectionSpacing(.compact)

            let labels = store.labelList(for: draft.labelIDs)
            if !store.labels.isEmpty || !labels.isEmpty {
                Section {
                    LabelChipsView(labels: labels) { label in
                        Task { await removeLabel(label) }
                    }
                        .padding(.vertical, 4)
                } header: {
                    LabelsSectionHeader(
                        labels: store.labels.sorted {
                            $0.name.localizedStandardCompare($1.name) == .orderedAscending
                        },
                        selectedLabelIDs: draft.labelIDs
                    ) { label in
                        Task { await toggleLabel(label) }
                    }
                }
            }

            ContactFieldSection(title: "section.names", items: draft.names.map(\.displayName))
            ContactFieldSection(title: "section.nicknames", items: draft.nicknames.map(\.value))
            ContactLabeledValueSection(title: "section.emails", items: draft.emailAddresses)
            ContactLabeledValueSection(title: "section.phones", items: draft.phoneNumbers)
            ContactFieldSection(title: "section.addresses", items: draft.addresses.map { [$0.streetAddress, $0.city, $0.region, $0.postalCode, $0.country].joinedNonEmpty(separator: ", ") })
            ContactFieldSection(title: "section.birthdays", items: draft.birthdays.map { [$0.year, $0.month, $0.day].joinedNonEmpty(separator: "/") })
            ContactFieldSection(title: "section.events", items: draft.events.map { "\($0.label): \([$0.date.year, $0.date.month, $0.date.day].joinedNonEmpty(separator: "/"))" })
            ContactFieldSection(title: "section.urls", items: draft.urls.map(\.value))
            ContactFieldSection(title: "section.relations", items: draft.relations.map { "\($0.label): \($0.person)" })
            ContactFieldSection(title: "section.biographies", items: draft.biographies)
            ContactFieldSection(title: "section.userDefined", items: draft.userDefined.map { "\($0.key): \($0.value)" })
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
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

    private func toggleLabel(_ label: ContactLabel) async {
        var updatedLabelIDs = draft.labelIDs
        if updatedLabelIDs.contains(label.id) {
            updatedLabelIDs.remove(label.id)
        } else {
            updatedLabelIDs.insert(label.id)
        }
        await updateLabels(updatedLabelIDs)
    }

    private func removeLabel(_ label: ContactLabel) async {
        var updatedLabelIDs = draft.labelIDs
        updatedLabelIDs.remove(label.id)
        await updateLabels(updatedLabelIDs)
    }

    private func updateLabels(_ labelIDs: Set<String>) async {
        var updated = draft
        updated.labelIDs = labelIDs
        if let saved = await store.save(updated) {
            draft = saved
        }
    }
}

private struct ContactHeaderTitleView: View {
    let contact: Contact

    private var organizationSummary: String {
        contact.organizations
            .map { [$0.title, $0.department, $0.name].joinedNonEmpty(separator: " · ") }
            .first { !$0.isBlank } ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(contact.displayName)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.72)

            if !organizationSummary.isBlank {
                Text(organizationSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ContactFieldSection: View {
    let title: LocalizedStringKey
    let items: [String]

    var body: some View {
        let visibleItems = items.filter { !$0.isBlank }
        if !visibleItems.isEmpty {
            Section(title) {
                ForEach(visibleItems, id: \.self) { item in
                    Text(item)
                }
            }
        }
    }
}

private struct ContactLabeledValueSection: View {
    let title: LocalizedStringKey
    let items: [LabeledValue]

    var body: some View {
        let visibleItems = items.filter {
            !$0.value.isBlank || !$0.label.isBlank
        }
        if !visibleItems.isEmpty {
            Section(title) {
                ForEach(visibleItems) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        if !item.value.isBlank {
                            Text(item.value)
                                .foregroundStyle(.primary)
                        }

                        if !item.label.isBlank {
                            Text(item.label.googleContactsDisplayLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

private struct LabelsSectionHeader: View {
    let labels: [ContactLabel]
    let selectedLabelIDs: Set<String>
    let onToggleLabel: (ContactLabel) -> Void
    @State private var isManagingLabels = false

    var body: some View {
        HStack {
            Text("section.labels")
            Spacer()
            Button {
                isManagingLabels = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .accessibilityLabel(Text("labels.manage"))
            .popover(isPresented: $isManagingLabels, arrowEdge: .top) {
                LabelManagerPopover(
                    labels: labels,
                    selectedLabelIDs: selectedLabelIDs,
                    onToggleLabel: onToggleLabel
                )
                .presentationCompactAdaptation(.popover)
            }
        }
    }
}

private struct LabelManagerPopover: View {
    let labels: [ContactLabel]
    let selectedLabelIDs: Set<String>
    let onToggleLabel: (ContactLabel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("labels.manage")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(labels) { label in
                        Button {
                            onToggleLabel(label)
                        } label: {
                            HStack(spacing: 14) {
                                if selectedLabelIDs.contains(label.id) {
                                    Text("🅥")
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(.blue)
                                        .frame(width: 28)
                                } else {
                                    Image(systemName: "tag")
                                        .font(.title3)
                                        .foregroundStyle(.primary)
                                        .frame(width: 28)
                                }

                                Text(label.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)

                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(width: 320, height: 440)
    }
}

private struct LabelChipsView: View {
    let labels: [ContactLabel]
    let onRemove: (ContactLabel) -> Void

    var body: some View {
        if labels.isEmpty {
            Text("labels.none")
                .foregroundStyle(.secondary)
        } else {
            FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(labels) { label in
                    HStack(spacing: 6) {
                        Text(label.name)
                            .lineLimit(1)

                        Button {
                            onRemove(label)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption.weight(.bold))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("labels.remove"))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
                    .padding(.leading, 12)
                    .padding(.trailing, 8)
                    .padding(.vertical, 7)
                    .background(.blue.opacity(0.12), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let rows = makeRows(proposal: proposal, subviews: subviews)
        return CGSize(
            width: proposal.width ?? rows.map(\.width).max() ?? 0,
            height: rows.last.map { $0.y + $0.height } ?? 0
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let rows = makeRows(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        for row in rows {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(item.size)
                )
            }
        }
    }

    private func makeRows(proposal: ProposedViewSize, subviews: Subviews) -> [FlowRow] {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var rows: [FlowRow] = []
        var currentItems: [FlowItem] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var currentHeight: CGFloat = 0
        var currentWidth: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let spacing = currentItems.isEmpty ? CGFloat(0) : horizontalSpacing

            if !currentItems.isEmpty, currentX + spacing + size.width > maxWidth {
                rows.append(FlowRow(items: currentItems, y: currentY, width: currentWidth, height: currentHeight))
                currentY += currentHeight + verticalSpacing
                currentItems = []
                currentX = 0
                currentHeight = 0
                currentWidth = 0
            }

            let x = currentItems.isEmpty ? CGFloat(0) : currentX + horizontalSpacing
            currentItems.append(FlowItem(index: index, x: x, size: size))
            currentX = x + size.width
            currentWidth = max(currentWidth, currentX)
            currentHeight = max(currentHeight, size.height)
        }

        if !currentItems.isEmpty {
            rows.append(FlowRow(items: currentItems, y: currentY, width: currentWidth, height: currentHeight))
        }

        return rows
    }
}

private struct FlowRow {
    var items: [FlowItem]
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
}

private struct FlowItem {
    var index: Int
    var x: CGFloat
    var size: CGSize
}

private extension String {
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var googleContactsDisplayLabel: String {
        switch lowercased() {
        case "home": "Home"
        case "work": "Work"
        case "other": "Other"
        case "mobile": "Mobile"
        case "main": "Main"
        case "homefax", "home_fax", "home fax": "Home Fax"
        case "workfax", "work_fax", "work fax": "Work Fax"
        case "googlevoice", "google_voice", "google voice": "Google Voice"
        case "pager": "Pager"
        default: self
        }
    }
}

private extension Array where Element == String {
    func joinedNonEmpty(separator: String) -> String {
        filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: separator)
    }
}

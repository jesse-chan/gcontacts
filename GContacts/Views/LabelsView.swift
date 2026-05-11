import SwiftUI

struct LabelsView: View {
    @Environment(ContactStore.self) private var store
    @Binding var selectedLabel: ContactLabelSelection
    let onSelectLabel: () -> Void
    @State private var newLabelName = ""
    @State private var editingLabel: ContactLabel?
    @State private var labelPendingDeletion: ContactLabel?

    private var sortedLabels: [ContactLabel] {
        store.labels.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        List {
            Section("labels.create") {
                HStack {
                    TextField("labels.name", text: $newLabelName)
                    Button {
                        Task {
                            await store.createLabel(named: newLabelName)
                            newLabelName = ""
                        }
                    } label: {
                        Label("labels.add", systemImage: "plus.circle.fill")
                    }
                    .labelStyle(.iconOnly)
                    .disabled(newLabelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section("labels.all") {
                LabelSelectionRow(
                    title: String(localized: "labels.all"),
                    subtitle: String(localized: "labels.count \(store.contacts.count)"),
                    isSelected: selectedLabel.id == nil
                ) {
                    selectedLabel = .all
                    onSelectLabel()
                }

                ForEach(sortedLabels) { label in
                    HStack(spacing: 16) {
                        LabelSelectionRow(
                            title: label.name,
                            subtitle: String(localized: "labels.count \(label.contactCount)"),
                            isSelected: selectedLabel.id == label.id
                        ) {
                            selectedLabel = ContactLabelSelection(id: label.id, name: label.name)
                            onSelectLabel()
                        }

                        Spacer()

                        Button(role: .destructive) {
                            labelPendingDeletion = label
                        } label: {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("action.delete"))

                        Button {
                            editingLabel = label
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("action.edit"))
                    }
                }
                .onDelete { offsets in
                    if let index = offsets.first {
                        labelPendingDeletion = sortedLabels[index]
                    }
                }
            }
        }
        .navigationTitle("labels.title")
        .sheet(item: $editingLabel) { label in
            LabelEditorView(label: label)
        }
        .alert(
            "labels.delete.title",
            isPresented: Binding(
                get: { labelPendingDeletion != nil },
                set: { if !$0 { labelPendingDeletion = nil } }
            ),
            presenting: labelPendingDeletion
        ) { label in
            Button("action.delete", role: .destructive) {
                Task {
                    await store.deleteLabel(label)
                    if selectedLabel.id == label.id {
                        selectedLabel = .all
                    }
                }
            }
            Button("action.cancel", role: .cancel) {}
        } message: { label in
            Text("labels.delete.message \(label.name)")
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

private struct LabelSelectionRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LabelEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ContactStore.self) private var store
    @State private var label: ContactLabel

    init(label: ContactLabel) {
        _label = State(initialValue: label)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("labels.name", text: $label.name)
            }
            .navigationTitle("labels.edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") {
                        Task {
                            if await store.updateLabel(label) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(label.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

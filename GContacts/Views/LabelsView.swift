import SwiftUI

struct LabelsView: View {
    @Environment(ContactStore.self) private var store
    @State private var newLabelName = ""
    @State private var editingLabel: ContactLabel?

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
                ForEach(store.labels) { label in
                    Button {
                        editingLabel = label
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(label.name)
                                    .foregroundStyle(.primary)
                                Text(String(localized: "labels.count \(label.contactCount)"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .onDelete { offsets in
                    Task { await store.deleteLabels(at: offsets) }
                }
            }
        }
        .navigationTitle("labels.title")
        .task {
            if store.labels.isEmpty {
                await store.load()
            }
        }
        .sheet(item: $editingLabel) { label in
            LabelEditorView(label: label)
        }
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
                            await store.updateLabel(label)
                            dismiss()
                        }
                    }
                    .disabled(label.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}


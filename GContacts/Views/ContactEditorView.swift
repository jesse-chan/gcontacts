import SwiftUI

struct ContactEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ContactStore.self) private var store
    @State private var draft: Contact

    init(contact: Contact) {
        _draft = State(initialValue: contact)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("section.names") {
                    EditableNamesView(names: $draft.names)
                }

                Section("section.labels") {
                    ForEach(store.labels) { label in
                        Toggle(label.name, isOn: Binding(
                            get: { draft.labelIDs.contains(label.id) },
                            set: { isOn in
                                if isOn {
                                    draft.labelIDs.insert(label.id)
                                } else {
                                    draft.labelIDs.remove(label.id)
                                }
                            }
                        ))
                    }
                }

                EditableLabeledValuesSection(title: "section.nicknames", values: $draft.nicknames)
                EditableLabeledValuesSection(title: "section.emails", values: $draft.emailAddresses)
                EditableLabeledValuesSection(title: "section.phones", values: $draft.phoneNumbers)
                EditableAddressesSection(addresses: $draft.addresses)
                EditableOrganizationsSection(organizations: $draft.organizations)
                EditableDatesSection(title: "section.birthdays", dates: $draft.birthdays)
                EditableEventsSection(events: $draft.events)
                EditableLabeledValuesSection(title: "section.urls", values: $draft.urls)
                EditableRelationsSection(relations: $draft.relations)
                EditableBiographiesSection(biographies: $draft.biographies)
                EditableUserDefinedSection(fields: $draft.userDefined)
            }
            .navigationTitle(draft.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") {
                        Task {
                            await store.save(draft)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

private struct EditableNamesView: View {
    @Binding var names: [ContactName]

    var body: some View {
        ForEach($names) { $name in
            TextField("name.display", text: $name.displayName)
            TextField("name.given", text: $name.givenName)
            TextField("name.middle", text: $name.middleName)
            TextField("name.family", text: $name.familyName)
            TextField("name.prefix", text: $name.honorificPrefix)
            TextField("name.suffix", text: $name.honorificSuffix)
        }
        .onDelete { names.remove(atOffsets: $0) }

        Button("action.addName") {
            names.append(ContactName())
        }
    }
}

private struct EditableLabeledValuesSection: View {
    let title: LocalizedStringKey
    @Binding var values: [LabeledValue]

    var body: some View {
        Section(title) {
            ForEach($values) { $value in
                TextField("field.label", text: $value.label)
                TextField("field.value", text: $value.value)
            }
            .onDelete { values.remove(atOffsets: $0) }

            Button("action.addField") {
                values.append(LabeledValue())
            }
        }
    }
}

private struct EditableAddressesSection: View {
    @Binding var addresses: [PostalAddress]

    var body: some View {
        Section("section.addresses") {
            ForEach($addresses) { $address in
                TextField("field.label", text: $address.label)
                TextField("address.street", text: $address.streetAddress)
                TextField("address.city", text: $address.city)
                TextField("address.region", text: $address.region)
                TextField("address.postalCode", text: $address.postalCode)
                TextField("address.country", text: $address.country)
            }
            .onDelete { addresses.remove(atOffsets: $0) }

            Button("action.addAddress") {
                addresses.append(PostalAddress())
            }
        }
    }
}

private struct EditableOrganizationsSection: View {
    @Binding var organizations: [Organization]

    var body: some View {
        Section("section.organizations") {
            ForEach($organizations) { $organization in
                TextField("organization.name", text: $organization.name)
                TextField("organization.department", text: $organization.department)
                TextField("organization.title", text: $organization.title)
            }
            .onDelete { organizations.remove(atOffsets: $0) }

            Button("action.addOrganization") {
                organizations.append(Organization())
            }
        }
    }
}

private struct EditableDatesSection: View {
    let title: LocalizedStringKey
    @Binding var dates: [ContactDate]

    var body: some View {
        Section(title) {
            ForEach($dates) { $date in
                TextField("date.year", text: $date.year)
                    .keyboardType(.numberPad)
                TextField("date.month", text: $date.month)
                    .keyboardType(.numberPad)
                TextField("date.day", text: $date.day)
                    .keyboardType(.numberPad)
            }
            .onDelete { dates.remove(atOffsets: $0) }

            Button("action.addDate") {
                dates.append(ContactDate())
            }
        }
    }
}

private struct EditableEventsSection: View {
    @Binding var events: [ContactEvent]

    var body: some View {
        Section("section.events") {
            ForEach($events) { $event in
                TextField("field.label", text: $event.label)
                TextField("date.year", text: $event.date.year)
                    .keyboardType(.numberPad)
                TextField("date.month", text: $event.date.month)
                    .keyboardType(.numberPad)
                TextField("date.day", text: $event.date.day)
                    .keyboardType(.numberPad)
            }
            .onDelete { events.remove(atOffsets: $0) }

            Button("action.addEvent") {
                events.append(ContactEvent())
            }
        }
    }
}

private struct EditableRelationsSection: View {
    @Binding var relations: [Relation]

    var body: some View {
        Section("section.relations") {
            ForEach($relations) { $relation in
                TextField("field.label", text: $relation.label)
                TextField("relation.person", text: $relation.person)
            }
            .onDelete { relations.remove(atOffsets: $0) }

            Button("action.addRelation") {
                relations.append(Relation())
            }
        }
    }
}

private struct EditableBiographiesSection: View {
    @Binding var biographies: [String]

    var body: some View {
        Section("section.biographies") {
            ForEach(biographies.indices, id: \.self) { index in
                TextEditor(text: $biographies[index])
                    .frame(minHeight: 80)
            }
            .onDelete { biographies.remove(atOffsets: $0) }

            Button("action.addBiography") {
                biographies.append("")
            }
        }
    }
}

private struct EditableUserDefinedSection: View {
    @Binding var fields: [UserDefinedField]

    var body: some View {
        Section("section.userDefined") {
            ForEach($fields) { $field in
                TextField("field.key", text: $field.key)
                TextField("field.value", text: $field.value)
            }
            .onDelete { fields.remove(atOffsets: $0) }

            Button("action.addUserDefined") {
                fields.append(UserDefinedField())
            }
        }
    }
}


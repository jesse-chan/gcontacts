import Foundation

actor MockGoogleContactsService: GoogleContactsService {
    private var contacts: [Contact]
    private var labels: [ContactLabel]

    init() {
        labels = [.friends, .work]
        contacts = [
            Contact(
                id: "sample-ada",
                resourceName: "people/sample-ada",
                etag: "sample-etag-1",
                names: [ContactName(displayName: "Ada Lovelace", givenName: "Ada", familyName: "Lovelace")],
                nicknames: [LabeledValue(label: "short", value: "Ada")],
                emailAddresses: [LabeledValue(label: "work", value: "ada@example.com")],
                phoneNumbers: [LabeledValue(label: "mobile", value: "+1 555 0100")],
                addresses: [PostalAddress(label: "home", city: "London", country: "United Kingdom")],
                organizations: [Organization(name: "Analytical Engines", title: "Researcher")],
                birthdays: [ContactDate(year: "1815", month: "12", day: "10")],
                events: [],
                urls: [LabeledValue(label: "profile", value: "https://example.com/ada")],
                relations: [Relation(label: "collaborator", person: "Charles Babbage")],
                biographies: ["First computer programmer."],
                userDefined: [UserDefinedField(key: "source", value: "sample")],
                labelIDs: ["label-friends"]
            ),
            Contact(
                id: "sample-grace",
                resourceName: "people/sample-grace",
                etag: "sample-etag-2",
                names: [ContactName(displayName: "Grace Hopper", givenName: "Grace", familyName: "Hopper")],
                nicknames: [],
                emailAddresses: [LabeledValue(label: "work", value: "grace@example.com")],
                phoneNumbers: [],
                addresses: [],
                organizations: [Organization(name: "US Navy", title: "Rear Admiral")],
                birthdays: [],
                events: [],
                urls: [],
                relations: [],
                biographies: [],
                userDefined: [],
                labelIDs: ["label-work"]
            )
        ]
    }

    func fetchContacts() async throws -> [Contact] {
        contacts
    }

    func fetchLabels() async throws -> [ContactLabel] {
        labels
    }

    func createContact(_ contact: Contact) async throws -> Contact {
        var created = contact
        created.id = UUID().uuidString
        contacts.append(created)
        recalculateCounts()
        return created
    }

    func updateContact(_ contact: Contact) async throws -> Contact {
        guard let index = contacts.firstIndex(where: { $0.id == contact.id }) else {
            throw GoogleContactsServiceError.notFound
        }
        contacts[index] = contact
        recalculateCounts()
        return contact
    }

    func deleteContact(id: Contact.ID) async throws {
        contacts.removeAll { $0.id == id }
        recalculateCounts()
    }

    func createLabel(named name: String) async throws -> ContactLabel {
        let label = ContactLabel(
            id: UUID().uuidString,
            resourceName: nil,
            name: name,
            contactCount: 0
        )
        labels.append(label)
        return label
    }

    func updateLabel(_ label: ContactLabel) async throws -> ContactLabel {
        guard let index = labels.firstIndex(where: { $0.id == label.id }) else {
            throw GoogleContactsServiceError.notFound
        }
        labels[index] = label
        return label
    }

    func deleteLabel(id: ContactLabel.ID) async throws {
        labels.removeAll { $0.id == id }
        contacts = contacts.map { contact in
            var updated = contact
            updated.labelIDs.remove(id)
            return updated
        }
    }

    private func recalculateCounts() {
        labels = labels.map { label in
            var updated = label
            updated.contactCount = contacts.filter { $0.labelIDs.contains(label.id) }.count
            return updated
        }
    }
}


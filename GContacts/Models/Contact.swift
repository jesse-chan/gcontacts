import Foundation

struct Contact: Identifiable, Hashable {
    static let starredLabelID = "contactGroups/starred"

    var id: String
    var resourceName: String?
    var etag: String?
    var sourceID: String?
    var photoURL: URL?
    var names: [ContactName]
    var nicknames: [LabeledValue]
    var emailAddresses: [LabeledValue]
    var phoneNumbers: [LabeledValue]
    var addresses: [PostalAddress]
    var organizations: [Organization]
    var birthdays: [ContactDate]
    var events: [ContactEvent]
    var urls: [LabeledValue]
    var relations: [Relation]
    var biographies: [String]
    var userDefined: [UserDefinedField]
    var labelIDs: Set<String>

    var displayName: String {
        names.first?.displayName.nilIfEmpty
            ?? emailAddresses.first?.value.nilIfEmpty
            ?? phoneNumbers.first?.value.nilIfEmpty
            ?? String(localized: "contact.unnamed")
    }

    var isStarred: Bool {
        labelIDs.contains(Self.starredLabelID)
    }

    static let empty = Contact(
        id: UUID().uuidString,
        resourceName: nil,
        etag: nil,
        sourceID: nil,
        photoURL: nil,
        names: [ContactName()],
        nicknames: [],
        emailAddresses: [],
        phoneNumbers: [],
        addresses: [],
        organizations: [],
        birthdays: [],
        events: [],
        urls: [],
        relations: [],
        biographies: [],
        userDefined: [],
        labelIDs: []
    )
}

struct ContactName: Identifiable, Hashable {
    var id = UUID().uuidString
    var displayName = ""
    var givenName = ""
    var familyName = ""
    var middleName = ""
    var honorificPrefix = ""
    var honorificSuffix = ""
}

struct LabeledValue: Identifiable, Hashable {
    var id = UUID().uuidString
    var label = ""
    var value = ""
}

struct PostalAddress: Identifiable, Hashable {
    var id = UUID().uuidString
    var label = ""
    var streetAddress = ""
    var city = ""
    var region = ""
    var postalCode = ""
    var country = ""
}

struct Organization: Identifiable, Hashable {
    var id = UUID().uuidString
    var name = ""
    var title = ""
    var department = ""
}

struct ContactDate: Identifiable, Hashable {
    var id = UUID().uuidString
    var year = ""
    var month = ""
    var day = ""
}

struct ContactEvent: Identifiable, Hashable {
    var id = UUID().uuidString
    var label = ""
    var date = ContactDate()
}

struct Relation: Identifiable, Hashable {
    var id = UUID().uuidString
    var label = ""
    var person = ""
}

struct UserDefinedField: Identifiable, Hashable {
    var id = UUID().uuidString
    var key = ""
    var value = ""
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

import Foundation

struct Contact: Identifiable, Hashable, Codable {
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

struct ContactName: Identifiable, Hashable, Codable {
    var id = UUID().uuidString
    var displayName = ""
    var givenName = ""
    var familyName = ""
    var middleName = ""
    var honorificPrefix = ""
    var honorificSuffix = ""
    var phoneticGivenName = ""
    var phoneticMiddleName = ""
    var phoneticFamilyName = ""

    init(
        id: String = UUID().uuidString,
        displayName: String = "",
        givenName: String = "",
        familyName: String = "",
        middleName: String = "",
        honorificPrefix: String = "",
        honorificSuffix: String = "",
        phoneticGivenName: String = "",
        phoneticMiddleName: String = "",
        phoneticFamilyName: String = ""
    ) {
        self.id = id
        self.displayName = displayName
        self.givenName = givenName
        self.familyName = familyName
        self.middleName = middleName
        self.honorificPrefix = honorificPrefix
        self.honorificSuffix = honorificSuffix
        self.phoneticGivenName = phoneticGivenName
        self.phoneticMiddleName = phoneticMiddleName
        self.phoneticFamilyName = phoneticFamilyName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        givenName = try container.decodeIfPresent(String.self, forKey: .givenName) ?? ""
        familyName = try container.decodeIfPresent(String.self, forKey: .familyName) ?? ""
        middleName = try container.decodeIfPresent(String.self, forKey: .middleName) ?? ""
        honorificPrefix = try container.decodeIfPresent(String.self, forKey: .honorificPrefix) ?? ""
        honorificSuffix = try container.decodeIfPresent(String.self, forKey: .honorificSuffix) ?? ""
        phoneticGivenName = try container.decodeIfPresent(String.self, forKey: .phoneticGivenName) ?? ""
        phoneticMiddleName = try container.decodeIfPresent(String.self, forKey: .phoneticMiddleName) ?? ""
        phoneticFamilyName = try container.decodeIfPresent(String.self, forKey: .phoneticFamilyName) ?? ""
    }
}

struct LabeledValue: Identifiable, Hashable, Codable {
    var id = UUID().uuidString
    var label = ""
    var value = ""
}

struct PostalAddress: Identifiable, Hashable, Codable {
    var id = UUID().uuidString
    var label = ""
    var streetAddress = ""
    var city = ""
    var region = ""
    var postalCode = ""
    var country = ""
}

struct Organization: Identifiable, Hashable, Codable {
    var id = UUID().uuidString
    var name = ""
    var title = ""
    var department = ""
}

struct ContactDate: Identifiable, Hashable, Codable {
    var id = UUID().uuidString
    var year = ""
    var month = ""
    var day = ""
}

struct ContactEvent: Identifiable, Hashable, Codable {
    var id = UUID().uuidString
    var label = ""
    var date = ContactDate()
}

struct Relation: Identifiable, Hashable, Codable {
    var id = UUID().uuidString
    var label = ""
    var person = ""
}

struct UserDefinedField: Identifiable, Hashable, Codable {
    var id = UUID().uuidString
    var key = ""
    var value = ""
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

import Foundation

final class GooglePeopleContactsService: GoogleContactsService {
    private let authService: GoogleAuthService
    private let baseURL = URL(string: "https://people.googleapis.com/v1")!
    private let session: URLSession

    private let personFields = [
        "addresses",
        "biographies",
        "birthdays",
        "emailAddresses",
        "events",
        "memberships",
        "metadata",
        "names",
        "nicknames",
        "organizations",
        "phoneNumbers",
        "photos",
        "relations",
        "urls",
        "userDefined"
    ].joined(separator: ",")

    private let updatePersonFields = [
        "addresses",
        "biographies",
        "birthdays",
        "emailAddresses",
        "events",
        "memberships",
        "names",
        "nicknames",
        "organizations",
        "phoneNumbers",
        "relations",
        "urls",
        "userDefined"
    ].joined(separator: ",")

    init(authService: GoogleAuthService, session: URLSession = .shared) {
        self.authService = authService
        self.session = session
    }

    func fetchContacts() async throws -> [Contact] {
        try await fullSyncContacts()
    }

    private func fullSyncContacts() async throws -> [Contact] {
        var pageToken: String?
        var people: [PeoplePerson] = []

        repeat {
            var components = URLComponents(url: baseURL.appending(path: "people/me/connections"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "personFields", value: personFields),
                URLQueryItem(name: "sources", value: "READ_SOURCE_TYPE_CONTACT"),
                URLQueryItem(name: "pageSize", value: "1000")
            ]
            if let pageToken {
                components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
            }

            let response: PeopleConnectionsResponse = try await send(components.url!)
            people.append(contentsOf: response.connections ?? [])
            pageToken = response.nextPageToken
        } while pageToken != nil

        return sortedContacts(people.compactMap { $0.metadata?.deleted == true ? nil : Contact(person: $0) })
    }

    func fetchLabels() async throws -> [ContactLabel] {
        var labels: [ContactLabel] = []
        var pageToken: String?

        repeat {
            var components = URLComponents(url: baseURL.appending(path: "contactGroups"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "pageSize", value: "1000"),
                URLQueryItem(name: "groupFields", value: "metadata,groupType,memberCount,name")
            ]
            if let pageToken {
                components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
            }

            let response: ContactGroupsResponse = try await send(components.url!)
            labels.append(contentsOf: (response.contactGroups ?? [])
                .filter { $0.groupType == "USER_CONTACT_GROUP" }
                .map(ContactLabel.init(group:)))
            pageToken = response.nextPageToken
        } while pageToken != nil

        return labels
    }

    func createContact(_ contact: Contact) async throws -> Contact {
        var components = URLComponents(url: baseURL.appending(path: "people:createContact"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "personFields", value: personFields),
            URLQueryItem(name: "sources", value: "READ_SOURCE_TYPE_CONTACT")
        ]

        let person = PeoplePerson(contact: contact, includeMetadata: false)
        let created: PeoplePerson = try await send(components.url!, method: "POST", body: person)
        return Contact(person: created)
    }

    func updateContact(_ contact: Contact) async throws -> Contact {
        guard let resourceName = contact.resourceName ?? contact.id.nilIfEmpty else {
            throw GooglePeopleAPIError.missingResourceName
        }

        var components = URLComponents(url: baseURL.appending(path: "\(resourceName):updateContact"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "updatePersonFields", value: updatePersonFields),
            URLQueryItem(name: "personFields", value: personFields),
            URLQueryItem(name: "sources", value: "READ_SOURCE_TYPE_CONTACT")
        ]

        let person = PeoplePerson(contact: contact, includeMetadata: true)
        let updated: PeoplePerson = try await send(components.url!, method: "PATCH", body: person)
        return Contact(person: updated)
    }

    func updateContactPhoto(_ contact: Contact, photoData: Data) async throws -> Contact {
        guard let resourceName = contact.resourceName ?? contact.id.nilIfEmpty else {
            throw GooglePeopleAPIError.missingResourceName
        }

        let url = baseURL.appending(path: "\(resourceName):updateContactPhoto")
        let body = ContactPhotoUpdateRequest(
            photoBytes: photoData.base64EncodedString(),
            personFields: personFields,
            sources: ["READ_SOURCE_TYPE_CONTACT"]
        )
        let response: ContactPhotoMutationResponse = try await send(url, method: "PATCH", body: body)
        guard let person = response.person else {
            throw GooglePeopleAPIError.invalidResponse
        }
        return Contact(person: person)
    }

    func deleteContactPhoto(_ contact: Contact) async throws -> Contact {
        guard let resourceName = contact.resourceName ?? contact.id.nilIfEmpty else {
            throw GooglePeopleAPIError.missingResourceName
        }

        var components = URLComponents(url: baseURL.appending(path: "\(resourceName):deleteContactPhoto"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "personFields", value: personFields),
            URLQueryItem(name: "sources", value: "READ_SOURCE_TYPE_CONTACT")
        ]

        let response: ContactPhotoMutationResponse = try await send(components.url!, method: "DELETE")
        guard let person = response.person else {
            throw GooglePeopleAPIError.invalidResponse
        }
        return Contact(person: person)
    }

    func deleteContact(id: Contact.ID) async throws {
        guard id.hasPrefix("people/") else {
            throw GooglePeopleAPIError.missingResourceName
        }

        let url = baseURL.appending(path: "\(id):deleteContact")
        let _: EmptyResponse = try await send(url, method: "DELETE")
    }

    func createLabel(named name: String) async throws -> ContactLabel {
        let url = baseURL.appending(path: "contactGroups")
        let body = ContactGroupMutation(contactGroup: PeopleContactGroup(name: name))
        let created: PeopleContactGroup = try await send(url, method: "POST", body: body)
        return ContactLabel(group: created)
    }

    func updateLabel(_ label: ContactLabel) async throws -> ContactLabel {
        guard let resourceName = label.resourceName ?? label.id.nilIfEmpty else {
            throw GooglePeopleAPIError.missingResourceName
        }

        let url = baseURL.appending(path: resourceName)
        let body = ContactGroupMutation(
            contactGroup: PeopleContactGroup(resourceName: resourceName, etag: label.etag, name: label.name),
            updateGroupFields: "name",
            readGroupFields: "metadata,groupType,memberCount,name"
        )
        let updated: PeopleContactGroup = try await send(url, method: "PUT", body: body)
        return ContactLabel(group: updated)
    }

    func deleteLabel(id: ContactLabel.ID) async throws {
        guard id.hasPrefix("contactGroups/") else {
            throw GooglePeopleAPIError.missingResourceName
        }

        var components = URLComponents(url: baseURL.appending(path: id), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "deleteContacts", value: "false")]
        let _: EmptyResponse = try await send(components.url!, method: "DELETE")
    }

    private func send<Response: Decodable>(
        _ url: URL,
        method: String = "GET"
    ) async throws -> Response {
        try await send(url, method: method, body: Optional<EmptyRequest>.none)
    }

    private func send<Request: Encodable, Response: Decodable>(
        _ url: URL,
        method: String = "GET",
        body: Request?
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(try await authService.freshAccessToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder.peopleAPI.encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GooglePeopleAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder.peopleAPI.decode(GoogleAPIErrorResponse.self, from: data)
            throw GooglePeopleAPIError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: apiError?.error.message ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }

        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }

        return try JSONDecoder.peopleAPI.decode(Response.self, from: data)
    }

    private func sortedContacts(_ contacts: [Contact]) -> [Contact] {
        contacts.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }
}

private struct EmptyRequest: Encodable {}

private struct EmptyResponse: Decodable {}

private struct GoogleAPIErrorResponse: Decodable {
    let error: GoogleAPIError
}

private struct GoogleAPIError: Decodable {
    let message: String
}

enum GooglePeopleAPIError: LocalizedError {
    case invalidResponse
    case missingResourceName
    case requestFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            String(localized: "peopleAPI.invalidResponse")
        case .missingResourceName:
            String(localized: "peopleAPI.missingResourceName")
        case .requestFailed(let statusCode, let message):
            String(localized: "peopleAPI.requestFailed \(statusCode) \(message)")
        }
    }
}

private struct PeopleConnectionsResponse: Decodable {
    let connections: [PeoplePerson]?
    let nextPageToken: String?
}

private struct ContactGroupsResponse: Decodable {
    let contactGroups: [PeopleContactGroup]?
    let nextPageToken: String?
}

private struct ContactGroupMutation: Encodable {
    let contactGroup: PeopleContactGroup
    var updateGroupFields: String? = nil
    var readGroupFields: String? = nil
}

private struct ContactPhotoUpdateRequest: Encodable {
    let photoBytes: String
    let personFields: String
    let sources: [String]
}

private struct ContactPhotoMutationResponse: Decodable {
    let person: PeoplePerson?
}

private struct PeoplePerson: Codable {
    var resourceName: String?
    var etag: String?
    var metadata: PeoplePersonMetadata?
    var names: [PeopleName]?
    var nicknames: [PeopleLabeledValue]?
    var emailAddresses: [PeopleLabeledValue]?
    var phoneNumbers: [PeopleLabeledValue]?
    var addresses: [PeopleAddress]?
    var organizations: [PeopleOrganization]?
    var birthdays: [PeopleBirthday]?
    var events: [PeopleEvent]?
    var urls: [PeopleLabeledValue]?
    var relations: [PeopleRelation]?
    var biographies: [PeopleBiography]?
    var userDefined: [PeopleUserDefined]?
    var memberships: [PeopleMembership]?
    var photos: [PeoplePhoto]?

    init(contact: Contact, includeMetadata: Bool) {
        resourceName = contact.resourceName
        etag = contact.etag
        metadata = includeMetadata ? PeoplePersonMetadata(contact: contact) : nil
        names = contact.names.nonEmptyPeopleValues { PeopleName(name: $0) }
        nicknames = contact.nicknames.nonEmptyPeopleValues { PeopleLabeledValue(labeledValue: $0) }
        emailAddresses = contact.emailAddresses.nonEmptyPeopleValues { PeopleLabeledValue(labeledValue: $0) }
        phoneNumbers = contact.phoneNumbers.nonEmptyPeopleValues { PeopleLabeledValue(labeledValue: $0) }
        addresses = contact.addresses.nonEmptyPeopleValues { PeopleAddress(address: $0) }
        organizations = contact.organizations.nonEmptyPeopleValues { PeopleOrganization(organization: $0) }
        birthdays = contact.birthdays.nonEmptyPeopleValues { PeopleBirthday(date: $0) }
        events = contact.events.nonEmptyPeopleValues { PeopleEvent(event: $0) }
        urls = contact.urls.nonEmptyPeopleValues { PeopleLabeledValue(labeledValue: $0) }
        relations = contact.relations.nonEmptyPeopleValues { PeopleRelation(relation: $0) }
        biographies = contact.biographies.nonEmptyPeopleValues { PeopleBiography(value: $0) }
        userDefined = contact.userDefined.nonEmptyPeopleValues { PeopleUserDefined(field: $0) }
        memberships = contact.labelIDs.sorted().map { PeopleMembership(contactGroupResourceName: $0) }
        photos = nil
    }
}

private struct PeoplePersonMetadata: Codable {
    var sources: [PeopleSource]?
    var deleted: Bool?

    init(sources: [PeopleSource]? = nil) {
        self.sources = sources
    }

    init(contact: Contact) {
        sources = [PeopleSource(type: "CONTACT", id: contact.sourceID, etag: contact.etag)]
        deleted = nil
    }
}

private struct PeopleSource: Codable {
    var type: String? = nil
    var id: String? = nil
    var etag: String? = nil
}

private struct PeopleName: Codable {
    var displayName: String?
    var givenName: String?
    var familyName: String?
    var middleName: String?
    var honorificPrefix: String?
    var honorificSuffix: String?
    var phoneticGivenName: String?
    var phoneticMiddleName: String?
    var phoneticFamilyName: String?

    init(name: ContactName) {
        displayName = name.displayName.nilIfEmpty
        givenName = name.givenName.nilIfEmpty
        familyName = name.familyName.nilIfEmpty
        middleName = name.middleName.nilIfEmpty
        honorificPrefix = name.honorificPrefix.nilIfEmpty
        honorificSuffix = name.honorificSuffix.nilIfEmpty
        phoneticGivenName = name.phoneticGivenName.nilIfEmpty
        phoneticMiddleName = name.phoneticMiddleName.nilIfEmpty
        phoneticFamilyName = name.phoneticFamilyName.nilIfEmpty
    }
}

private struct PeopleLabeledValue: Codable {
    var type: String?
    var value: String?

    init(labeledValue: LabeledValue) {
        type = labeledValue.label.nilIfEmpty
        value = labeledValue.value.nilIfEmpty
    }
}

private struct PeopleAddress: Codable {
    var type: String?
    var streetAddress: String?
    var extendedAddress: String?
    var city: String?
    var region: String?
    var postalCode: String?
    var poBox: String?
    var country: String?
    var countryCode: String?

    init(address: PostalAddress) {
        type = address.label.nilIfEmpty
        streetAddress = address.streetAddress.nilIfEmpty
        extendedAddress = address.extendedAddress.nilIfEmpty
        city = address.city.nilIfEmpty
        region = address.region.nilIfEmpty
        postalCode = address.postalCode.nilIfEmpty
        poBox = address.poBox.nilIfEmpty
        country = address.country.nilIfEmpty
        countryCode = address.countryCode.nilIfEmpty
    }
}

private struct PeopleOrganization: Codable {
    var name: String?
    var title: String?
    var department: String?

    init(organization: Organization) {
        name = organization.name.nilIfEmpty
        title = organization.title.nilIfEmpty
        department = organization.department.nilIfEmpty
    }
}

private struct PeopleBirthday: Codable {
    var date: PeopleDate?

    init(date: ContactDate) {
        self.date = PeopleDate(contactDate: date)
    }
}

private struct PeopleEvent: Codable {
    var type: String?
    var date: PeopleDate?

    init(event: ContactEvent) {
        type = event.label.nilIfEmpty
        date = PeopleDate(contactDate: event.date)
    }
}

private struct PeopleDate: Codable {
    var year: Int?
    var month: Int?
    var day: Int?

    init(contactDate: ContactDate) {
        year = Int(contactDate.year)
        month = Int(contactDate.month)
        day = Int(contactDate.day)
    }
}

private struct PeopleRelation: Codable {
    var type: String?
    var person: String?

    init(relation: Relation) {
        type = relation.label.nilIfEmpty
        person = relation.person.nilIfEmpty
    }
}

private struct PeopleBiography: Codable {
    var value: String?

    init(value: String) {
        self.value = value.nilIfEmpty
    }
}

private struct PeopleUserDefined: Codable {
    var key: String?
    var value: String?

    init(field: UserDefinedField) {
        key = field.key.nilIfEmpty
        value = field.value.nilIfEmpty
    }
}

private struct PeopleMembership: Codable {
    var contactGroupMembership: PeopleContactGroupMembership?

    init(contactGroupResourceName: String) {
        contactGroupMembership = PeopleContactGroupMembership(contactGroupResourceName: contactGroupResourceName)
    }
}

private struct PeopleContactGroupMembership: Codable {
    var contactGroupResourceName: String?
}

private struct PeoplePhoto: Codable {
    var url: String?
    var `default`: Bool?
}

private struct PeopleContactGroup: Codable {
    var resourceName: String? = nil
    var etag: String? = nil
    var name: String? = nil
    var groupType: String? = nil
    var memberCount: Int? = nil
}

private extension Contact {
    init(person: PeoplePerson) {
        let contactSource = person.metadata?.sources?.first { $0.type == "CONTACT" }
        let resourceName = person.resourceName

        self.init(
            id: resourceName ?? UUID().uuidString,
            resourceName: resourceName,
            etag: contactSource?.etag ?? person.etag,
            sourceID: contactSource?.id,
            photoURL: person.photos?.first { $0.default != true }?.url.flatMap(URL.init(string:)),
            names: person.names?.map(ContactName.init(name:)) ?? [],
            nicknames: person.nicknames?.map(LabeledValue.init(labeledValue:)) ?? [],
            emailAddresses: person.emailAddresses?.map(LabeledValue.init(labeledValue:)) ?? [],
            phoneNumbers: person.phoneNumbers?.map(LabeledValue.init(labeledValue:)) ?? [],
            addresses: person.addresses?.map(PostalAddress.init(address:)) ?? [],
            organizations: person.organizations?.map(Organization.init(organization:)) ?? [],
            birthdays: person.birthdays?.compactMap(ContactDate.init(birthday:)) ?? [],
            events: person.events?.compactMap(ContactEvent.init(event:)) ?? [],
            urls: person.urls?.map(LabeledValue.init(labeledValue:)) ?? [],
            relations: person.relations?.map(Relation.init(relation:)) ?? [],
            biographies: person.biographies?.compactMap(\.value) ?? [],
            userDefined: person.userDefined?.map(UserDefinedField.init(field:)) ?? [],
            labelIDs: Set(person.memberships?.compactMap(\.contactGroupMembership?.contactGroupResourceName) ?? [])
        )
    }
}

private extension ContactName {
    init(name: PeopleName) {
        self.init(
            displayName: name.displayName ?? "",
            givenName: name.givenName ?? "",
            familyName: name.familyName ?? "",
            middleName: name.middleName ?? "",
            honorificPrefix: name.honorificPrefix ?? "",
            honorificSuffix: name.honorificSuffix ?? "",
            phoneticGivenName: name.phoneticGivenName ?? "",
            phoneticMiddleName: name.phoneticMiddleName ?? "",
            phoneticFamilyName: name.phoneticFamilyName ?? ""
        )
    }
}

private extension LabeledValue {
    init(labeledValue: PeopleLabeledValue) {
        self.init(label: (labeledValue.type ?? "").googleContactsDisplayLabel, value: labeledValue.value ?? "")
    }
}

private extension String {
    var googleContactsDisplayLabel: String {
        switch lowercased() {
        case "home": "Home"
        case "work": "Work"
        case "other": "Other"
        case "mobile": "Mobile"
        case "main": "Main"
        case "homefax", "home_fax": "Home Fax"
        case "workfax", "work_fax": "Work Fax"
        case "googlevoice", "google_voice": "Google Voice"
        case "pager": "Pager"
        default: self
        }
    }
}

private extension PostalAddress {
    init(address: PeopleAddress) {
        self.init(
            label: address.type ?? "",
            streetAddress: address.streetAddress ?? "",
            extendedAddress: address.extendedAddress ?? "",
            city: address.city ?? "",
            region: address.region ?? "",
            postalCode: address.postalCode ?? "",
            poBox: address.poBox ?? "",
            country: address.country ?? "",
            countryCode: address.countryCode ?? ""
        )
    }
}

private extension Organization {
    init(organization: PeopleOrganization) {
        self.init(name: organization.name ?? "", title: organization.title ?? "", department: organization.department ?? "")
    }
}

private extension ContactDate {
    init?(birthday: PeopleBirthday) {
        guard let date = birthday.date else { return nil }
        self.init(date: date)
    }

    init(date: PeopleDate) {
        self.init(
            year: date.year.map(String.init) ?? "",
            month: date.month.map(String.init) ?? "",
            day: date.day.map(String.init) ?? ""
        )
    }
}

private extension ContactEvent {
    init?(event: PeopleEvent) {
        guard let date = event.date else { return nil }
        self.init(label: event.type ?? "", date: ContactDate(date: date))
    }
}

private extension Relation {
    init(relation: PeopleRelation) {
        self.init(label: relation.type ?? "", person: relation.person ?? "")
    }
}

private extension UserDefinedField {
    init(field: PeopleUserDefined) {
        self.init(key: field.key ?? "", value: field.value ?? "")
    }
}

private extension ContactLabel {
    init(group: PeopleContactGroup) {
        let resourceName = group.resourceName
        self.init(
            id: resourceName ?? UUID().uuidString,
            resourceName: resourceName,
            etag: group.etag,
            name: group.name ?? "",
            contactCount: group.memberCount ?? 0
        )
    }
}

private extension Array {
    func nonEmptyPeopleValues<Value>(_ transform: (Element) -> Value) -> [Value]? {
        isEmpty ? nil : map(transform)
    }
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

private extension JSONEncoder {
    static var peopleAPI: JSONEncoder {
        JSONEncoder()
    }
}

private extension JSONDecoder {
    static var peopleAPI: JSONDecoder {
        JSONDecoder()
    }
}

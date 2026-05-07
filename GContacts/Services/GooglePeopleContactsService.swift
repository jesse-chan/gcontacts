import Foundation

final class GooglePeopleContactsService: GoogleContactsService {
    private let authService: GoogleAuthService
    private let baseURL = URL(string: "https://people.googleapis.com/v1")!
    private let session: URLSession
    private let defaults: UserDefaults

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

    init(authService: GoogleAuthService, session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.authService = authService
        self.session = session
        self.defaults = defaults
    }

    func fetchContacts() async throws -> [Contact] {
        let cacheKey = await contactCacheKey()

        guard
            let syncToken = defaults.string(forKey: cacheKey.syncToken),
            var cachedContacts = cachedContacts(forKey: cacheKey.contacts)
        else {
            return try await fullSyncContacts(cacheKey: cacheKey)
        }

        do {
            let sync = try await fetchContactChanges(syncToken: syncToken)
            apply(sync.people, to: &cachedContacts)
            let mergedContacts = sortedContacts(cachedContacts)
            save(mergedContacts, syncToken: sync.nextSyncToken, cacheKey: cacheKey)
            return mergedContacts
        } catch GooglePeopleAPIError.requestFailed(let statusCode, let message)
            where statusCode == 400 && message.isExpiredSyncTokenMessage {
            defaults.removeObject(forKey: cacheKey.syncToken)
            defaults.removeObject(forKey: cacheKey.contacts)
            return try await fullSyncContacts(cacheKey: cacheKey)
        }
    }

    private func fullSyncContacts(cacheKey: ContactCacheKey) async throws -> [Contact] {
        var pageToken: String?
        var people: [PeoplePerson] = []
        var nextSyncToken: String?

        repeat {
            var components = URLComponents(url: baseURL.appending(path: "people/me/connections"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "personFields", value: personFields),
                URLQueryItem(name: "sources", value: "READ_SOURCE_TYPE_CONTACT"),
                URLQueryItem(name: "pageSize", value: "1000"),
                URLQueryItem(name: "requestSyncToken", value: "true")
            ]
            if let pageToken {
                components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
            }

            let response: PeopleConnectionsResponse = try await send(components.url!)
            people.append(contentsOf: response.connections ?? [])
            pageToken = response.nextPageToken
            nextSyncToken = response.nextSyncToken ?? nextSyncToken
        } while pageToken != nil

        let contacts = sortedContacts(people.compactMap { $0.metadata?.deleted == true ? nil : Contact(person: $0) })
        save(contacts, syncToken: nextSyncToken, cacheKey: cacheKey)
        return contacts
    }

    private func fetchContactChanges(syncToken: String) async throws -> (people: [PeoplePerson], nextSyncToken: String?) {
        var pageToken: String?
        var people: [PeoplePerson] = []
        var nextSyncToken: String?

        repeat {
            var components = URLComponents(url: baseURL.appending(path: "people/me/connections"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "personFields", value: personFields),
                URLQueryItem(name: "sources", value: "READ_SOURCE_TYPE_CONTACT"),
                URLQueryItem(name: "pageSize", value: "1000"),
                URLQueryItem(name: "requestSyncToken", value: "true"),
                URLQueryItem(name: "syncToken", value: syncToken)
            ]
            if let pageToken {
                components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
            }

            let response: PeopleConnectionsResponse = try await send(components.url!)
            people.append(contentsOf: response.connections ?? [])
            pageToken = response.nextPageToken
            nextSyncToken = response.nextSyncToken ?? nextSyncToken
        } while pageToken != nil

        return (people, nextSyncToken)
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
        let createdContact = Contact(person: created)
        await replaceCachedContact(createdContact)
        return createdContact
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
        let updatedContact = Contact(person: updated)
        await replaceCachedContact(updatedContact)
        return updatedContact
    }

    func deleteContact(id: Contact.ID) async throws {
        guard id.hasPrefix("people/") else {
            throw GooglePeopleAPIError.missingResourceName
        }

        let url = baseURL.appending(path: "\(id):deleteContact")
        let _: EmptyResponse = try await send(url, method: "DELETE")
        await removeCachedContact(id: id)
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

    private func contactCacheKey() async -> ContactCacheKey {
        let accountID = await MainActor.run {
            authService.user?.userID ?? authService.user?.email ?? "default"
        }
        return ContactCacheKey(accountID: accountID)
    }

    private func cachedContacts(forKey key: String) -> [Contact]? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder.peopleAPI.decode([Contact].self, from: data)
    }

    private func save(_ contacts: [Contact], syncToken: String?, cacheKey: ContactCacheKey) {
        if let data = try? JSONEncoder.peopleAPI.encode(contacts) {
            defaults.set(data, forKey: cacheKey.contacts)
        }

        if let syncToken {
            defaults.set(syncToken, forKey: cacheKey.syncToken)
        }
    }

    private func apply(_ people: [PeoplePerson], to contacts: inout [Contact]) {
        for person in people {
            guard let id = person.resourceName else { continue }
            if person.metadata?.deleted == true {
                contacts.removeAll { $0.id == id || $0.resourceName == id }
                continue
            }

            replace(Contact(person: person), in: &contacts)
        }
    }

    private func replace(_ contact: Contact, in contacts: inout [Contact]) {
        guard let index = contacts.firstIndex(where: { $0.id == contact.id }) else {
            contacts.append(contact)
            return
        }
        contacts[index] = contact
    }

    private func replaceCachedContact(_ contact: Contact) async {
        let cacheKey = await contactCacheKey()
        guard var contacts = cachedContacts(forKey: cacheKey.contacts) else { return }
        replace(contact, in: &contacts)
        save(sortedContacts(contacts), syncToken: nil, cacheKey: cacheKey)
    }

    private func removeCachedContact(id: Contact.ID) async {
        let cacheKey = await contactCacheKey()
        guard var contacts = cachedContacts(forKey: cacheKey.contacts) else { return }
        contacts.removeAll { $0.id == id || $0.resourceName == id }
        save(sortedContacts(contacts), syncToken: nil, cacheKey: cacheKey)
    }

    private func sortedContacts(_ contacts: [Contact]) -> [Contact] {
        contacts.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }
}

private struct ContactCacheKey {
    let accountID: String

    var contacts: String {
        "googlePeopleContacts.contacts.\(accountID)"
    }

    var syncToken: String {
        "googlePeopleContacts.syncToken.\(accountID)"
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
    let nextSyncToken: String?
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

    init(name: ContactName) {
        displayName = name.displayName.nilIfEmpty
        givenName = name.givenName.nilIfEmpty
        familyName = name.familyName.nilIfEmpty
        middleName = name.middleName.nilIfEmpty
        honorificPrefix = name.honorificPrefix.nilIfEmpty
        honorificSuffix = name.honorificSuffix.nilIfEmpty
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
    var city: String?
    var region: String?
    var postalCode: String?
    var country: String?

    init(address: PostalAddress) {
        type = address.label.nilIfEmpty
        streetAddress = address.streetAddress.nilIfEmpty
        city = address.city.nilIfEmpty
        region = address.region.nilIfEmpty
        postalCode = address.postalCode.nilIfEmpty
        country = address.country.nilIfEmpty
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
            honorificSuffix: name.honorificSuffix ?? ""
        )
    }
}

private extension LabeledValue {
    init(labeledValue: PeopleLabeledValue) {
        self.init(label: labeledValue.type ?? "", value: labeledValue.value ?? "")
    }
}

private extension PostalAddress {
    init(address: PeopleAddress) {
        self.init(
            label: address.type ?? "",
            streetAddress: address.streetAddress ?? "",
            city: address.city ?? "",
            region: address.region ?? "",
            postalCode: address.postalCode ?? "",
            country: address.country ?? ""
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

    var isExpiredSyncTokenMessage: Bool {
        localizedCaseInsensitiveContains("EXPIRED_SYNC_TOKEN")
            || localizedCaseInsensitiveContains("sync token is expired")
            || localizedCaseInsensitiveContains("expired sync token")
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

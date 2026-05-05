import Foundation

protocol GoogleContactsService: Sendable {
    func fetchContacts() async throws -> [Contact]
    func fetchLabels() async throws -> [ContactLabel]
    func createContact(_ contact: Contact) async throws -> Contact
    func updateContact(_ contact: Contact) async throws -> Contact
    func deleteContact(id: Contact.ID) async throws
    func createLabel(named name: String) async throws -> ContactLabel
    func updateLabel(_ label: ContactLabel) async throws -> ContactLabel
    func deleteLabel(id: ContactLabel.ID) async throws
}

enum GoogleContactsServiceError: LocalizedError {
    case notFound

    var errorDescription: String? {
        switch self {
        case .notFound:
            String(localized: "error.notFound")
        }
    }
}


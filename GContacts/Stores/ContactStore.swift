import Foundation
import Observation

@MainActor
@Observable
final class ContactStore {
    private let service: GoogleContactsService
    private(set) var contacts: [Contact] = []
    private(set) var labels: [ContactLabel] = []
    var isLoading = false
    var errorMessage: String?

    init(service: GoogleContactsService) {
        self.service = service
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let fetchedContacts = service.fetchContacts()
            async let fetchedLabels = service.fetchLabels()
            contacts = try await fetchedContacts
            labels = try await fetchedLabels
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func clear() {
        contacts = []
        labels = []
        errorMessage = nil
        isLoading = false
    }

    @discardableResult
    func save(_ contact: Contact) async -> Contact? {
        do {
            if contacts.contains(where: { $0.id == contact.id }) {
                let updated = try await service.updateContact(contact)
                replace(updated)
                labels = try await service.fetchLabels()
                return updated
            } else {
                let created = try await service.createContact(contact)
                contacts.append(created)
                labels = try await service.fetchLabels()
                return created
            }
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteContacts(at offsets: IndexSet) async {
        let contactsToDelete = offsets.map { contacts[$0] }
        await delete(contactsToDelete)
    }

    func delete(_ contact: Contact) async {
        await delete([contact])
    }

    func delete(_ contactsToDelete: [Contact]) async {
        do {
            for contact in contactsToDelete {
                try await service.deleteContact(id: contact.resourceName ?? contact.id)
            }
            let idsToDelete = Set(contactsToDelete.map(\.id))
            contacts.removeAll { idsToDelete.contains($0.id) }
            labels = try await service.fetchLabels()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createLabel(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            let label = try await service.createLabel(named: trimmed)
            labels.append(label)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateLabel(_ label: ContactLabel) async {
        do {
            let updated = try await service.updateLabel(label)
            if let index = labels.firstIndex(where: { $0.id == updated.id }) {
                labels[index] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteLabels(at offsets: IndexSet) async {
        do {
            for index in offsets {
                try await service.deleteLabel(id: labels[index].id)
            }
            labels.remove(atOffsets: offsets)
            contacts = try await service.fetchContacts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func labelNames(for ids: Set<String>) -> String {
        labels
            .filter { ids.contains($0.id) }
            .map(\.name)
            .sorted()
            .joined(separator: ", ")
    }

    private func replace(_ contact: Contact) {
        guard let index = contacts.firstIndex(where: { $0.id == contact.id }) else {
            contacts.append(contact)
            return
        }
        contacts[index] = contact
    }
}

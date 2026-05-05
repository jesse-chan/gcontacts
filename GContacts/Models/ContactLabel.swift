import Foundation

struct ContactLabel: Identifiable, Hashable {
    var id: String
    var resourceName: String?
    var name: String
    var contactCount: Int

    static let friends = ContactLabel(
        id: "label-friends",
        resourceName: "contactGroups/friends",
        name: String(localized: "sample.label.friends"),
        contactCount: 1
    )

    static let work = ContactLabel(
        id: "label-work",
        resourceName: "contactGroups/work",
        name: String(localized: "sample.label.work"),
        contactCount: 1
    )
}


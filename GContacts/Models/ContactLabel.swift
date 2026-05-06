import Foundation

struct ContactLabel: Identifiable, Hashable {
    var id: String
    var resourceName: String?
    var etag: String?
    var name: String
    var contactCount: Int

    static let friends = ContactLabel(
        id: "label-friends",
        resourceName: "contactGroups/friends",
        etag: "sample-label-etag-1",
        name: String(localized: "sample.label.friends"),
        contactCount: 1
    )

    static let work = ContactLabel(
        id: "label-work",
        resourceName: "contactGroups/work",
        etag: "sample-label-etag-2",
        name: String(localized: "sample.label.work"),
        contactCount: 1
    )
}

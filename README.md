# GContacts

GContacts is a SwiftUI iOS app scaffold for managing Google Contacts and contact labels.

## Current scope

- Native iOS app project: `GContacts.xcodeproj`
- SwiftUI tabs for Contacts, Labels, and Settings
- Mock CRUD flow for contacts and labels
- Contact model coverage for Google People-style fields:
  - names, nicknames, emails, phones, addresses, organizations
  - birthdays, events, URLs, relations, biographies, custom fields
  - label membership
- Theme setting: system, light, dark
- Localization resources:
  - English
  - Traditional Chinese

## Build

```sh
xcodebuild -project GContacts.xcodeproj \
  -scheme GContacts \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath ./.DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Next integration point

`GoogleContactsService` is the boundary for replacing mock data with real Google integration.
The next production step is to add Google OAuth sign-in, then implement the service with the Google People API:

- `people.connections.list` for contacts
- `people.createContact`
- `people.updateContact`
- `people.deleteContact`
- `contactGroups.list`
- `contactGroups.create`
- `contactGroups.update`
- `contactGroups.delete`
- `contactGroups.members.modify`


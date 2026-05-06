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

`GoogleAuthService` owns Google Sign-In and token refresh. Before running a real sign-in flow, create an iOS OAuth client in Google Cloud for bundle ID `com.jessechan.gcontacts`, then set these target build settings:

- `GOOGLE_IOS_CLIENT_ID`
- `GOOGLE_REVERSED_CLIENT_ID`

`GoogleContactsService` is the boundary for replacing mock data with real Google People API integration:

- `people.connections.list` for contacts
- `people.createContact`
- `people.updateContact`
- `people.deleteContact`
- `contactGroups.list`
- `contactGroups.create`
- `contactGroups.update`
- `contactGroups.delete`
- `contactGroups.members.modify`

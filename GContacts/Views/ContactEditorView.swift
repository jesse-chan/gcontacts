import PhotosUI
import PhoneNumberKit
import SwiftUI
import UIKit

struct ContactEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ContactStore.self) private var store
    private let originalDraft: Contact
    @State private var draft: Contact
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoImage: UIImage?
    @State private var selectedPhotoData: Data?
    @State private var removesPhoto = false
    @State private var isShowingPhotoActions = false
    @State private var isShowingPhotoPicker = false
    @State private var isShowingDiscardConfirmation = false
    @State private var isSaving = false
    @State private var showsAllNameFields = false
    @State private var validationMessage: String?

    init(contact: Contact) {
        let normalized = contact.normalizedForEditing()
        originalDraft = normalized
        _draft = State(initialValue: normalized)
    }

    var body: some View {
        NavigationStack {
            Form {
                EditableContactPhotoView(
                    contact: draft,
                    selectedImage: selectedPhotoImage,
                    removesPhoto: removesPhoto
                ) {
                    isShowingPhotoActions = true
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 0)
                .padding(.bottom, 16)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)

                Section {
                    EditableNameView(
                        name: nameBinding,
                        nickname: nicknameBinding,
                        showsAllFields: showsAllNameFields
                    )
                } header: {
                    ExpandableSectionHeader(
                        title: "section.names",
                        isExpanded: showsAllNameFields
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showsAllNameFields.toggle()
                        }
                    }
                }

                EditableOrganizationsSection(organizations: $draft.organizations)
                EditableEmailsSection(values: $draft.emailAddresses)
                EditablePhonesSection(values: $draft.phoneNumbers)
                EditableAddressesSection(addresses: $draft.addresses)
                EditableDatesSection(title: "section.birthdays", dates: $draft.birthdays)
                EditableEventsSection(events: $draft.events)
                EditableWebsitesSection(values: $draft.urls)
                EditableRelationsSection(relations: $draft.relations)
                EditableUserDefinedSection(fields: $draft.userDefined)
                EditableBiographiesSection(biographies: $draft.biographies)
            }
            .navigationTitle(draft.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") {
                        Task {
                            await save()
                        }
                    }
                    .disabled(!hasChanges || isSaving)
                }
            }
            .alert("photo.edit", isPresented: $isShowingPhotoActions) {
                Button("photo.change") {
                    isShowingPhotoPicker = true
                }

                if draft.photoURL != nil || selectedPhotoImage != nil || removesPhoto {
                    Button("photo.remove", role: .destructive) {
                        selectedPhotoItem = nil
                        selectedPhotoImage = nil
                        selectedPhotoData = nil
                        removesPhoto = true
                    }
                }

                Button("action.cancel", role: .cancel) {}
            }
            .photosPicker(isPresented: $isShowingPhotoPicker, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { _, item in
                Task { await loadSelectedPhoto(item) }
            }
            .alert("error.title", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("action.ok", role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
            .alert("warning.title", isPresented: Binding(
                get: { validationMessage != nil },
                set: { if !$0 { validationMessage = nil } }
            )) {
                Button("action.ok", role: .cancel) {}
            } message: {
                Text(validationMessage ?? "")
            }
            .alert("discardChanges.title", isPresented: $isShowingDiscardConfirmation) {
                Button("discardChanges.confirm", role: .destructive) {
                    dismiss()
                }
                Button("action.cancel", role: .cancel) {}
            } message: {
                Text("discardChanges.message")
            }
        }
    }

    private var hasChanges: Bool {
        draft != originalDraft || selectedPhotoData != nil || removesPhoto
    }

    private func cancel() {
        if hasChanges {
            isShowingDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    private func loadSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }

        do {
            guard
                let data = try await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data),
                let photoData = image.scaledJPEGData(maxPixelLength: 1024, compressionQuality: 0.85),
                let previewImage = UIImage(data: photoData)
            else {
                return
            }

            selectedPhotoImage = previewImage
            selectedPhotoData = photoData
            removesPhoto = false
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        draft = draft.normalizedForEditing()
        guard validateForm() else { return }
        guard var saved = await store.save(draft) else { return }

        if removesPhoto {
            guard let updated = await store.deletePhoto(saved) else { return }
            saved = updated
        }

        if let selectedPhotoData {
            guard await store.updatePhoto(saved, photoData: selectedPhotoData) != nil else { return }
        }

        dismiss()
    }

    private func validateForm() -> Bool {
        let hasInvalidBirthday = draft.birthdays.contains { !$0.hasRequiredMonthAndDay }
        let hasInvalidEvent = draft.events.contains { !$0.date.hasRequiredMonthAndDay }

        guard !hasInvalidBirthday && !hasInvalidEvent else {
            validationMessage = String(localized: "date.validation.monthDayRequired")
            return false
        }

        guard !draft.userDefined.contains(where: { $0.requiresLabel }) else {
            validationMessage = String(localized: "customField.validation.labelRequired")
            return false
        }

        return true
    }

    private var nameBinding: Binding<ContactName> {
        Binding {
            draft.names.first ?? ContactName()
        } set: { name in
            draft.names = [name]
        }
    }

    private var nicknameBinding: Binding<String> {
        Binding {
            draft.nicknames.first?.value ?? ""
        } set: { nickname in
            let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            draft.nicknames = trimmed.isEmpty ? [] : [LabeledValue(value: nickname)]
        }
    }
}

private struct EditableContactPhotoView: View {
    let contact: Contact
    let selectedImage: UIImage?
    let removesPhoto: Bool
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            ZStack(alignment: .bottomTrailing) {
                avatar
                    .frame(width: 136, height: 136)
                    .clipShape(Circle())

                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 34, height: 34)
                    .background(.regularMaterial, in: Circle())
            }
            .frame(width: 152, height: 152)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("photo.edit"))
    }

    @ViewBuilder
    private var avatar: some View {
        if let selectedImage {
            Image(uiImage: selectedImage)
                .resizable()
                .scaledToFill()
        } else {
            ContactAvatarView(contact: previewContact, size: 136, showsStar: false)
        }
    }

    private var previewContact: Contact {
        var preview = contact
        if removesPhoto {
            preview.photoURL = nil
        }
        return preview
    }
}

private struct ExpandableSectionHeader: View {
    let title: LocalizedStringKey
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button(action: onToggle) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(isExpanded ? "name.hideAllFields" : "name.showAllFields"))
        }
    }
}

private struct EditableNameView: View {
    @Binding var name: ContactName
    @Binding var nickname: String
    let showsAllFields: Bool

    var body: some View {
        if showsAllFields {
            TextField("name.prefix", text: $name.honorificPrefix)
        }

        TextField("name.given", text: $name.givenName)

        if showsAllFields {
            TextField("name.middle", text: $name.middleName)
        }

        TextField("name.family", text: $name.familyName)

        if showsAllFields {
            TextField("name.suffix", text: $name.honorificSuffix)
            TextField("name.phoneticGiven", text: $name.phoneticGivenName)
            TextField("name.phoneticMiddle", text: $name.phoneticMiddleName)
            TextField("name.phoneticFamily", text: $name.phoneticFamilyName)
            TextField("section.nicknames", text: $nickname)
        }
    }
}

private struct EditableLabeledValuesSection: View {
    let title: LocalizedStringKey
    @Binding var values: [LabeledValue]
    @State private var valueFocusRequest: String?

    var body: some View {
        Section(title) {
            ForEach($values) { $value in
                TextField("field.label", text: $value.label)
                TextField("field.value", text: $value.value)
                    .focusWhenRequested(fieldID: value.id, request: valueFocusRequest)
            }
            .onDelete { values.remove(atOffsets: $0) }

            Button("action.addField") {
                let newValue = LabeledValue()
                values.append(newValue)
                valueFocusRequest = newValue.id
            }
        }
    }
}

private struct EditableEmailsSection: View {
    @Binding var values: [LabeledValue]
    @State private var emailValueFocusRequest: String?

    var body: some View {
        Section("section.emails") {
            ForEach($values) { $value in
                EditableEmailRow(
                    value: $value,
                    valueFocusRequest: emailValueFocusRequest
                ) {
                    values.removeAll { $0.id == value.id }
                }
            }

            Button("email.add") {
                let newEmail = LabeledValue()
                values.append(newEmail)
                emailValueFocusRequest = newEmail.id
            }
        }
    }
}

private struct EditableWebsitesSection: View {
    @Binding var values: [LabeledValue]
    @State private var websiteValueFocusRequest: String?

    var body: some View {
        Section("section.urls") {
            ForEach($values) { $value in
                EditableWebsiteRow(
                    value: $value,
                    valueFocusRequest: websiteValueFocusRequest
                ) {
                    values.removeAll { $0.id == value.id }
                }
            }
            .onDelete { values.remove(atOffsets: $0) }

            Button("website.add") {
                let newWebsite = LabeledValue()
                values.append(newWebsite)
                websiteValueFocusRequest = newWebsite.id
            }
        }
    }
}

private struct EditableWebsiteRow: View {
    @Binding var value: LabeledValue
    let valueFocusRequest: String?
    let onDelete: () -> Void

    private let labelOptions = [
        LabelOption(title: "label.profile", value: "Profile"),
        LabelOption(title: "label.blog", value: "Blog"),
        LabelOption(title: "label.homePage", value: "Home Page"),
        LabelOption(title: "label.work", value: "Work")
    ]

    var body: some View {
        EditableLabeledInputRow(
            value: $value,
            valueTitle: "section.urls",
            presetLabels: labelOptions,
            keyboardType: .URL,
            textCapitalization: .never,
            removeLabel: "website.remove",
            valueFocusRequest: valueFocusRequest,
            onDelete: onDelete
        )
    }
}

private struct EditablePhonesSection: View {
    @Binding var values: [LabeledValue]
    @State private var phoneValueFocusRequest: String?

    var body: some View {
        Section("section.phones") {
            ForEach($values) { $value in
                EditablePhoneRow(
                    value: $value,
                    presetLabels: phoneLabelOptions,
                    valueFocusRequest: phoneValueFocusRequest
                ) {
                    values.removeAll { $0.id == value.id }
                }
            }

            Button("phone.add") {
                let newPhone = LabeledValue()
                values.append(newPhone)
                phoneValueFocusRequest = newPhone.id
            }
        }
    }

    private var phoneLabelOptions: [LabelOption] {
        [
            LabelOption(title: "label.home", value: "Home"),
            LabelOption(title: "label.work", value: "Work"),
            LabelOption(title: "label.other", value: "Other"),
            LabelOption(title: "label.mobile", value: "Mobile"),
            LabelOption(title: "label.main", value: "Main"),
            LabelOption(title: "label.homeFax", value: "Home Fax"),
            LabelOption(title: "label.workFax", value: "Work Fax"),
            LabelOption(title: "label.googleVoice", value: "Google Voice"),
            LabelOption(title: "label.pager", value: "Pager")
        ]
    }
}

private struct EditablePhoneRow: View {
    @Binding var value: LabeledValue
    let presetLabels: [LabelOption]
    let valueFocusRequest: String?
    let onDelete: () -> Void
    @State private var isPickingCountry = false
    @State private var selectedCountryOverride: PhoneCountry?
    @State private var isFormattingPhone = false

    private var selectedCountry: PhoneCountry {
        selectedCountryOverride ?? PhoneCountry.matching(phoneNumber: value.value) ?? .taiwan
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("field.label", text: labelBinding)
                .textInputAutocapitalization(.words)

            Menu {
                ForEach(presetLabels) { label in
                    Button(label.title) {
                        value.label = label.value
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Text("🅧")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("phone.remove"))
        }

        HStack(spacing: 8) {
            Button {
                isPickingCountry = true
            } label: {
                HStack(spacing: 6) {
                    Text(selectedCountry.flag)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .frame(minWidth: 64, minHeight: 36)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(Text("phone.countryCode"))

            TextField("section.phones", text: $value.value)
                .keyboardType(.phonePad)
                .autocorrectionDisabled()
                .focusWhenRequested(fieldID: value.id, request: valueFocusRequest)
                .onChange(of: value.value) { _, newValue in
                    guard !isFormattingPhone else { return }
                    let formatted = PhoneNumberTextFormatter.format(
                        newValue,
                        selectedCountry: selectedCountry
                    )
                    guard formatted != newValue else { return }
                    isFormattingPhone = true
                    value.value = formatted
                    isFormattingPhone = false
                }
        }
        .sheet(isPresented: $isPickingCountry) {
            PhoneCountryPickerView(selectedCountry: selectedCountry) { country in
                selectedCountryOverride = country
                value.value = country.applied(to: value.value)
                isPickingCountry = false
            }
        }
        .onChange(of: value.value) { _, newValue in
            guard let selectedCountryOverride else { return }
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("+") && !trimmed.hasPrefix(selectedCountryOverride.dialCode) {
                self.selectedCountryOverride = nil
            }
        }
    }

    private var labelBinding: Binding<String> {
        Binding {
            value.label.googleContactsDisplayLabel
        } set: { newValue in
            value.label = newValue.googleContactsDisplayLabel
        }
    }
}

private struct EditableEmailRow: View {
    @Binding var value: LabeledValue
    let valueFocusRequest: String?
    let onDelete: () -> Void

    var body: some View {
        EditableLabeledInputRow(
            value: $value,
            valueTitle: "section.emails",
            presetLabels: [
                LabelOption(title: "label.home", value: "Home"),
                LabelOption(title: "label.work", value: "Work"),
                LabelOption(title: "label.other", value: "Other")
            ],
            keyboardType: .emailAddress,
            textCapitalization: .never,
            removeLabel: "email.remove",
            valueFocusRequest: valueFocusRequest,
            onDelete: onDelete
        )
    }
}

private struct EditableLabeledInputRow: View {
    @Binding var value: LabeledValue
    let valueTitle: LocalizedStringKey
    let presetLabels: [LabelOption]
    let keyboardType: UIKeyboardType
    var textCapitalization: TextInputAutocapitalization? = nil
    let removeLabel: LocalizedStringKey
    var valueFocusRequest: String? = nil
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("field.label", text: labelBinding)
                .textInputAutocapitalization(.words)

            Menu {
                ForEach(presetLabels) { label in
                    Button(label.title) {
                        value.label = label.value
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Text("🅧")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(removeLabel))
        }

        TextField(valueTitle, text: $value.value)
            .textInputAutocapitalization(textCapitalization)
            .keyboardType(keyboardType)
            .autocorrectionDisabled()
            .focusWhenRequested(fieldID: value.id, request: valueFocusRequest)
    }

    private var labelBinding: Binding<String> {
        Binding {
            value.label.googleContactsDisplayLabel
        } set: { newValue in
            value.label = newValue.googleContactsDisplayLabel
        }
    }

}

private struct FocusWhenRequestedModifier: ViewModifier {
    let fieldID: String
    let request: String?
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .onAppear {
                focusIfRequested(request)
            }
            .onChange(of: request) { _, newRequest in
                focusIfRequested(newRequest)
            }
    }

    private func focusIfRequested(_ request: String?) {
        guard request == fieldID else { return }
        isFocused = true
    }
}

private extension View {
    func focusWhenRequested(fieldID: String, request: String?) -> some View {
        modifier(FocusWhenRequestedModifier(fieldID: fieldID, request: request))
    }
}

private struct LabelOption: Identifiable {
    let title: LocalizedStringKey
    let value: String

    var id: String { value }
}

private extension String {
    var googleContactsDisplayLabel: String {
        switch lowercased() {
        case "home": "Home"
        case "work": "Work"
        case "other": "Other"
        case "profile": "Profile"
        case "blog": "Blog"
        case "homepage", "home_page", "home page": "Home Page"
        case "spouse": "Spouse"
        case "child": "Child"
        case "mother": "Mother"
        case "father": "Father"
        case "parent": "Parent"
        case "brother": "Brother"
        case "sister": "Sister"
        case "friend": "Friend"
        case "relative": "Relative"
        case "manager": "Manager"
        case "assistant": "Assistant"
        case "reference": "Reference"
        case "partner": "Partner"
        case "domesticpartner", "domestic_partner", "domestic partner": "Domestic Partner"
        case "anniversary": "Anniversary"
        case "mobile": "Mobile"
        case "main": "Main"
        case "homefax", "home_fax", "home fax": "Home Fax"
        case "workfax", "work_fax", "work fax": "Work Fax"
        case "googlevoice", "google_voice", "google voice": "Google Voice"
        case "pager": "Pager"
        default: self
        }
    }
}

private struct PhoneCountryPickerView: View {
    let selectedCountry: PhoneCountry
    let onSelect: (PhoneCountry) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredCountries: [PhoneCountry] {
        guard !searchText.isEmpty else { return PhoneCountry.all }
        return PhoneCountry.all.filter { country in
            country.name.localizedStandardContains(searchText)
                || country.dialCode.localizedStandardContains(searchText)
                || country.regionCode.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredCountries) { country in
                Button {
                    onSelect(country)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text(country.flag)
                        Text("\(country.name) (\(country.dialCode))")
                        Spacer()
                        if country == selectedCountry {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("phone.countryCode")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "phone.countrySearch")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct PhoneCountry: Identifiable, Hashable {
    let regionCode: String
    let dialCode: String

    var id: String { regionCode }

    var name: String {
        Locale.autoupdatingCurrent.localizedString(forRegionCode: regionCode)
            ?? Locale(identifier: "en").localizedString(forRegionCode: regionCode)
            ?? regionCode
    }

    var flag: String {
        regionCode
            .unicodeScalars
            .compactMap { UnicodeScalar(127397 + $0.value) }
            .map(String.init)
            .joined()
    }

    static let taiwan = PhoneCountry(regionCode: "TW", dialCode: "+886")

    static func matching(phoneNumber: String) -> PhoneCountry? {
        let trimmed = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return all
            .sorted { lhs, rhs in
                if lhs.dialCode.count != rhs.dialCode.count {
                    return lhs.dialCode.count > rhs.dialCode.count
                }
                let lhsPriority = primaryRegionPriority[lhs.dialCode] == lhs.regionCode ? 0 : 1
                let rhsPriority = primaryRegionPriority[rhs.dialCode] == rhs.regionCode ? 0 : 1
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .first { trimmed.hasPrefix($0.dialCode) }
    }

    func applied(to phoneNumber: String) -> String {
        var remainder = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existingCountry = Self.matching(phoneNumber: remainder) {
            remainder.removeFirst(existingCountry.dialCode.count)
            remainder = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return remainder.isEmpty ? "\(dialCode) " : "\(dialCode) \(remainder)"
    }

    static let all: [PhoneCountry] = {
        dialCodesByRegion
            .map { PhoneCountry(regionCode: $0.key, dialCode: $0.value) }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }()

    private static let primaryRegionPriority: [String: String] = [
        "+1": "US",
        "+7": "RU",
        "+39": "IT",
        "+44": "GB",
        "+47": "NO",
        "+61": "AU",
        "+262": "RE",
        "+358": "FI",
        "+500": "FK",
        "+590": "GP",
        "+599": "CW",
        "+672": "AQ"
    ]

    private static let dialCodesByRegion: [String: String] = [
        "AD": "+376",
        "AE": "+971",
        "AF": "+93",
        "AG": "+1",
        "AI": "+1",
        "AL": "+355",
        "AM": "+374",
        "AO": "+244",
        "AQ": "+672",
        "AR": "+54",
        "AS": "+1",
        "AT": "+43",
        "AU": "+61",
        "AW": "+297",
        "AX": "+358",
        "AZ": "+994",
        "BA": "+387",
        "BB": "+1",
        "BD": "+880",
        "BE": "+32",
        "BF": "+226",
        "BG": "+359",
        "BH": "+973",
        "BI": "+257",
        "BJ": "+229",
        "BL": "+590",
        "BM": "+1",
        "BN": "+673",
        "BO": "+591",
        "BQ": "+599",
        "BR": "+55",
        "BS": "+1",
        "BT": "+975",
        "BV": "+47",
        "BW": "+267",
        "BY": "+375",
        "BZ": "+501",
        "CA": "+1",
        "CC": "+61",
        "CD": "+243",
        "CF": "+236",
        "CG": "+242",
        "CH": "+41",
        "CI": "+225",
        "CK": "+682",
        "CL": "+56",
        "CM": "+237",
        "CN": "+86",
        "CO": "+57",
        "CR": "+506",
        "CU": "+53",
        "CV": "+238",
        "CW": "+599",
        "CX": "+61",
        "CY": "+357",
        "CZ": "+420",
        "DE": "+49",
        "DJ": "+253",
        "DK": "+45",
        "DM": "+1",
        "DO": "+1",
        "DZ": "+213",
        "EC": "+593",
        "EE": "+372",
        "EG": "+20",
        "EH": "+212",
        "ER": "+291",
        "ES": "+34",
        "ET": "+251",
        "FI": "+358",
        "FJ": "+679",
        "FK": "+500",
        "FM": "+691",
        "FO": "+298",
        "FR": "+33",
        "GA": "+241",
        "GB": "+44",
        "GD": "+1",
        "GE": "+995",
        "GF": "+594",
        "GG": "+44",
        "GH": "+233",
        "GI": "+350",
        "GL": "+299",
        "GM": "+220",
        "GN": "+224",
        "GP": "+590",
        "GQ": "+240",
        "GR": "+30",
        "GS": "+500",
        "GT": "+502",
        "GU": "+1",
        "GW": "+245",
        "GY": "+592",
        "HM": "+672",
        "HK": "+852",
        "HN": "+504",
        "HR": "+385",
        "HT": "+509",
        "HU": "+36",
        "ID": "+62",
        "IE": "+353",
        "IL": "+972",
        "IM": "+44",
        "IN": "+91",
        "IO": "+246",
        "IQ": "+964",
        "IR": "+98",
        "IS": "+354",
        "IT": "+39",
        "JE": "+44",
        "JM": "+1",
        "JO": "+962",
        "JP": "+81",
        "KE": "+254",
        "KG": "+996",
        "KH": "+855",
        "KI": "+686",
        "KM": "+269",
        "KN": "+1",
        "KP": "+850",
        "KR": "+82",
        "KW": "+965",
        "KY": "+1",
        "KZ": "+7",
        "LA": "+856",
        "LB": "+961",
        "LC": "+1",
        "LI": "+423",
        "LK": "+94",
        "LR": "+231",
        "LS": "+266",
        "LT": "+370",
        "LU": "+352",
        "LV": "+371",
        "LY": "+218",
        "MA": "+212",
        "MC": "+377",
        "MD": "+373",
        "ME": "+382",
        "MF": "+590",
        "MG": "+261",
        "MH": "+692",
        "MK": "+389",
        "ML": "+223",
        "MM": "+95",
        "MN": "+976",
        "MO": "+853",
        "MP": "+1",
        "MQ": "+596",
        "MR": "+222",
        "MS": "+1",
        "MT": "+356",
        "MU": "+230",
        "MV": "+960",
        "MW": "+265",
        "MX": "+52",
        "MY": "+60",
        "MZ": "+258",
        "NA": "+264",
        "NC": "+687",
        "NE": "+227",
        "NF": "+672",
        "NG": "+234",
        "NI": "+505",
        "NL": "+31",
        "NO": "+47",
        "NP": "+977",
        "NR": "+674",
        "NU": "+683",
        "NZ": "+64",
        "OM": "+968",
        "PA": "+507",
        "PE": "+51",
        "PF": "+689",
        "PG": "+675",
        "PH": "+63",
        "PK": "+92",
        "PL": "+48",
        "PM": "+508",
        "PN": "+64",
        "PR": "+1",
        "PS": "+970",
        "PT": "+351",
        "PW": "+680",
        "PY": "+595",
        "QA": "+974",
        "RE": "+262",
        "RO": "+40",
        "RS": "+381",
        "RU": "+7",
        "RW": "+250",
        "SA": "+966",
        "SB": "+677",
        "SC": "+248",
        "SD": "+249",
        "SE": "+46",
        "SG": "+65",
        "SH": "+290",
        "SI": "+386",
        "SJ": "+47",
        "SK": "+421",
        "SL": "+232",
        "SM": "+378",
        "SN": "+221",
        "SO": "+252",
        "SR": "+597",
        "SS": "+211",
        "ST": "+239",
        "SV": "+503",
        "SX": "+1",
        "SY": "+963",
        "SZ": "+268",
        "TC": "+1",
        "TD": "+235",
        "TF": "+262",
        "TG": "+228",
        "TH": "+66",
        "TJ": "+992",
        "TK": "+690",
        "TL": "+670",
        "TM": "+993",
        "TN": "+216",
        "TO": "+676",
        "TR": "+90",
        "TT": "+1",
        "TV": "+688",
        "TW": "+886",
        "TZ": "+255",
        "UA": "+380",
        "UG": "+256",
        "UM": "+1",
        "US": "+1",
        "UY": "+598",
        "UZ": "+998",
        "VA": "+39",
        "VC": "+1",
        "VE": "+58",
        "VG": "+1",
        "VI": "+1",
        "VN": "+84",
        "VU": "+678",
        "WF": "+681",
        "WS": "+685",
        "YE": "+967",
        "YT": "+262",
        "ZA": "+27",
        "ZM": "+260",
        "ZW": "+263"
    ]
}

private enum PhoneNumberTextFormatter {
    private static let phoneNumberKit = PhoneNumberUtility()

    static func format(_ text: String, selectedCountry: PhoneCountry) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let formatter = PartialFormatter(
            utility: phoneNumberKit,
            defaultRegion: selectedCountry.regionCode,
            withPrefix: true,
            ignoreIntlNumbers: false
        )
        let formatted = formatter.formatPartial(trimmed)
        return displayLocalTrunkPrefixIfNeeded(
            formatted,
            original: trimmed
        )
    }

    private static func displayLocalTrunkPrefixIfNeeded(
        _ formatted: String,
        original: String
    ) -> String {
        guard !original.hasPrefix("+") else { return formatted }

        let originalDigits = original.filter(\.isNumber)
        let formattedDigits = formatted.filter(\.isNumber)
        guard originalDigits.hasPrefix("0"), !formattedDigits.hasPrefix("0") else {
            return formatted
        }

        return "0" + formatted
    }
}

private struct EditableAddressesSection: View {
    @Binding var addresses: [PostalAddress]
    @State private var streetFocusRequest: String?

    var body: some View {
        Section("section.addresses") {
            ForEach($addresses) { $address in
                EditableAddressRow(
                    address: $address,
                    streetFocusRequest: streetFocusRequest
                ) {
                    addresses.removeAll { $0.id == address.id }
                }
            }
            .onDelete { addresses.remove(atOffsets: $0) }

            Button("action.addAddress") {
                let newAddress = PostalAddress()
                addresses.append(newAddress)
                streetFocusRequest = newAddress.id
            }
        }
    }
}

private struct EditableAddressRow: View {
    @Binding var address: PostalAddress
    let streetFocusRequest: String?
    let onDelete: () -> Void
    @State private var isPickingCountry = false

    private let labelOptions = [
        LabelOption(title: "label.home", value: "Home"),
        LabelOption(title: "label.work", value: "Work"),
        LabelOption(title: "label.other", value: "Other")
    ]

    private var selectedCountry: AddressCountry? {
        AddressCountry.matching(code: address.countryCode, name: address.country)
    }

    private var counties: [String] {
        selectedCountry.map { AddressSubdivisionCatalog.counties(for: $0) } ?? []
    }

    private var districts: [String] {
        guard let selectedCountry, !address.region.isEmpty else { return [] }
        return AddressSubdivisionCatalog.districts(for: selectedCountry, county: address.region)
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("field.label", text: labelBinding)
                .textInputAutocapitalization(.words)

            Menu {
                ForEach(labelOptions) { label in
                    Button(label.title) {
                        address.label = label.value
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Text("🅧")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("address.remove"))
        }

        Button {
            isPickingCountry = true
        } label: {
            FieldMenuValue(title: "address.country", value: address.country)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPickingCountry) {
            AddressCountryPickerView(selectedCountry: selectedCountry) { country in
                address.country = country.name
                address.countryCode = country.regionCode
                address.region = ""
                address.city = ""
                isPickingCountry = false
            }
        }

        TextField("address.street", text: $address.streetAddress)
            .textInputAutocapitalization(.words)
            .focusWhenRequested(fieldID: address.id, request: streetFocusRequest)
        TextField("address.extended", text: $address.extendedAddress)
            .textInputAutocapitalization(.words)

        Menu {
            ForEach(districts, id: \.self) { district in
                Button(district) {
                    address.city = district
                }
            }
        } label: {
            FieldMenuValue(title: "address.district", value: address.city)
        }
        .buttonStyle(.plain)
        .disabled(address.region.isEmpty || districts.isEmpty)

        Menu {
            ForEach(counties, id: \.self) { county in
                Button(county) {
                    address.region = county
                    address.city = ""
                }
            }
        } label: {
            FieldMenuValue(title: "address.county", value: address.region)
        }
        .buttonStyle(.plain)
        .disabled(selectedCountry == nil || counties.isEmpty)

        TextField("address.postalCode", text: $address.postalCode)
            .keyboardType(.numbersAndPunctuation)
        TextField("address.poBox", text: $address.poBox)
            .textInputAutocapitalization(.words)
    }

    private var labelBinding: Binding<String> {
        Binding {
            address.label.googleContactsDisplayLabel
        } set: { newValue in
            address.label = newValue.googleContactsDisplayLabel
        }
    }
}

private struct FieldMenuValue: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value.isEmpty ? String(localized: "field.empty") : value)
                    .foregroundStyle(value.isEmpty ? .secondary : .primary)
            }
            Spacer()
            Image(systemName: "chevron.down")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct AddressCountryPickerView: View {
    let selectedCountry: AddressCountry?
    let onSelect: (AddressCountry) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredCountries: [AddressCountry] {
        guard !searchText.isEmpty else { return AddressCountry.all }
        return AddressCountry.all.filter { country in
            country.name.localizedStandardContains(searchText)
                || country.regionCode.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredCountries) { country in
                Button {
                    onSelect(country)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text(country.flag)
                        Text(country.name)
                        Spacer()
                        if country == selectedCountry {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("address.country")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "address.country")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct AddressCountry: Identifiable, Hashable {
    let regionCode: String

    var id: String { regionCode }

    var name: String {
        Locale.autoupdatingCurrent.localizedString(forRegionCode: regionCode)
            ?? Locale(identifier: "en").localizedString(forRegionCode: regionCode)
            ?? regionCode
    }

    var flag: String {
        regionCode
            .unicodeScalars
            .compactMap { UnicodeScalar(127397 + $0.value) }
            .map(String.init)
            .joined()
    }

    static func matching(code: String, name: String) -> AddressCountry? {
        if let byCode = all.first(where: { $0.regionCode == code }) {
            return byCode
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        return all.first {
            $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
                || $0.regionCode.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
        }
    }

    static let all: [AddressCountry] = Locale.Region.isoRegions
        .compactMap { region -> AddressCountry? in
            let code = region.identifier
            guard code.count == 2 else { return nil }
            return AddressCountry(regionCode: code)
        }
        .sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
}

private enum AddressSubdivisionCatalog {
    static func counties(for country: AddressCountry) -> [String] {
        guard country.regionCode == "TW" else { return [] }
        return taiwanDistricts.map(\.county)
    }

    static func districts(for country: AddressCountry, county: String) -> [String] {
        guard country.regionCode == "TW" else { return [] }
        return taiwanDistricts.first { $0.county == county }?.districts ?? []
    }

    private static let taiwanDistricts: [(county: String, districts: [String])] = [
        ("Taipei City", ["Zhongzheng District", "Datong District", "Zhongshan District", "Songshan District", "Da'an District", "Wanhua District", "Xinyi District", "Shilin District", "Beitou District", "Neihu District", "Nangang District", "Wenshan District"]),
        ("New Taipei City", ["Banqiao District", "Sanchong District", "Zhonghe District", "Yonghe District", "Xinzhuang District", "Xindian District", "Tucheng District", "Luzhou District", "Shulin District", "Yingge District", "Sanxia District", "Tamsui District", "Xizhi District", "Ruifang District", "Wugu District", "Taishan District", "Linkou District", "Shenkeng District", "Shiding District", "Pinglin District", "Sanzhi District", "Shimen District", "Bali District", "Pingxi District", "Shuangxi District", "Gongliao District", "Jinshan District", "Wanli District", "Wulai District"]),
        ("Taoyuan City", ["Taoyuan District", "Zhongli District", "Daxi District", "Yangmei District", "Luzhu District", "Dayuan District", "Guishan District", "Bade District", "Longtan District", "Pingzhen District", "Xinwu District", "Guanyin District", "Fuxing District"]),
        ("Taichung City", ["Central District", "East District", "South District", "West District", "North District", "Beitun District", "Xitun District", "Nantun District", "Taiping District", "Dali District", "Wufeng District", "Wuri District", "Fengyuan District", "Houli District", "Shigang District", "Dongshi District", "Heping District", "Xinshe District", "Tanzi District", "Daya District", "Shengang District", "Dadu District", "Shalu District", "Longjing District", "Wuqi District", "Qingshui District", "Dajia District", "Waipu District", "Da'an District"]),
        ("Tainan City", ["West Central District", "East District", "South District", "North District", "Anping District", "Annan District", "Yongkang District", "Guiren District", "Xinhua District", "Zuozhen District", "Yujing District", "Nanxi District", "Nanhua District", "Rende District", "Guanmiao District", "Longqi District", "Guantian District", "Madou District", "Jiali District", "Xigang District", "Qigu District", "Jiangjun District", "Xuejia District", "Beimen District", "Xinying District", "Houbi District", "Baihe District", "Dongshan District", "Liujia District", "Xiaying District", "Liuying District", "Yanshui District", "Shanhua District", "Danei District", "Shanshang District", "Xinshi District", "Anding District"]),
        ("Kaohsiung City", ["Xinxing District", "Qianjin District", "Lingya District", "Yancheng District", "Gushan District", "Qijin District", "Qianzhen District", "Sanmin District", "Nanzih District", "Xiaogang District", "Zuoying District", "Renwu District", "Dashe District", "Gangshan District", "Luzhu District", "Alian District", "Tianliao District", "Yanchao District", "Qiaotou District", "Ziguan District", "Mituo District", "Yongan District", "Hunei District", "Fengshan District", "Daliao District", "Linyuan District", "Niaosong District", "Dashu District", "Qishan District", "Meinong District", "Liugui District", "Neimen District", "Shanlin District", "Jiaxian District", "Taoyuan District", "Namaxia District", "Maolin District", "Qieding District"]),
        ("Keelung City", ["Ren'ai District", "Xinyi District", "Zhongzheng District", "Zhongshan District", "Anle District", "Nuannuan District", "Qidu District"]),
        ("Hsinchu City", ["East District", "North District", "Xiangshan District"]),
        ("Chiayi City", ["East District", "West District"]),
        ("Hsinchu County", ["Zhubei City", "Zhudong Township", "Xinpu Township", "Guanxi Township", "Hukou Township", "Xinfeng Township", "Emei Township", "Baoshan Township", "Beipu Township", "Qionglin Township", "Hengshan Township", "Jianshi Township", "Wufeng Township"]),
        ("Miaoli County", ["Miaoli City", "Toufen City", "Yuanli Township", "Tongxiao Township", "Zhunan Township", "Houlong Township", "Zhuolan Township", "Dahu Township", "Gongguan Township", "Tongluo Township", "Nanzhuang Township", "Touwu Township", "Sanyi Township", "Xihu Township", "Zaoqiao Township", "Sanwan Township", "Shitan Township", "Tai'an Township"]),
        ("Changhua County", ["Changhua City", "Lukang Township", "Hemei Township", "Xianxi Township", "Shengang Township", "Fuxing Township", "Xiushui Township", "Huatan Township", "Fenyuan Township", "Yuanlin City", "Xihu Township", "Tianzhong Township", "Dacun Township", "Puxin Township", "Yongjing Township", "Shetou Township", "Ershui Township", "Beidou Township", "Erlin Township", "Tianwei Township", "Pitou Township", "Fangyuan Township", "Dacheng Township", "Zhutang Township", "Xizhou Township"]),
        ("Nantou County", ["Nantou City", "Puli Township", "Caotun Township", "Zhushan Township", "Jiji Township", "Mingjian Township", "Lugu Township", "Zhongliao Township", "Yuchi Township", "Guoxing Township", "Shuili Township", "Xinyi Township", "Ren'ai Township"]),
        ("Yunlin County", ["Douliu City", "Dounan Township", "Huwei Township", "Xiluo Township", "Tuku Township", "Beigang Township", "Gukeng Township", "Dapi Township", "Citong Township", "Linnei Township", "Erlun Township", "Lunbei Township", "Mailiao Township", "Dongshi Township", "Baozhong Township", "Taixi Township", "Yuanchang Township", "Sihu Township", "Kouhu Township", "Shuilin Township"]),
        ("Chiayi County", ["Taibao City", "Puzi City", "Budai Township", "Dalin Township", "Minxiong Township", "Xikou Township", "Xingang Township", "Liujiao Township", "Dongshi Township", "Yizhu Township", "Lucao Township", "Shuishang Township", "Zhongpu Township", "Zhuqi Township", "Meishan Township", "Fanlu Township", "Dapu Township", "Alishan Township"]),
        ("Pingtung County", ["Pingtung City", "Chaozhou Township", "Donggang Township", "Hengchun Township", "Wandan Township", "Changzhi Township", "Linluo Township", "Jiuru Township", "Ligang Township", "Yanpu Township", "Gaoshu Township", "Wanluan Township", "Neipu Township", "Zhutian Township", "Xinpi Township", "Fangliao Township", "Xinyuan Township", "Kanding Township", "Nanzhou Township", "Linbian Township", "Jiadong Township", "Liuqiu Township", "Checheng Township", "Manzhou Township", "Fangshan Township", "Sandimen Township", "Wutai Township", "Majia Township", "Taiwu Township", "Laiyi Township", "Chunri Township", "Shizi Township", "Mudan Township"]),
        ("Yilan County", ["Yilan City", "Luodong Township", "Su'ao Township", "Toucheng Township", "Jiaoxi Township", "Zhuangwei Township", "Yuanshan Township", "Dongshan Township", "Wujie Township", "Sanxing Township", "Datong Township", "Nan'ao Township"]),
        ("Hualien County", ["Hualien City", "Fenglin Township", "Yuli Township", "Xincheng Township", "Ji'an Township", "Shoufeng Township", "Guangfu Township", "Fengbin Township", "Ruisui Township", "Fuli Township", "Xiulin Township", "Wanrong Township", "Zhuoxi Township"]),
        ("Taitung County", ["Taitung City", "Chenggong Township", "Guanshan Township", "Beinan Township", "Luye Township", "Chishang Township", "Donghe Township", "Changbin Township", "Taimali Township", "Dawu Township", "Lüdao Township", "Haiduan Township", "Yanping Township", "Jinfeng Township", "Daren Township", "Lanyu Township"]),
        ("Penghu County", ["Magong City", "Huxi Township", "Baisha Township", "Xiyu Township", "Wang'an Township", "Qimei Township"]),
        ("Kinmen County", ["Jincheng Township", "Jinhu Township", "Jinsha Township", "Jinning Township", "Lieyu Township", "Wuqiu Township"]),
        ("Lienchiang County", ["Nangan Township", "Beigan Township", "Juguang Township", "Dongyin Township"])
    ]
}

private struct EditableOrganizationsSection: View {
    @Binding var organizations: [Organization]

    var body: some View {
        Section("section.organizations") {
            EditableOrganizationFields(organization: organizationBinding)
        }
    }

    private var organizationBinding: Binding<Organization> {
        Binding {
            organizations.first ?? Organization()
        } set: { organization in
            organizations = [organization]
        }
    }
}

private struct EditableOrganizationFields: View {
    @Binding var organization: Organization

    var body: some View {
        TextField("organization.name", text: $organization.name)
        TextField("organization.department", text: $organization.department)
        TextField("organization.title", text: $organization.title)
    }
}

private struct EditableDatesSection: View {
    let title: LocalizedStringKey
    @Binding var dates: [ContactDate]
    @State private var yearFocusRequest: String?

    var body: some View {
        Section(title) {
            ForEach($dates) { $date in
                EditableContactDateFields(
                    date: $date,
                    yearFocusRequest: yearFocusRequest
                )
            }
            .onDelete { dates.remove(atOffsets: $0) }

            Button("action.addDate") {
                let newDate = ContactDate()
                dates.append(newDate)
                yearFocusRequest = newDate.id
            }
        }
    }
}

private struct EditableContactDateFields: View {
    @Binding var date: ContactDate
    var yearFocusRequest: String? = nil

    private var selectedMonthValue: String {
        guard let month = Int(date.month), (1...12).contains(month) else {
            return ""
        }
        return DateInputFormatter.monthTitle(month)
    }

    private var dayOptions: [String] {
        (1...DateInputFormatter.maxDay(month: date.month, year: date.year)).map {
            String(format: "%02d", $0)
        }
    }

    var body: some View {
        TextField("date.year", text: yearBinding)
            .keyboardType(.numberPad)
            .focusWhenRequested(fieldID: date.id, request: yearFocusRequest)

        Picker("date.month", selection: monthBinding) {
            Text("field.empty").tag("")
            ForEach(1...12, id: \.self) { month in
                Text(monthTitle(month)).tag(String(month))
            }
        }
        .pickerStyle(.menu)

        Picker("date.day", selection: dayBinding) {
            Text("field.empty").tag("")
            ForEach(dayOptions, id: \.self) { day in
                Text(day).tag(day)
            }
        }
        .pickerStyle(.menu)
    }

    private var yearBinding: Binding<String> {
        Binding {
            date.year
        } set: { newValue in
            date.year = DateInputFormatter.year(newValue)
            date.day = DateInputFormatter.validatedDay(
                date.day,
                month: date.month,
                year: date.year,
                padsSingleDigit: true
            )
        }
    }

    private var monthBinding: Binding<String> {
        Binding {
            date.month
        } set: { newValue in
            date.month = newValue
            date.day = DateInputFormatter.validatedDay(
                date.day,
                month: date.month,
                year: date.year,
                padsSingleDigit: true
            )
        }
    }

    private var dayBinding: Binding<String> {
        Binding {
            date.day
        } set: { newValue in
            date.day = newValue
        }
    }

    private func monthTitle(_ month: Int) -> String {
        DateInputFormatter.monthTitle(month)
    }
}

private enum DateInputFormatter {
    static func year(_ text: String) -> String {
        String(text.filter(\.isNumber).prefix(4))
    }

    static func validatedDay(
        _ text: String,
        month: String,
        year: String,
        padsSingleDigit: Bool
    ) -> String {
        let digits = String(text.filter(\.isNumber).prefix(2))
        guard !digits.isEmpty else { return "" }

        guard var day = Int(digits) else { return "" }
        let maxDay = maxDay(month: month, year: year)
        day = min(max(day, 1), maxDay)

        if digits.count == 1 {
            if padsSingleDigit && day >= 4 {
                return String(format: "%02d", day)
            }
            return String(day)
        }

        return String(format: "%02d", day)
    }

    static func monthTitle(_ month: Int) -> String {
        let symbols = Calendar.current.monthSymbols
        guard symbols.indices.contains(month - 1) else { return String(month) }
        return symbols[month - 1]
    }

    static func maxDay(month: String, year: String) -> Int {
        guard let monthValue = Int(month), (1...12).contains(monthValue) else {
            return 31
        }

        switch monthValue {
        case 4, 6, 9, 11:
            return 30
        case 2:
            guard let yearValue = Int(year), year.count == 4 else {
                return 29
            }
            return isLeapYear(yearValue) ? 29 : 28
        default:
            return 31
        }
    }

    private static func isLeapYear(_ year: Int) -> Bool {
        (year.isMultiple(of: 4) && !year.isMultiple(of: 100)) || year.isMultiple(of: 400)
    }
}

private struct EditableEventsSection: View {
    @Binding var events: [ContactEvent]
    @State private var labelFocusRequest: String?

    var body: some View {
        Section("section.events") {
            ForEach($events) { $event in
                EditableEventRow(
                    event: $event,
                    labelFocusRequest: labelFocusRequest
                ) {
                    events.removeAll { $0.id == event.id }
                }
            }
            .onDelete { events.remove(atOffsets: $0) }

            Button("action.addEvent") {
                let newEvent = ContactEvent()
                events.append(newEvent)
                labelFocusRequest = newEvent.id
            }
        }
    }
}

private struct EditableEventRow: View {
    @Binding var event: ContactEvent
    let labelFocusRequest: String?
    let onDelete: () -> Void

    private let labelOptions = [
        LabelOption(title: "label.anniversary", value: "Anniversary"),
        LabelOption(title: "label.other", value: "Other")
    ]

    var body: some View {
        HStack(spacing: 8) {
            TextField("field.label", text: labelBinding)
                .textInputAutocapitalization(.words)
                .focusWhenRequested(fieldID: event.id, request: labelFocusRequest)

            Menu {
                ForEach(labelOptions) { label in
                    Button(label.title) {
                        event.label = label.value
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Text("🅧")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("event.remove"))
        }

        EditableContactDateFields(date: $event.date)
    }

    private var labelBinding: Binding<String> {
        Binding {
            event.label.googleContactsDisplayLabel
        } set: { newValue in
            event.label = newValue.googleContactsDisplayLabel
        }
    }
}

private struct EditableRelationsSection: View {
    @Binding var relations: [Relation]
    @State private var personFocusRequest: String?

    var body: some View {
        Section("section.relations") {
            ForEach($relations) { $relation in
                EditableRelationRow(
                    relation: $relation,
                    personFocusRequest: personFocusRequest
                ) {
                    relations.removeAll { $0.id == relation.id }
                }
            }
            .onDelete { relations.remove(atOffsets: $0) }

            Button("action.addRelation") {
                let newRelation = Relation()
                relations.append(newRelation)
                personFocusRequest = newRelation.id
            }
        }
    }
}

private struct EditableRelationRow: View {
    @Binding var relation: Relation
    let personFocusRequest: String?
    let onDelete: () -> Void

    private let labelOptions = [
        LabelOption(title: "label.spouse", value: "Spouse"),
        LabelOption(title: "label.child", value: "Child"),
        LabelOption(title: "label.mother", value: "Mother"),
        LabelOption(title: "label.father", value: "Father"),
        LabelOption(title: "label.parent", value: "Parent"),
        LabelOption(title: "label.brother", value: "Brother"),
        LabelOption(title: "label.sister", value: "Sister"),
        LabelOption(title: "label.friend", value: "Friend"),
        LabelOption(title: "label.relative", value: "Relative"),
        LabelOption(title: "label.manager", value: "Manager"),
        LabelOption(title: "label.assistant", value: "Assistant"),
        LabelOption(title: "label.reference", value: "Reference"),
        LabelOption(title: "label.partner", value: "Partner"),
        LabelOption(title: "label.domesticPartner", value: "Domestic Partner")
    ]

    var body: some View {
        HStack(spacing: 8) {
            TextField("field.label", text: labelBinding)
                .textInputAutocapitalization(.words)

            Menu {
                ForEach(labelOptions) { label in
                    Button(label.title) {
                        relation.label = label.value
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Text("🅧")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("relation.remove"))
        }

        TextField("relation.person", text: $relation.person)
            .textInputAutocapitalization(.words)
            .focusWhenRequested(fieldID: relation.id, request: personFocusRequest)
    }

    private var labelBinding: Binding<String> {
        Binding {
            relation.label.googleContactsDisplayLabel
        } set: { newValue in
            relation.label = newValue.googleContactsDisplayLabel
        }
    }
}

private struct EditableBiographiesSection: View {
    @Binding var biographies: [String]

    var body: some View {
        Section("section.biographies") {
            TextEditor(text: biographyBinding)
                .frame(minHeight: 80)
        }
    }

    private var biographyBinding: Binding<String> {
        Binding {
            biographies.first ?? ""
        } set: { value in
            biographies = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [value]
        }
    }
}

private struct EditableUserDefinedSection: View {
    @Binding var fields: [UserDefinedField]
    @State private var keyFocusRequest: String?

    var body: some View {
        Section("section.userDefined") {
            ForEach($fields) { $field in
                EditableUserDefinedRow(
                    field: $field,
                    keyFocusRequest: keyFocusRequest
                ) {
                    fields.removeAll { $0.id == field.id }
                }
            }
            .onDelete { fields.remove(atOffsets: $0) }

            Button("action.addUserDefined") {
                let newField = UserDefinedField()
                fields.append(newField)
                keyFocusRequest = newField.id
            }
        }
    }
}

private struct EditableUserDefinedRow: View {
    @Binding var field: UserDefinedField
    let keyFocusRequest: String?
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("field.label", text: $field.key)
                .textInputAutocapitalization(.words)
                .focusWhenRequested(fieldID: field.id, request: keyFocusRequest)

            Button(action: onDelete) {
                Text("🅧")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("customField.remove"))
        }

        TextField("field.value", text: $field.value)
    }
}

private extension UIImage {
    func scaledJPEGData(maxPixelLength: CGFloat, compressionQuality: CGFloat) -> Data? {
        let largestSide = max(size.width, size.height)
        let scale = largestSide > maxPixelLength ? maxPixelLength / largestSide : 1
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)

        let image = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return image.jpegData(compressionQuality: compressionQuality)
    }
}

private extension Contact {
    func normalizedForEditing() -> Contact {
        var normalized = self
        normalized.names = [names.first ?? ContactName()]
        normalized.organizations = [organizations.first ?? Organization()]
        normalized.nicknames = nicknames.first.map { [$0] } ?? []
        normalized.emailAddresses = emailAddresses.filter {
            !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        normalized.phoneNumbers = phoneNumbers.filter {
            !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        normalized.birthdays = birthdays.filter(\.hasAnyValue)
        normalized.events = events.filter {
            !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || $0.date.hasAnyValue
        }
        normalized.addresses = addresses.filter {
            !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !$0.streetAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !$0.extendedAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !$0.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !$0.region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !$0.postalCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !$0.poBox.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !$0.country.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !$0.countryCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        normalized.userDefined = userDefined.filter(\.hasAnyValue)
        return normalized
    }
}

private extension ContactDate {
    var hasAnyValue: Bool {
        !year.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !month.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !day.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasRequiredMonthAndDay: Bool {
        !month.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !day.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private extension UserDefinedField {
    var hasAnyValue: Bool {
        !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var requiresLabel: Bool {
        key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

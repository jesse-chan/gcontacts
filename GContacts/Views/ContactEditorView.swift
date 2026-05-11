import PhotosUI
import PhoneNumberKit
import SwiftUI
import UIKit

struct ContactEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ContactStore.self) private var store
    @State private var draft: Contact
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoImage: UIImage?
    @State private var selectedPhotoData: Data?
    @State private var removesPhoto = false
    @State private var isShowingPhotoActions = false
    @State private var isShowingPhotoPicker = false
    @State private var showsAllNameFields = false

    init(contact: Contact) {
        _draft = State(initialValue: contact.normalizedForEditing())
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
                EditableLabeledValuesSection(title: "section.urls", values: $draft.urls)
                EditableRelationsSection(relations: $draft.relations)
                EditableBiographiesSection(biographies: $draft.biographies)
                EditableUserDefinedSection(fields: $draft.userDefined)
            }
            .navigationTitle(draft.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") {
                        Task {
                            await save()
                        }
                    }
                }
            }
            .confirmationDialog("photo.edit", isPresented: $isShowingPhotoActions, titleVisibility: .visible) {
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
        draft = draft.normalizedForEditing()
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

    var body: some View {
        Section(title) {
            ForEach($values) { $value in
                TextField("field.label", text: $value.label)
                TextField("field.value", text: $value.value)
            }
            .onDelete { values.remove(atOffsets: $0) }

            Button("action.addField") {
                values.append(LabeledValue())
            }
        }
    }
}

private struct EditableEmailsSection: View {
    @Binding var values: [LabeledValue]

    var body: some View {
        Section("section.emails") {
            ForEach($values) { $value in
                EditableEmailRow(value: $value) {
                    values.removeAll { $0.id == value.id }
                }
            }

            Button("email.add") {
                values.append(LabeledValue())
            }
        }
    }
}

private struct EditablePhonesSection: View {
    @Binding var values: [LabeledValue]

    var body: some View {
        Section("section.phones") {
            ForEach($values) { $value in
                EditablePhoneRow(value: $value, presetLabels: phoneLabelOptions) {
                    values.removeAll { $0.id == value.id }
                }
            }

            Button("phone.add") {
                values.append(LabeledValue())
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
    }

    private var labelBinding: Binding<String> {
        Binding {
            value.label.googleContactsDisplayLabel
        } set: { newValue in
            value.label = newValue.googleContactsDisplayLabel
        }
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

    var body: some View {
        Section("section.addresses") {
            ForEach($addresses) { $address in
                TextField("field.label", text: $address.label)
                TextField("address.street", text: $address.streetAddress)
                TextField("address.city", text: $address.city)
                TextField("address.region", text: $address.region)
                TextField("address.postalCode", text: $address.postalCode)
                TextField("address.country", text: $address.country)
            }
            .onDelete { addresses.remove(atOffsets: $0) }

            Button("action.addAddress") {
                addresses.append(PostalAddress())
            }
        }
    }
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

    var body: some View {
        Section(title) {
            ForEach($dates) { $date in
                TextField("date.year", text: $date.year)
                    .keyboardType(.numberPad)
                TextField("date.month", text: $date.month)
                    .keyboardType(.numberPad)
                TextField("date.day", text: $date.day)
                    .keyboardType(.numberPad)
            }
            .onDelete { dates.remove(atOffsets: $0) }

            Button("action.addDate") {
                dates.append(ContactDate())
            }
        }
    }
}

private struct EditableEventsSection: View {
    @Binding var events: [ContactEvent]

    var body: some View {
        Section("section.events") {
            ForEach($events) { $event in
                TextField("field.label", text: $event.label)
                TextField("date.year", text: $event.date.year)
                    .keyboardType(.numberPad)
                TextField("date.month", text: $event.date.month)
                    .keyboardType(.numberPad)
                TextField("date.day", text: $event.date.day)
                    .keyboardType(.numberPad)
            }
            .onDelete { events.remove(atOffsets: $0) }

            Button("action.addEvent") {
                events.append(ContactEvent())
            }
        }
    }
}

private struct EditableRelationsSection: View {
    @Binding var relations: [Relation]

    var body: some View {
        Section("section.relations") {
            ForEach($relations) { $relation in
                TextField("field.label", text: $relation.label)
                TextField("relation.person", text: $relation.person)
            }
            .onDelete { relations.remove(atOffsets: $0) }

            Button("action.addRelation") {
                relations.append(Relation())
            }
        }
    }
}

private struct EditableBiographiesSection: View {
    @Binding var biographies: [String]

    var body: some View {
        Section("section.biographies") {
            ForEach(biographies.indices, id: \.self) { index in
                TextEditor(text: $biographies[index])
                    .frame(minHeight: 80)
            }
            .onDelete { biographies.remove(atOffsets: $0) }

            Button("action.addBiography") {
                biographies.append("")
            }
        }
    }
}

private struct EditableUserDefinedSection: View {
    @Binding var fields: [UserDefinedField]

    var body: some View {
        Section("section.userDefined") {
            ForEach($fields) { $field in
                TextField("field.key", text: $field.key)
                TextField("field.value", text: $field.value)
            }
            .onDelete { fields.remove(atOffsets: $0) }

            Button("action.addUserDefined") {
                fields.append(UserDefinedField())
            }
        }
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
        return normalized
    }
}

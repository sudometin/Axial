import SwiftUI

struct AnonymizerOptionsView: View {
    @Bindable var model: AnonymizerModel
    @State private var confirmNewKey = false

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Pseudonym prefix", text: $model.options.pseudonymPrefix)
                Toggle("Keep sex, age, height and weight", isOn: $model.options.keepDemographics)
            }

            Section {
                Picker("Dates", selection: $model.options.dateMode) {
                    ForEach(AnonymizationOptions.DateMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Dates")
            } footer: {
                Text(model.options.dateMode.explanation).font(.caption).foregroundStyle(.secondary)
            }

            Section("Metadata") {
                Toggle("Remove private tags", isOn: $model.options.removePrivateTags)
                Toggle("Replace UIDs", isOn: $model.options.remapUIDs)
                Toggle("Remove free-text descriptions", isOn: $model.options.removeDescriptions)
            }

            Section {
                Toggle("Find and mask burned-in text", isOn: $model.options.scanBurnedInText)
            } header: {
                Text("Pixels")
            } footer: {
                Text("Uses Apple's on-device text recognition. It can miss text, so always check the results.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Export") {
                Toggle("Also save each series as NIfTI (.nii.gz)", isOn: $model.options.exportNIfTI)
                Toggle("Write re-identification key (CSV)", isOn: $model.options.writeKeyFile)
                if model.options.writeKeyFile {
                    Label("The key links pseudonyms back to real identities. Keep it away from the shared data.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                LabeledContent("Project key") {
                    Text(String(model.options.projectKey.prefix(8)) + "…")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Button("Generate New Key…") { confirmNewKey = true }
                    .controlSize(.small)
            } header: {
                Text("Consistency")
            } footer: {
                Text("With the same key, the same patient always gets the same pseudonym and date shift, so data de-identified on different days still lines up.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Generate a new project key?", isPresented: $confirmNewKey) {
            Button("Generate New Key", role: .destructive) { model.newProjectKey() }
        } message: {
            Text("Patients will get different pseudonyms from now on, so new exports won't match earlier ones.")
        }
    }
}

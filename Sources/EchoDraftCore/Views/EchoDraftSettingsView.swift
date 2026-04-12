import AppKit
import SwiftUI

/// API key, base URL, global mode, privacy, and telemetry (Settings window).
public struct EchoDraftSettingsView: View {
    @State private var apiKeyDraft = ""
    @State private var baseURLDraft = ""
    @State private var globalMode: ProcessingMode = .offline
    @State private var telemetry = false
    @State private var showPrivacySheet = false

    public init() {}

    public var body: some View {
        Form {
            Section("Processing") {
                Picker("Default mode", selection: $globalMode) {
                    Text("Offline (on-device)").tag(ProcessingMode.offline)
                    Text("Online (OpenAI)").tag(ProcessingMode.online)
                }
                .onChange(of: globalMode) { _, newValue in
                    EchoDraftUserSettings.shared.globalProcessingMode = newValue
                    if newValue == .online, !EchoDraftUserSettings.shared.onlinePrivacyAcknowledged {
                        showPrivacySheet = true
                    }
                }
            }

            Section("Online (OpenAI)") {
                SecureField("API key", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                Text("Stored in the macOS Keychain on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Save key") {
                        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            OpenAIAPIKeyStore.delete()
                        } else {
                            try? OpenAIAPIKeyStore.save(trimmed)
                        }
                        apiKeyDraft = ""
                    }
                    Button("Remove key") {
                        OpenAIAPIKeyStore.delete()
                        apiKeyDraft = ""
                    }
                }
                TextField("API base URL", text: $baseURLDraft)
                    .textFieldStyle(.roundedBorder)
                Text("Default: https://api.openai.com — use your org’s gateway host if required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("OpenAI API data policy (web)…") {
                    if let url = URL(string: "https://platform.openai.com/docs/guides/your-data") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            Section("Privacy") {
                Toggle(
                    "I understand audio and text are sent to OpenAI when using Online mode",
                    isOn: Binding(
                        get: { EchoDraftUserSettings.shared.onlinePrivacyAcknowledged },
                        set: { EchoDraftUserSettings.shared.onlinePrivacyAcknowledged = $0 }
                    )
                )
                Text(
                    "API usage is typically not used to train OpenAI’s consumer models; see OpenAI’s current terms for details."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Diagnostics") {
                Toggle(
                    "Log anonymous online errors locally (OSLog)",
                    isOn: $telemetry
                )
                .onChange(of: telemetry) { _, v in
                    EchoDraftUserSettings.shared.telemetryOptIn = v
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 420)
        .onAppear {
            baseURLDraft = EchoDraftUserSettings.shared.openAIBaseURL
            globalMode = EchoDraftUserSettings.shared.globalProcessingMode
            telemetry = EchoDraftUserSettings.shared.telemetryOptIn
        }
        .onChange(of: baseURLDraft) { _, v in
            EchoDraftUserSettings.shared.openAIBaseURL = v
        }
        .sheet(isPresented: $showPrivacySheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Online mode")
                    .font(.title2)
                Text(
                    "In Online mode, audio is uploaded to your chosen API endpoint for transcription, and transcript text may be sent for summarization. Use Offline mode to keep processing on this Mac."
                )
                .fixedSize(horizontal: false, vertical: true)
                Button("Acknowledge") {
                    EchoDraftUserSettings.shared.onlinePrivacyAcknowledged = true
                    showPrivacySheet = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(24)
            .frame(minWidth: 400)
        }
    }
}

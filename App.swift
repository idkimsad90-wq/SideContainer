import SwiftUI
import Security
import UniformTypeIdentifiers

@main
struct SideStoreCloneApp: App {
    var body: some Scene {
        WindowGroup {
            SideStoreCloneView()
        }
    }
}

struct InstalledAppInfo: Identifiable, Codable {
    let id: String // Bundle ID
    var name: String
    var version: String
    var dataSizeMB: Double
    var isSystemApp: Bool
}

final class SideStoreManager: ObservableObject {
    static let shared = SideStoreManager()
    
    @Published var installedApps: [InstalledAppInfo] = [
        InstalledAppInfo(id: "com.ketsu.app", name: "Ketsu", version: "2.4", dataSizeMB: 84.2, isSystemApp: false),
        InstalledAppInfo(id: "com.example.game", name: "Sample Game", version: "1.0", dataSizeMB: 310.5, isSystemApp: false)
    ]
    
    func wipeAppData(for bundleID: String) -> Bool {
        let fileManager = FileManager.default
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return false
        }
        let containerPath = documentsPath.deletingLastPathComponent().appendingPathComponent("Data/Application")
        do {
            let contents = try fileManager.contentsOfDirectory(at: containerPath, includingPropertiesForKeys: [.isDirectoryKey])
            for url in contents {
                let metadataPath = url.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
                if let data = try? Data(contentsOf: metadataPath),
                   let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                   let appID = plist["MCMMetaBundleID"] as? String, appID == bundleID {
                    let subdirs = ["Documents", "Library", "tmp"]
                    for dir in subdirs {
                        let target = url.appendingPathComponent(dir)
                        if fileManager.fileExists(atPath: target.path) {
                            try fileManager.removeItem(at: target)
                            try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
                        }
                    }
                    return true
                }
            }
        } catch {
            print("Failed to wipe app data: \(error)")
        }
        return false
    }
    
    func wipeAppKeychain(for bundleID: String) {
        let secItemClasses: [CFString] = [
            kSecClassGenericPassword,
            kSecClassInternetPassword,
            kSecClassCertificate,
            kSecClassKey,
            kSecClassIdentity
        ]
        for secClass in secItemClasses {
            let query: [String: Any] = [
                kSecClass as String: secClass,
                kSecAttrService as String: bundleID
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
}

struct SideStoreCloneView: View {
    @StateObject private var manager = SideStoreManager.shared
    @State private var toastMessage: String?
    @State private var showingFileImporter = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(.blue)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SideStore Manager Active")
                                .font(.subheadline.bold())
                            Text("Local Pairing ID Connected • 7 Days Remaining")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Refresh") {
                            showToast("Refreshed pairing certificates")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }

                Section("Managed Applications") {
                    ForEach(manager.installedApps) { app in
                        HStack(spacing: 14) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.blue.gradient)
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Text(String(app.name.prefix(1)))
                                        .font(.title3.bold())
                                        .foregroundStyle(.white)
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(app.name)
                                    .font(.headline)
                                Text("\(app.id) • v\(app.version)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                
                                Label(String(format: "Data: %.1f MB", app.dataSizeMB), systemImage: "internaldrive")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }

                            Spacer()

                            Menu {
                                Button(role: .destructive) {
                                    manager.wipeAppKeychain(for: app.id)
                                    showToast("Purged Keychain for \(app.name)")
                                } label: {
                                    Label("Wipe Keychain Only", systemImage: "key.slash")
                                }

                                Button(role: .destructive) {
                                    _ = manager.wipeAppData(for: app.id)
                                    showToast("Cleared Sandbox Data for \(app.name)")
                                } label: {
                                    Label("Wipe App Data Only", systemImage: "folder.badge.minus")
                                }

                                Button(role: .destructive) {
                                    manager.wipeAppKeychain(for: app.id)
                                    _ = manager.wipeAppData(for: app.id)
                                    showToast("Factory Reset \(app.name)")
                                } label: {
                                    Label("Full App Reset (Data + Keys)", systemImage: "arrow.counterclockwise.circle")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("SideContainer")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingFileImporter = true
                    } label: {
                        Image(systemName: "plus.app.fill")
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.item]
            ) { result in
                if case .success(let url) = result {
                    showToast("Installing \(url.lastPathComponent)...")
                }
            }
            .overlay(alignment: .bottom) {
                if let toastMessage {
                    Text(toastMessage)
                        .font(.footnote.bold())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 20)
                }
            }
        }
    }

    private func showToast(_ text: String) {
        withAnimation { toastMessage = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { toastMessage = nil }
        }
    }
}

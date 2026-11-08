import SwiftUI
import Security
import UniformTypeIdentifiers

@main
struct SideContainerApp: App {
    var body: some Scene {
        WindowGroup {
            SideManagerAppView()
        }
    }
}

struct AppContainer: Identifiable, Codable {
    let id: UUID
    var name: String
    var bundleID: String
    var version: String
    var keychainGroupIndex: Int
    var dataSizeMB: Double
    var keychainItemsCount: Int
}

final class ContainerManager {
    static let shared = ContainerManager()
    
    var containersRootURL: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Containers", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
    
    func createContainerFolder(for id: UUID) {
        let base = containersRootURL.appendingPathComponent(id.uuidString)
        for sub in ["Documents", "Library/Preferences", "tmp", "SystemData"] {
            try? FileManager.default.createDirectory(
                at: base.appendingPathComponent(sub),
                withIntermediateDirectories: true
            )
        }
    }
    
    func wipeAppKeychain(for container: AppContainer) {
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
                kSecAttrLabel as String: "Slot_\(container.keychainGroupIndex)"
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
    
    func wipeAppData(for container: AppContainer) {
        let containerURL = containersRootURL.appendingPathComponent(container.id.uuidString)
        try? FileManager.default.removeItem(at: containerURL)
        createContainerFolder(for: container.id)
    }
}

struct SideManagerAppView: View {
    @State private var containers: [AppContainer] = [
        AppContainer(id: UUID(), name: "Demo Container 1", bundleID: "com.demo.app1", version: "1.0.0", keychainGroupIndex: 1, dataSizeMB: 42.5, keychainItemsCount: 8),
        AppContainer(id: UUID(), name: "Secondary Sandbox", bundleID: "com.demo.app2", version: "2.1.0", keychainGroupIndex: 2, dataSizeMB: 18.2, keychainItemsCount: 3)
    ]
    @State private var showingFileImporter = false
    @State private var toastMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sandbox Manager Active")
                                .font(.subheadline.bold())
                            Text("Isolated Keychain & Data Containers")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                Section("Installed Containers (\(containers.count)/128 Slots)") {
                    ForEach(containers.indices, id: \.self) { index in
                        let app = containers[index]
                        HStack(spacing: 14) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(LinearGradient(colors: [.indigo, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Text(String(app.name.prefix(1)).uppercased())
                                        .font(.title3.bold())
                                        .foregroundStyle(.white)
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(app.name)
                                    .font(.headline)
                                Text("\(app.bundleID) • Slot #\(app.keychainGroupIndex)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                
                                HStack(spacing: 10) {
                                    Label(String(format: "%.1f MB", app.dataSizeMB), systemImage: "internaldrive")
                                    Label("\(app.keychainItemsCount) Keys", systemImage: "key.fill")
                                }
                                .font(.caption2)
                                .foregroundStyle(.blue)
                            }

                            Spacer()

                            Menu {
                                Button(role: .destructive) {
                                    ContainerManager.shared.wipeAppKeychain(for: app)
                                    containers[index].keychainItemsCount = 0
                                    showToast("Wiped Keychain Slot #\(app.keychainGroupIndex) for \(app.name)")
                                } label: {
                                    Label("Wipe Keychain Only", systemImage: "key.slash")
                                }

                                Button(role: .destructive) {
                                    ContainerManager.shared.wipeAppData(for: app)
                                    containers[index].dataSizeMB = 0.0
                                    showToast("Wiped Sandbox Data for \(app.name)")
                                } label: {
                                    Label("Wipe App Data Only", systemImage: "folder.badge.minus")
                                }

                                Button(role: .destructive) {
                                    ContainerManager.shared.wipeAppKeychain(for: app)
                                    ContainerManager.shared.wipeAppData(for: app)
                                    containers[index].keychainItemsCount = 0
                                    containers[index].dataSizeMB = 0.0
                                    showToast("Hard Reset complete for \(app.name)")
                                } label: {
                                    Label("Hard Reset (Data + Keychain)", systemImage: "arrow.counterclockwise.circle")
                                }
                                
                                Divider()
                                
                                Button(role: .destructive) {
                                    containers.remove(at: index)
                                    showToast("Deleted container \(app.name)")
                                } label: {
                                    Label("Delete Container", systemImage: "trash")
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
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    let newID = UUID()
                    let nextSlot = (containers.map { $0.keychainGroupIndex }.max() ?? 0) + 1
                    let cleanName = url.deletingPathExtension().lastPathComponent
                    ContainerManager.shared.createContainerFolder(for: newID)
                    let newContainer = AppContainer(
                        id: newID,
                        name: cleanName,
                        bundleID: "com.container.\(cleanName.lowercased())",
                        version: "1.0",
                        keychainGroupIndex: nextSlot,
                        dataSizeMB: 12.4,
                        keychainItemsCount: 1
                    )
                    containers.append(newContainer)
                    showToast("Created isolated container for \(cleanName)")
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

import SwiftUI
import Foundation

/// A transient user-facing notice.
public struct ToastItem: Identifiable, Equatable {
    public enum Kind { case info, error, success }
    public let id = UUID()
    public var kind: Kind
    public var text: String
}

/// Root observable store. `@MainActor` so all UI-facing mutation is main-thread safe.
/// Services do their work off-actor and hop back here to publish results.
@MainActor
public final class AppState: ObservableObject {
    /// Weak back-reference so the AppDelegate can consult job state on quit (set in init).
    public static weak var current: AppState?
    // Settings & secret gate
    @Published public var settings: AppSettings
    @Published public private(set) var hasKey: Bool
    @Published public var showSettings: Bool = false

    // Library & jobs (populated as services come online)
    @Published public var library: Library = .empty
    @Published public var jobs: [Job] = []

    /// Models offered in the picker — defaults to presets, replaced by the live account list.
    @Published public var availableModels: [ModelPreset] = ModelCatalog.presets
    /// A 1 Hz clock published by the retry ticker so retry countdowns re-render.
    @Published public private(set) var clock = Date()

    // Notices
    @Published public var toast: ToastItem?

    // Selection (asset browser)
    @Published public var selectedAsset: Asset?

    // Collaborators
    public let keychain: KeychainStoring
    let styleStore: StyleStoring
    let libraryStore: LibraryStoring
    let engine: SummarizationEngine
    let youtube: YouTubeServicing
    let anthropic: AnthropicStreaming
    private let watcher: DirectoryWatcher

    var queueTask: Task<Void, Never>?
    var currentJobTask: Task<Void, Never>?
    var currentJobID: UUID?
    var retryTicker: Task<Void, Never>?
    func setClock(_ d: Date) { clock = d }
    private var saveTask: Task<Void, Never>?
    private var modelsTask: Task<Void, Never>?

    public init(keychain: KeychainStoring = KeychainStore(),
                styleStore: StyleStoring = StyleStore(),
                libraryStore: LibraryStoring = LibraryStore(),
                anthropic: AnthropicStreaming = AnthropicClient(),
                youtube: YouTubeServicing = YouTubeService()) {
        self.keychain = keychain
        self.styleStore = styleStore
        self.libraryStore = libraryStore
        self.anthropic = anthropic
        self.youtube = youtube
        self.engine = SummarizationEngine(extractor: TextExtractor(),
                                          anthropic: anthropic,
                                          youtube: youtube)
        self.watcher = DirectoryWatcher()
        var loaded = AppSettings.load()
        // Test/verification hook: override the library root so smoke runs don't touch ~/Documents.
        if let lib = ProcessInfo.processInfo.environment["SUMBEE_LIBRARY"], !lib.isEmpty {
            loaded.libraryRootPath = lib
        }
        self.settings = loaded
        self.hasKey = keychain.hasKey
        AppState.current = self
    }

    /// Called once when the scene appears.
    public func bootstrap() {
        migrateLibraryToDefaultIfNeeded()
        ensureLibrary()
        reloadLibrary()
        startWatching()
        // API-key gate: if no key, open Settings on launch (spec §11).
        // Skipped during screenshot runs so the main UI is captured.
        if !hasKey && ProcessInfo.processInfo.environment["SUMBEE_SHOT"] == nil {
            showSettings = true
        }
        if hasKey { fetchModels() }
    }

    /// Populate the model picker from the account's available models (FR-023). Keeps the
    /// preset fallback on any failure (offline, no key). Presets are always kept selectable.
    public func fetchModels() {
        guard let key = keychain.load(), !key.isEmpty else { return }
        let client = anthropic
        modelsTask?.cancel()                     // dedupe overlapping fetches (last writer wins)
        modelsTask = Task { [weak self] in
            let models = await client.listModels(key)
            guard let self, !Task.isCancelled, !models.isEmpty else { return }
            var merged = models.map {
                ModelPreset(id: $0.id, displayName: $0.displayName,
                            capabilities: ModelCatalog.capabilities(for: $0.id))
            }
            for preset in ModelCatalog.presets where !merged.contains(where: { $0.id == preset.id }) {
                merged.append(preset)
            }
            self.availableModels = merged
        }
    }

    /// Models for the pickers, sorted alphabetically by display name.
    public var modelsForPicker: [ModelPreset] {
        availableModels.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Switch the active model and keep generation settings consistent everywhere (bottom-bar
    /// menu or Settings picker both route through this).
    public func selectModel(_ id: String) {
        settings.model = id
        normalizeGenerationForModel()
        persistSettings()
    }

    /// Clamp effort + max-output-tokens to the current model's capabilities. Only acts on a
    /// known/complete model selection so it doesn't disrupt free-text typing of a custom id.
    public func normalizeGenerationForModel() {
        let id = settings.model
        let known = ModelCatalog.isPreset(id) || availableModels.contains { $0.id == id }
        guard known else { return }
        let caps = ModelCatalog.capabilities(for: id)
        if let e = settings.effort, !caps.effortLevels.contains(e) { settings.effort = nil }
        settings.maxOutputTokens = min(max(settings.maxOutputTokens, 512), caps.maxOutputCeiling)
    }

    // MARK: - Key management

    public func saveKey(_ key: String) {
        do {
            try keychain.save(key.trimmingCharacters(in: .whitespacesAndNewlines))
            hasKey = keychain.hasKey
        } catch {
            present(.error, "Couldn’t save the key: \(error.localizedDescription)")
        }
    }

    public func removeKey() {
        try? keychain.remove()
        hasKey = keychain.hasKey
        showSettings = true
    }

    /// Save then do a cheap validation call. Returns nil on success or an error message.
    public func saveAndValidateKey(_ key: String) async -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Key is empty." }
        saveKey(trimmed)
        let result = await anthropic.validateKey(trimmed, model: settings.model)
        switch result {
        case .success:
            present(.success, "API key validated.")
            fetchModels()
            return nil
        case .failure(let err):
            return err.userMessage
        }
    }

    /// True if a key is present; otherwise gate to Settings and return false.
    func requireKey() -> Bool {
        if hasKey { return true }
        showSettings = true
        present(.error, "Set your API key in Settings to begin.")
        return false
    }

    /// Re-gate to Settings after an authentication failure (spec §11).
    func handleAuthFailure() {
        hasKey = keychain.hasKey
        showSettings = true
        present(.error, "Your API key was rejected. Please update it.")
    }

    // MARK: - Library

    /// One-time move of the library from a pre-rename default location into the current default
    /// `~/Sumbee Summaries`, so "Reveal in Finder" works (see AppSettings.defaultLibraryRootPath:
    /// `~/Documents` is TCC-protected). Only fires for installs still pointed at a legacy default —
    /// custom locations and the SUMBEE_LIBRARY test override are left untouched. On any failure it
    /// keeps the old location (no data loss).
    func migrateLibraryToDefaultIfNeeded() {
        let fm = FileManager.default
        let current = (settings.libraryRootPath as NSString).expandingTildeInPath
        let target = (AppSettings.defaultLibraryRootPath as NSString).expandingTildeInPath
        guard current != target else { return }

        // Only migrate installs still on a known pre-rename default (not a user-chosen location).
        let legacies = AppSettings.legacyLibraryRootPaths.map { ($0 as NSString).expandingTildeInPath }
        guard legacies.contains(current) else { return }

        var legacyIsDir: ObjCBool = false
        let legacyExists = fm.fileExists(atPath: current, isDirectory: &legacyIsDir) && legacyIsDir.boolValue
        let targetExists = fm.fileExists(atPath: target)

        if legacyExists && !targetExists {
            do {
                try fm.moveItem(atPath: current, toPath: target)
                present(.success, "Moved your library to “Sumbee Summaries”.")
            } catch {
                present(.error, "Couldn’t move the library to ~/Sumbee Summaries (\(error.localizedDescription)). Keeping the old location.")
                return                                   // keep legacy path on failure — no data loss
            }
        }
        // Point settings at the new location (ensureLibrary seeds it fresh if nothing was moved).
        settings.libraryRootPath = AppSettings.defaultLibraryRootPath
        persistSettings()
    }

    func ensureLibrary() {
        let root = settings.libraryRootURL
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            // Seed default styles on first run (when no style folders exist yet).
            let existing = (try? styleStore.loadStyles(root: root)) ?? []
            if existing.isEmpty {
                try styleStore.seedDefaults(root: root)
            }
        } catch {
            present(.error, "Couldn’t prepare the library folder: \(error.localizedDescription)")
        }
    }

    /// Rescan the library off the main actor (it reads every asset file), then publish on main.
    public func reloadLibrary() {
        let root = settings.libraryRootURL
        let store = libraryStore
        Task { [weak self] in
            let outcome = await AppState.scanOffMain(store: store, root: root)
            guard let self else { return }
            switch outcome {
            case .success(let lib): self.library = lib
            case .failure(let err): self.present(.error, "Couldn’t read the library: \(err.localizedDescription)")
            }
        }
    }

    private static func scanOffMain(store: LibraryStoring, root: URL) async -> Result<Library, Error> {
        await Task.detached(priority: .userInitiated) {
            do { return .success(try store.scan(root: root)) }
            catch { return .failure(error) }
        }.value
    }

    func startWatching() {
        watcher.start(root: settings.libraryRootURL) { [weak self] in
            Task { @MainActor in self?.reloadLibrary() }
        }
    }

    public func changeLibraryRoot(to url: URL) {
        settings.libraryRootPath = url.path
        persistSettings()
        watcher.stop()
        ensureLibrary()
        reloadLibrary()
        startWatching()
    }

    // MARK: - Settings persistence

    public func persistSettings() {
        saveTask?.cancel()
        do { try settings.save() }
        catch { present(.error, "Couldn’t save settings: \(error.localizedDescription)") }
    }

    /// Debounced settings save — coalesces rapid edits (e.g. typing in a text field) into one
    /// write rather than persisting on every keystroke.
    public func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            self?.persistSettings()
        }
    }

    // MARK: - Styles convenience

    public var fileStyles: [SummaryStyle] {
        library.styles.filter { $0.channel == .file && $0.enabled }.sorted { $0.order < $1.order }
    }
    public var youtubeStyles: [SummaryStyle] {
        library.styles.filter { $0.channel == .youtube && $0.enabled }.sorted { $0.order < $1.order }
    }

    // MARK: - Toast

    public func present(_ kind: ToastItem.Kind, _ text: String) {
        toast = ToastItem(kind: kind, text: text)
    }
    public func dismissToast() { toast = nil }
}

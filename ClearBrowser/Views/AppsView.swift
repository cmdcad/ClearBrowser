import SwiftUI
import StoreKit
import FirebaseAuth

private enum HubApp: String, CaseIterable, Identifiable {
    case reloCalc, creditTrack, bingBot, textReader, pointsTrack
    var id: String { rawValue }
    var requiresPurchase: Bool { self != .textReader && self != .pointsTrack }
    var productID: String { "com.mikeso.ClearBrowser.apphub." + rawValue }
    var title: String {
        switch self { case .reloCalc: return "ReloCalc"; case .creditTrack: return "CreditTrack"; case .bingBot: return "BingBot"; case .textReader: return "Text Reader"; case .pointsTrack: return "PointsTrack" }
    }
    var subtitle: String {
        switch self {
        case .reloCalc: return "Plan your relocation budget"
        case .creditTrack: return "Track payments and pay off debt"
        case .bingBot: return "Build queries and track Bing searches"
        case .textReader: return "Turn text and articles into read-along audio"
        case .pointsTrack: return "Track reward points and project future value"
        }
    }
    var icon: String {
        switch self { case .reloCalc: return "globe.americas.fill"; case .creditTrack: return "creditcard.fill"; case .bingBot: return "magnifyingglass"; case .textReader: return "text.book.closed.fill"; case .pointsTrack: return "star.circle.fill" }
    }
}

@MainActor
private final class HubPurchases: ObservableObject {
    static let shared = HubPurchases()
    @Published private(set) var owned = Set<String>()
    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var checking = true
    @Published private(set) var busy = false
    @Published var message: String?
    @Published private(set) var developerAccess = false
    #if DEBUG
    @Published var debugAccess = false
    #endif
    private var authListener: AuthStateDidChangeListenerHandle?
    private var claimRevision = 0
    private var developerUID: String?
    private var updates: Task<Void, Never>?

    private init() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.developerAccess = false
                await self.refreshDeveloperAccess()
            }
        }
        updates = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let self else { return }
                guard case .verified(let transaction) = result,
                      HubApp.allCases.contains(where: { $0.productID == transaction.productID }) else { continue }
                await self.refreshEntitlements()
                await transaction.finish()
            }
        }
    }
    func owns(_ app: HubApp) -> Bool {
        if !app.requiresPurchase { return true }
        #if DEBUG
        if debugAccess { return true }
        #endif
        return (developerAccess && developerUID == Auth.auth().currentUser?.uid) || owned.contains(app.productID)
    }
    func refreshDeveloperAccess() async {
        claimRevision += 1
        let revision = claimRevision
        developerAccess = false
        developerUID = nil
        guard let user = Auth.auth().currentUser else { return }
        do {
            let token = try await user.getIDTokenResult(forcingRefresh: true)
            guard revision == claimRevision, Auth.auth().currentUser?.uid == user.uid else { return }
            developerAccess = token.claims["developer"] as? Bool == true
            developerUID = developerAccess ? user.uid : nil
        } catch {
            // Failed checks leave developer access locked; verified purchases still work.
        }
    }
    func refreshEntitlements() async {
        var verifiedIDs = Set<String>()
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productType == .nonConsumable, transaction.revocationDate == nil,
                  HubApp.allCases.contains(where: { $0.productID == transaction.productID }) else { continue }
            verifiedIDs.insert(transaction.productID)
        }
        owned = verifiedIDs
        checking = false
    }
    func load() async {
        await refreshDeveloperAccess()
        await refreshEntitlements()
        do {
            let available = try await Product.products(for: HubApp.allCases.filter { $0.requiresPurchase }.map(\.productID))
            products = Dictionary(uniqueKeysWithValues: available.filter { $0.type == .nonConsumable }.map { ($0.id, $0) })
        } catch {
            message = "Purchase options could not load. Check your connection and try again."
        }
    }
    func purchase(_ app: HubApp) async {
        guard !busy, let product = products[app.productID] else { return }
        busy = true
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result,
                      transaction.productID == app.productID, transaction.revocationDate == nil else {
                    message = "The purchase could not be verified. Access remains locked."; return
                }
                await refreshEntitlements()
                await transaction.finish()
            case .pending: message = "Your purchase is awaiting approval. Access unlocks once Apple confirms it."
            case .userCancelled: break
            @unknown default: message = "The purchase has not completed. Please try again."
            }
        } catch { message = "The purchase could not complete. Please try again." }
    }
    func restore() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            message = owned.isEmpty ? "No AppHub purchases were found for this Apple Account." : "Your AppHub purchases have been restored."
        } catch { message = "Purchases could not be restored. Please try again." }
    }
}

struct AppsView: View {
    let onClose: () -> Void
    @ObservedObject var model: ReloCalcModel
    @StateObject private var purchases = HubPurchases.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedApp: HubApp?
    @State private var purchaseApp: HubApp?
    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            if let app = selectedApp, purchases.owns(app) {
                switch app {
                case .reloCalc: ReloCalcView(model: model, action: onClose)
                case .creditTrack: CreditTrackView { selectedApp = nil }
                case .bingBot: BingBotView { selectedApp = nil }
                case .textReader: TextReaderView { selectedApp = nil }
                case .pointsTrack: PointsTrackView { selectedApp = nil }
                }
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Button(action: onClose) { Label("Browser", systemImage: "chevron.left") }
                        Spacer()
                        Text("Apps").font(.headline)
                        Spacer()
                        Color.clear.frame(width: 68)
                    }.font(.subheadline).frame(height: 32)
                    Text("Your apps and reading tools. Paid apps are one-time purchases.").font(.subheadline).foregroundStyle(.secondary)
                    #if DEBUG
                    Toggle("Developer access (Debug only)", isOn: $purchases.debugAccess)
                        .font(.subheadline)
                    #endif
                    if purchases.developerAccess {
                        Label("Developer account · All apps unlocked", systemImage: "checkmark.shield.fill")
                            .font(.caption).foregroundStyle(.green)
                    }
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(HubApp.allCases) { app in
                                Button {
                                    if purchases.owns(app) { selectedApp = app } else { purchaseApp = app }
                                } label: {
                                    VStack(alignment: .leading, spacing: 14) {
                                        Image(systemName: app.icon)
                                            .font(.system(size: 28, weight: .medium)).foregroundStyle(.white)
                                            .frame(width: 56, height: 56)
                                            .background((app == .reloCalc ? Color.teal : Color.blue).gradient, in: RoundedRectangle(cornerRadius: 16))
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(app.title).font(.headline).foregroundStyle(.primary)
                                            Text(app.subtitle).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                                        }
                                        Spacer(minLength: 0)
                                        Label(purchases.owns(app) ? "Open" : (purchases.products[app.productID]?.displayPrice ?? "$2.99 USD"),
                                              systemImage: purchases.owns(app) ? "checkmark.circle" : "lock.fill")
                                            .font(.subheadline.bold())
                                            .foregroundStyle(purchases.owns(app) ? Color.green : Color.blue)
                                        if !purchases.owns(app) {
                                            Text("One-time purchase").font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading).padding(16)
                                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                                }
                                .buttonStyle(.plain).disabled(purchases.checking && app.requiresPurchase)
                                .accessibilityLabel(purchases.owns(app) ? "Open \(app.title)" : "Unlock \(app.title)")
                            }
                        }
                    }
                    if purchases.checking { ProgressView("Checking purchases…") }
                    Button("Restore Purchases") { Task { await purchases.restore() } }.disabled(purchases.busy)
                    Button("Refresh Account Access") { Task { await purchases.refreshDeveloperAccess() } }
                        .font(.caption)
                    Spacer(minLength: 0)
                }.padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await purchases.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await purchases.refreshDeveloperAccess()
                    await purchases.refreshEntitlements()
                }
            }
        }
        .sheet(item: $purchaseApp) { app in
            VStack(spacing: 20) {
                Image(systemName: app.icon).font(.system(size: 48)).foregroundStyle(.blue)
                Text("Unlock \(app.title)").font(.title2.bold())
                Text(app.subtitle).foregroundStyle(.secondary)
                Text("One-time purchase. Restore access with the same Apple Account.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if purchases.owns(app) {
                    Button("Open \(app.title)") { purchaseApp = nil; selectedApp = app }.buttonStyle(.borderedProminent)
                } else if let product = purchases.products[app.productID] {
                    Button("Buy for \(product.displayPrice)") { Task { await purchases.purchase(app) } }
                        .buttonStyle(.borderedProminent).disabled(purchases.busy)
                } else {
                    Text("Purchases are currently unavailable.").font(.footnote)
                    Button("Try Again") { Task { await purchases.load() } }.disabled(purchases.busy)
                }
                if purchases.busy { ProgressView() }
                Button("Restore Purchases") { Task { await purchases.restore() } }.disabled(purchases.busy)
                Button("Close") { purchaseApp = nil }
            }.padding(28).presentationDetents([.medium, .large])
            .alert("AppHub", isPresented: messageBinding) {
                Button("OK") { purchases.message = nil }
            } message: { Text(purchases.message ?? "") }
        }
        .alert("AppHub", isPresented: Binding(get: { purchaseApp == nil && purchases.message != nil }, set: { if !$0 { purchases.message = nil } })) {
            Button("OK") { purchases.message = nil }
        } message: { Text(purchases.message ?? "") }
    }
    private var messageBinding: Binding<Bool> {
        Binding(get: { purchases.message != nil }, set: { if !$0 { purchases.message = nil } })
    }
}

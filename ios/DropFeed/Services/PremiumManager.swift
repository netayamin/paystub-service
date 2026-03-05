import Foundation
import StoreKit

@MainActor
final class PremiumManager: ObservableObject {
    static let shared = PremiumManager()
    
    static let productId = "com.dropfeed.premium.monthly"
    
    @Published var isPremium = false
    @Published var products: [Product] = []
    @Published var purchaseInProgress = false
    @Published var errorMessage: String?
    
    private var updateListenerTask: Task<Void, Never>?
    
    private var unlockAllForTesting: Bool {
        if let flag = Bundle.main.object(forInfoDictionaryKey: "UNLOCK_ALL_FEATURES") as? Bool, flag {
            return true
        }
#if DEBUG
        return true
#else
        return false
#endif
    }
    
    init() {
        updateListenerTask = listenForTransactions()
        Task { await checkEntitlements() }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    // MARK: - Products
    
    func loadProducts() async {
        if unlockAllForTesting {
            isPremium = true
            return
        }
        do {
            products = try await Product.products(for: [Self.productId])
        } catch {
            errorMessage = "Failed to load products"
        }
    }
    
    var monthlyProduct: Product? {
        products.first { $0.id == Self.productId }
    }
    
    var priceLabel: String {
        monthlyProduct?.displayPrice ?? "$4.99/mo"
    }
    
    // MARK: - Purchase
    
    func purchase() async {
        if unlockAllForTesting {
            isPremium = true
            return
        }
        guard let product = monthlyProduct else {
            await loadProducts()
            guard let product = monthlyProduct else { return }
            await doPurchase(product)
            return
        }
        await doPurchase(product)
    }
    
    private func doPurchase(_ product: Product) async {
        purchaseInProgress = true
        errorMessage = nil
        defer { purchaseInProgress = false }
        
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                isPremium = true
            case .userCancelled:
                break
            case .pending:
                errorMessage = "Purchase pending approval"
            @unknown default:
                break
            }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
        }
    }
    
    func restore() async {
        if unlockAllForTesting {
            isPremium = true
            return
        }
        try? await AppStore.sync()
        await checkEntitlements()
    }
    
    // MARK: - Entitlements
    
    func checkEntitlements() async {
        if unlockAllForTesting {
            isPremium = true
            return
        }
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                if transaction.productID == Self.productId {
                    isPremium = true
                    return
                }
            }
        }
        isPremium = false
    }
    
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                let transaction = await MainActor.run { [weak self] in
                    try? self?.checkVerified(result)
                }
                if let transaction {
                    await transaction.finish()
                    await self?.checkEntitlements()
                }
            }
        }
    }
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
    
    // MARK: - Premium feature gates
    
    static let freeWatchlistLimit = 3
    static let freeLikelyToOpenLimit = 3
    
    var canAddMoreWatches: Bool {
        isPremium
    }
    
    func watchlistLimitReached(currentCount: Int) -> Bool {
        !isPremium && currentCount >= Self.freeWatchlistLimit
    }
    
    func likelyToOpenLimit() -> Int {
        isPremium ? .max : Self.freeLikelyToOpenLimit
    }
}

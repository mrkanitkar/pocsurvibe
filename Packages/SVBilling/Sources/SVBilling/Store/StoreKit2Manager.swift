import Foundation
import os
import StoreKit
import SVCore

/// StoreKit 2 subscription management.
/// Handles product fetching, purchasing, and entitlement verification.
/// Full implementation in Phase 2.
@MainActor
@Observable
public final class StoreKit2Manager {
    private static let logger = Logger.survibe(category: "StoreKit2Manager")
    public static let shared = StoreKit2Manager()

    /// Current subscription tier.
    public var currentTier: SubscriptionTier = .free

    private init() {}

    /// Fetch available products from the App Store.
    public func fetchProducts() async throws {
        Self.logger.info("Fetching products (Phase 2 stub)")
        // Phase 2: Product.products(for:)
    }

    /// Purchase a subscription product.
    public func purchase(_ tier: SubscriptionTier) async throws {
        Self.logger.info("Purchase requested: \(tier.rawValue, privacy: .public)")
        // Phase 2: product.purchase()
    }

    /// Restore purchases.
    public func restorePurchases() async throws {
        Self.logger.info("Restore purchases requested")
        // Phase 2: Transaction.currentEntitlements
    }
}

import Combine
import Foundation

#if canImport(RevenueCat)
import RevenueCat
#endif

enum AppSubscriptionPeriod {
    case weekly
    case monthly
    case yearly
}

struct AppSubscriptionOption: Identifiable, Equatable {
    let id: String
    let title: String
    let price: String
    let description: String
    let period: AppSubscriptionPeriod
    let weeklyPrice: String?
    let savingsTag: String?
    let hasIntroOffer: Bool

    static let fallbackWeekly = AppSubscriptionOption(
        id: "weekly",
        title: "Weekly",
        price: "$2.00",
        description: "Billed weekly",
        period: .weekly,
        weeklyPrice: nil,
        savingsTag: nil,
        hasIntroOffer: false
    )

    static let fallbackYearly = AppSubscriptionOption(
        id: "annual",
        title: "Yearly",
        price: "$79.98",
        description: "Billed yearly",
        period: .yearly,
        weeklyPrice: "$1.54",
        savingsTag: "SAVE 23%",
        hasIntroOffer: false
    )
}

struct AppOfferingsResult {
    let weekly: AppSubscriptionOption?
    let yearly: AppSubscriptionOption?
    let showFirstTimeOffer: Bool
}

struct AppSubscriptionError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

@MainActor
final class AppSubscriptionService {
    static let shared = AppSubscriptionService()

    @Published private(set) var isPremium = false
    @Published private(set) var activeSubscriptionPeriod: AppSubscriptionPeriod?

    #if canImport(RevenueCat)
    private var lastPackages: [String: Package] = [:]
    #endif

    private var configured = false

    private init() {}

    func initialize() {
        #if canImport(RevenueCat)
        guard !configured else { return }
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String,
              apiKey.isEmpty == false,
              apiKey.contains("$(") == false
        else {
            return
        }

        Purchases.logLevel = isDebugBuild ? .debug : .warn
        Purchases.configure(withAPIKey: apiKey)
        configured = true
        checkSubscriptionStatus()
        #endif
    }

    func isConfigured() -> Bool {
        configured
    }

    func checkSubscriptionStatus() {
        #if canImport(RevenueCat)
        guard configured else { return }
        Purchases.shared.getCustomerInfo { [weak self] customerInfo, error in
            guard let self, let customerInfo else {
                #if DEBUG
                if let error {
                    print("customer_info_fetch_failed", error.localizedDescription)
                }
                #endif
                return
            }
            self.updatePremiumStatus(customerInfo: customerInfo)
        }
        #endif
    }

    func fetchOfferings() async -> AppOfferingsResult? {
        #if canImport(RevenueCat)
        guard configured else { return nil }
        return await withCheckedContinuation { continuation in
            Purchases.shared.getOfferings { [weak self] offerings, _ in
                guard let self, let current = offerings?.current else {
                    continuation.resume(returning: nil)
                    return
                }

                let weeklyPackage = current.availablePackages.first { package in
                    package.packageType == .weekly
                } ?? current.availablePackages.first { package in
                    package.packageType == .monthly
                }
                let yearlyPackage = current.availablePackages.first { package in
                    package.packageType == .annual
                }

                self.lastPackages = Dictionary(
                    uniqueKeysWithValues: current.availablePackages.map { ($0.identifier, $0) }
                )

                let weekly = weeklyPackage.map { self.mapPackageToUi($0, weeklyPrice: nil, savingsTag: nil) }
                let yearlyWeeklyPrice = yearlyPackage.flatMap { self.weeklyEquivalent(for: $0) }
                let savingsTag = self.savingsTag(weeklyPackage: weeklyPackage, yearlyPackage: yearlyPackage)
                let yearly = yearlyPackage.map {
                    self.mapPackageToUi($0, weeklyPrice: yearlyWeeklyPrice, savingsTag: savingsTag)
                }
                continuation.resume(returning: AppOfferingsResult(
                    weekly: weekly,
                    yearly: yearly,
                    showFirstTimeOffer: weekly?.hasIntroOffer == true || yearly?.hasIntroOffer == true
                ))
            }
        }
        #else
        return nil
        #endif
    }

    func purchase(optionId: String) async -> Result<Void, AppSubscriptionError> {
        #if canImport(RevenueCat)
        guard configured else { return .failure(AppSubscriptionError(message: "RevenueCat not configured")) }
        guard let package = lastPackages[optionId] else { return .failure(AppSubscriptionError(message: "Package not found")) }
        return await withCheckedContinuation { continuation in
            Purchases.shared.purchase(package: package) { [weak self] _, customerInfo, error, userCancelled in
                if userCancelled {
                    continuation.resume(returning: .failure(AppSubscriptionError(message: "cancelled")))
                    return
                }
                if let error {
                    continuation.resume(returning: .failure(AppSubscriptionError(message: error.localizedDescription)))
                    return
                }
                guard let customerInfo, self?.hasPremiumEntitlement(customerInfo) == true else {
                    continuation.resume(returning: .failure(AppSubscriptionError(message: "No active entitlement")))
                    return
                }
                self?.updatePremiumStatus(customerInfo: customerInfo)
                continuation.resume(returning: .success(()))
            }
        }
        #else
        return .success(())
        #endif
    }

    func restorePurchases() async -> Result<Void, AppSubscriptionError> {
        #if canImport(RevenueCat)
        guard configured else { return .failure(AppSubscriptionError(message: "RevenueCat not configured")) }
        return await withCheckedContinuation { continuation in
            Purchases.shared.restorePurchases { [weak self] customerInfo, error in
                if let error {
                    continuation.resume(returning: .failure(AppSubscriptionError(message: error.localizedDescription)))
                    return
                }
                guard let customerInfo, self?.hasPremiumEntitlement(customerInfo) == true else {
                    continuation.resume(returning: .failure(AppSubscriptionError(message: "No active subscriptions")))
                    return
                }
                self?.updatePremiumStatus(customerInfo: customerInfo)
                continuation.resume(returning: .success(()))
            }
        }
        #else
        return .success(())
        #endif
    }

    private var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    #if canImport(RevenueCat)
    private func updatePremiumStatus(customerInfo: CustomerInfo) {
        isPremium = hasPremiumEntitlement(customerInfo)
        activeSubscriptionPeriod = isPremium ? resolveActiveSubscriptionPeriod(customerInfo: customerInfo) : nil
    }

    private func hasPremiumEntitlement(_ customerInfo: CustomerInfo) -> Bool {
        let entitlementIds = Set(["premium", "pro", "premium_access"])
        return customerInfo.entitlements.active.keys.contains { entitlementIds.contains($0.lowercased()) }
    }

    private func resolveActiveSubscriptionPeriod(customerInfo: CustomerInfo) -> AppSubscriptionPeriod? {
        let ids = customerInfo.activeSubscriptions.joined(separator: " ").lowercased()
        if ids.contains("annual") || ids.contains("year") { return .yearly }
        if ids.contains("month") { return .monthly }
        if ids.contains("week") { return .weekly }
        return nil
    }

    private func mapPackageToUi(_ package: Package, weeklyPrice: String?, savingsTag: String?) -> AppSubscriptionOption {
        AppSubscriptionOption(
            id: package.identifier,
            title: package.storeProduct.localizedTitle,
            price: package.storeProduct.localizedPriceString,
            description: package.storeProduct.localizedDescription,
            period: period(for: package),
            weeklyPrice: weeklyPrice,
            savingsTag: savingsTag,
            hasIntroOffer: package.storeProduct.introductoryDiscount != nil
        )
    }

    private func period(for package: Package) -> AppSubscriptionPeriod {
        switch package.packageType {
        case .annual:
            return .yearly
        case .monthly:
            return .monthly
        default:
            return .weekly
        }
    }

    private func weeklyEquivalent(for package: Package) -> String? {
        guard let price = package.storeProduct.price as Decimal? else { return nil }
        let weekly = NSDecimalNumber(decimal: price).doubleValue / 52.0
        return formatPrice(weekly, locale: package.storeProduct.priceFormatter?.locale)
    }

    private func savingsTag(weeklyPackage: Package?, yearlyPackage: Package?) -> String? {
        guard let weeklyPackage, let yearlyPackage else { return nil }
        let weeklyPrice = NSDecimalNumber(decimal: weeklyPackage.storeProduct.price).doubleValue
        let yearlyPrice = NSDecimalNumber(decimal: yearlyPackage.storeProduct.price).doubleValue
        let comparisonWeeklyCost = weeklyPackage.packageType == .monthly ? weeklyPrice / 4.345 : weeklyPrice
        guard comparisonWeeklyCost > 0 else { return nil }
        let yearlyWeeklyCost = yearlyPrice / 52.0
        let savings = ((comparisonWeeklyCost - yearlyWeeklyCost) / comparisonWeeklyCost) * 100.0
        guard savings > 0 else { return nil }
        return "SAVE \(Int(savings))%"
    }

    private func formatPrice(_ amount: Double, locale: Locale?) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale ?? .current
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }
    #endif
}

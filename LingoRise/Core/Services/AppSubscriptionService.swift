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

enum AppSubscriptionOffering {
    static let retentionExit = "retention_exit"
}

struct AppSubscriptionOption: Identifiable, Equatable {
    let id: String
    let title: String
    let price: String
    let priceAmount: Decimal?
    let description: String
    let period: AppSubscriptionPeriod
    let weeklyPrice: String?
    let savingsPercent: Int?
    let hasIntroOffer: Bool
    let introPrice: String?
    let introPriceAmount: Decimal?

    var savingsTag: String? {
        savingsPercent.map { L10n.format("paywall_save_badge_format", $0) }
    }

    var introDiscountPercent: Int? {
        guard let priceAmount, let introPriceAmount else { return nil }
        let regular = NSDecimalNumber(decimal: priceAmount).doubleValue
        let intro = NSDecimalNumber(decimal: introPriceAmount).doubleValue
        guard regular > 0, intro > 0, intro < regular else { return nil }
        let discount = ((regular - intro) / regular) * 100.0
        guard discount > 0 else { return nil }
        return max(1, Int(discount.rounded()))
    }

    static let fallbackWeekly = AppSubscriptionOption(
        id: "weekly",
        title: "Weekly",
        price: "$2.00",
        priceAmount: nil,
        description: "Billed weekly",
        period: .weekly,
        weeklyPrice: nil,
        savingsPercent: nil,
        hasIntroOffer: false,
        introPrice: nil,
        introPriceAmount: nil
    )

    static let fallbackYearly = AppSubscriptionOption(
        id: "annual",
        title: "Yearly",
        price: "$79.98",
        priceAmount: nil,
        description: "Billed yearly",
        period: .yearly,
        weeklyPrice: "$1.54",
        savingsPercent: 23,
        hasIntroOffer: false,
        introPrice: nil,
        introPriceAmount: nil
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
            #if DEBUG
            print("revenuecat_not_configured_missing_api_key")
            #endif
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

    func fetchOfferings(offeringId: String? = nil) async -> AppOfferingsResult? {
        #if canImport(RevenueCat)
        guard configured else { return nil }
        return await withCheckedContinuation { continuation in
            Purchases.shared.getOfferings { [weak self] offerings, _ in
                guard let self,
                      let offerings,
                      let current = offeringId.flatMap({ offerings.offering(identifier: $0) }) ?? offerings.current
                else {
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

                let weekly = weeklyPackage.map { self.mapPackageToUi($0, weeklyPrice: nil, savingsPercent: nil) }
                let yearlyWeeklyPrice = yearlyPackage.flatMap { self.weeklyEquivalent(for: $0) }
                let savingsPercent = self.savingsPercent(weeklyPackage: weeklyPackage, yearlyPackage: yearlyPackage)
                let yearly = yearlyPackage.map {
                    self.mapPackageToUi($0, weeklyPrice: yearlyWeeklyPrice, savingsPercent: savingsPercent)
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
        customerInfo.entitlements.active.keys.contains { $0.lowercased() == "premium" }
    }

    private func resolveActiveSubscriptionPeriod(customerInfo: CustomerInfo) -> AppSubscriptionPeriod? {
        let ids = customerInfo.activeSubscriptions.joined(separator: " ").lowercased()
        if ids.contains("annual") || ids.contains("year") { return .yearly }
        if ids.contains("month") { return .monthly }
        if ids.contains("week") { return .weekly }
        return nil
    }

    private func mapPackageToUi(_ package: Package, weeklyPrice: String?, savingsPercent: Int?) -> AppSubscriptionOption {
        AppSubscriptionOption(
            id: package.identifier,
            title: package.storeProduct.localizedTitle,
            price: package.storeProduct.localizedPriceString,
            priceAmount: package.storeProduct.price,
            description: package.storeProduct.localizedDescription,
            period: period(for: package),
            weeklyPrice: weeklyPrice,
            savingsPercent: savingsPercent,
            hasIntroOffer: package.storeProduct.introductoryDiscount != nil,
            introPrice: package.storeProduct.introductoryDiscount?.localizedPriceString,
            introPriceAmount: package.storeProduct.introductoryDiscount?.price
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

    private func savingsPercent(weeklyPackage: Package?, yearlyPackage: Package?) -> Int? {
        guard let weeklyPackage, let yearlyPackage else { return nil }
        let weeklyPrice = NSDecimalNumber(decimal: weeklyPackage.storeProduct.price).doubleValue
        let yearlyPrice = NSDecimalNumber(decimal: yearlyPackage.storeProduct.price).doubleValue
        let comparisonWeeklyCost = weeklyPackage.packageType == .monthly ? weeklyPrice / 4.345 : weeklyPrice
        guard comparisonWeeklyCost > 0 else { return nil }
        let yearlyWeeklyCost = yearlyPrice / 52.0
        let savings = ((comparisonWeeklyCost - yearlyWeeklyCost) / comparisonWeeklyCost) * 100.0
        guard savings > 0 else { return nil }
        return Int(savings)
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

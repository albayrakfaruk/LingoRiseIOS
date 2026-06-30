# iOS Store Setup

This file tracks the App Store, RevenueCat, and Firebase connections that cannot be completed until the Apple Developer account is active. The app code is already wired to these contracts.

## Apple Developer

1. Enroll in the Apple Developer Program.
2. In Certificates, Identifiers & Profiles, create or confirm the app identifier:
   - Bundle ID: `com.lingorise.learn.english.listening.reading.stories`
   - Capabilities: In-App Purchase, Push Notifications
3. Create the App Store Connect app with the same bundle ID.
4. Add the real team id in Xcode signing once the account is ready.
5. Reference docs:
   - https://developer.apple.com/programs/enroll/
   - https://developer.apple.com/help/account/

## App Store Connect Subscriptions

1. Create one auto-renewable subscription group for LingoRise Premium.
2. Create the normal products that match the RevenueCat default offering:
   - weekly premium package
   - yearly premium package
3. Create the retention yearly product or offer used by the RevenueCat `retention_exit` offering.
4. Configure localized subscription display names, descriptions, review screenshot, and pricing in every supported storefront.
5. Add Terms of Use and Privacy Policy URLs before review.
6. Finish Paid Applications Agreement, tax, and banking. StoreKit purchases will not work in production until this is complete.
7. Reference docs:
   - https://developer.apple.com/help/app-store-connect/manage-subscriptions/
   - https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions/

## RevenueCat

1. Create/select the iOS app in RevenueCat with bundle ID `com.lingorise.learn.english.listening.reading.stories`.
2. Add the App Store Connect products.
3. Entitlement IDs accepted by the app:
   - `premium`
   - `pro`
   - `premium_access`
4. Create offerings:
   - `default`: weekly and yearly packages
   - `retention_exit`: yearly package only
5. The app reads the `retention_exit` offering when the normal paywall close button is pressed. If the offering or yearly package is unavailable, the close flow falls back safely.
6. Put the iOS public SDK key into the local/CI build setting:

```sh
export LINGORISE_REVENUECAT_IOS_API_KEY="appl_xxxxxxxxxxxxxxxxx"
```

When running from Xcode's GUI, add `LINGORISE_REVENUECAT_IOS_API_KEY` as a user-defined build setting or inject it from an ignored local `.xcconfig` before archiving. Shell exports only apply to command-line builds.

The project maps this value to `RevenueCatAPIKey` in the generated Info.plist. Do not commit real RevenueCat keys to the repository.

Reference docs:

- https://www.revenuecat.com/docs/getting-started/installation/ios
- https://www.revenuecat.com/docs/getting-started/entitlements
- https://www.revenuecat.com/docs/tools/offerings

## Firebase

1. Confirm `GoogleService-Info.plist` belongs to the same bundle ID.
2. Enable Analytics, Firestore, Functions, Remote Config, Auth, and Messaging for iOS in Firebase.
3. Upload the APNs authentication key or certificates to Firebase Cloud Messaging after Apple Developer access is ready.
4. Remote Config keys used by the app:
   - `TERMS_OF_USE`
   - `PRIVACY_POLICY`
   - `COMPANY_EMAIL`
   - `ONBOARDING_MONTHLY`
   - `PRACTICE_PAYWALL_ENABLED`
5. Cloud Functions called by iOS:
   - `getContentPackage`
   - `rateContent`
   - `registerNotificationDevice`

## Review Checklist

1. Test purchases with a sandbox account.
2. Test restore purchases from Paywall and Profile.
3. Verify premium state refreshes after purchase and restore.
4. Verify `retention_exit` appears after closing the normal paywall and does not appear when products are unavailable.
5. Verify push permission, APNs token, FCM token, and `registerNotificationDevice` in Firebase logs.
6. Verify Terms, Privacy, and support email open correctly from Remote Config.
7. Archive a Release build after signing is configured.

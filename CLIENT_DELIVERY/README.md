# UnivFoods Delivery Platform — Client Handover Package

## 📦 Package Contents

This package contains the complete UnivFoods delivery platform:

---

## 📱 APKs (Ready-to-Install / Upload)

| File | Description |
|------|-------------|
| `APKs/UnivFoods_CustomerApp_V27_RELEASE.aab` | ✅ Customer App — Upload to Google Play Store |
| `APKs/UnivFoods_CustomerApp_V26_RELEASE.apk` | ✅ Customer App — Install directly on Android |
| `APKs/UnivFoods_DeliveryRiderApp_V27.apk` | ✅ Delivery Rider App — Install on rider devices |
| `APKs/UnivFoods_VendorApp_V1.0.28.apk` | ✅ Vendor App — Install on vendor/restaurant devices |

---

## 💻 Source Code

| Folder | Description |
|--------|-------------|
| `source_code/customer_app/` | Flutter source code — Customer App |
| `source_code/delivery_app/` | Flutter source code — Delivery Rider App |
| `admin_panel/` | React/Vite source code — Admin Web Dashboard |
| `landing_website/` | Landing page — univfoods.in website |
| `firebase-functions/` | Firebase Cloud Functions |

---

## 🗄️ Database SQL Scripts

Located in `database_sql/` — Run these in order in your Supabase SQL Editor:

1. `MASTER_SCHEMA_V12.sql` — Core database schema (run first)
2. `CREATE_MISSING_TABLES.sql` — Additional tables
3. `ADD_INDEXES.sql` — Performance indexes
4. `PAYMENTS_SETUP.sql` — Payment system setup
5. `STORAGE_SETUP.sql` — File storage setup
6. `ZONES_SETUP.sql` — Delivery zones
7. `SETUP_REGISTRATIONS.sql` — User registration setup
8. `SETUP_NOTIFICATIONS.sql` — Notification system
9. `LOCATION_AND_TRACKING_MASTER_V16.sql` — Location & live tracking
10. `ORDER_MANAGEMENT_MASTER.sql` — Order management
11. `REALTIME_TRACKING_SYSTEM.sql` — Realtime updates
12. `MASTER_NOTIFICATION_SYSTEM.sql` — Push notification engine
13. `FINANCIAL_LEDGER_MASTER_V17.sql` — Financial/payout system
14. `LEGAL_SETUP.sql` — Legal pages setup
15. `PROMOTIONS_MODULE.sql` — Promotions & campaigns
16. `FAST2SMS_AUTH_V1.sql` — SMS OTP authentication
17. `SEED_DATA.sql` — Initial seed data
18. `FINAL_PRODUCTION_FLOW.sql` — Final production setup

---

## ⚙️ Firebase Config

- `.firebaserc` — Firebase project config
- `firebase.json` — Firebase hosting rules
- `codemagic.yaml` — CI/CD build pipeline config

---

## 🚀 Quick Setup Guide

### Admin Panel
```bash
cd admin_panel
npm install
npm run dev     # Development
npm run build   # Production build
```

### Firebase Deploy
```bash
firebase deploy --only hosting
```

### Building Apps (requires Flutter SDK)
```bash
cd source_code/customer_app
flutter pub get
flutter build apk --release
```

---

## 🔑 Credentials Required
The following credentials need to be configured:
- **Supabase URL & Keys** — In each app's config file
- **Google Maps API Key** — In Android manifest files
- **Firebase Project** — Firebase console credentials
- **Fast2SMS API Key** — For OTP authentication

---

*UnivFoods Platform — Delivered by Ganaparthi Manish*

# Platform Handover & End-to-End Documentation

Welcome! This document provides all the necessary details to take over, run, build, and deploy the **Curry Delivery Platform (UNIV Foods)**. 

The platform consists of **three mobile apps (Flutter)**, a **React/Vite Admin Panel**, a **Static Landing Website**, a **Supabase Backend Database**, and **Firebase Cloud Functions** for Push Notifications.

---

## 🔑 1. Credentials, API Keys & Environments

All keys are currently configured in the code files. Below is the master list of all credentials and keys used across the platform.

### A. Supabase (Backend Database & Auth)
Supabase handles user profiles, product catalogs, vendor details, orders, real-time live location tracking, and wallets.
*   **Supabase URL:** `https://dxqcruvarqgnscenixzf.supabase.co`
*   **Public Anon Key (Client SDKs):**
    ```text
    eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgwMjQ2NzksImV4cCI6MjA4MzYwMDY3OX0.2Z_DubJZM0p_aIC_1-H_LuZIrf8twPxqLbURw3rrHxY
    ```
*   **Service Role Key (Bypasses RLS - Admin Panel & Firebase Functions only):**
    ```text
    eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s
    ```
*   **Database Project ID:** `dxqcruvarqgnscenixzf`

### B. Google Maps API Key
Used for address geocoding, autocomplete search, and live route tracking maps in the mobile apps and admin panel.
*   **API Key:** `AIzaSyAqpif-LqTA5KczhJtkKzG8RXK8lrhMyJQ`

### C. Firebase Configurations
We use two different Firebase project setups:
1.  **Mobile Apps & Domain Hosting:** `univfoods-967a6` (FCM push notifications, SMS Phone OTP, and custom domains hosting).
    *   **Project Number:** `1014515818898`
    *   **Customer App ID (`com.univfoods.curry`):** `1:1014515818898:android:4209a4d8097423d0d7614b`
    *   **Delivery App ID (`com.univfoods.rider`):** `1:1014515818898:android:3d28f8d28ed28ed28ed28e`
    *   **Vendor App ID (`com.univfoods.vendor`):** `1:1014515818898:android:3d28f8d28ed28ed28ed28e`
2.  **Admin Panel Web Config:** `curypoint-f0274` (Firestore, Storage, Auth SDK)
    *   **Web API Key:** `AIzaSyDt6W42XHG09_e2PpOH5loSxkjRY43EhQY`
    *   **Auth Domain:** `curypoint-f0274.firebaseapp.com`
    *   **Project ID:** `curypoint-f0274`
    *   **Storage Bucket:** `curypoint-f0274.firebasestorage.app`
    *   **Messaging Sender ID:** `106238487896`
    *   **App ID:** `1:106238487896:web:16434b08e4b8c2b3a4092d`

### D. Keystore Signing Credentials (Android Apps)
All three Flutter apps share the same keystore password details for building release bundles (`AAB` and `APK` files).
*   **Keystore File:** `upload-keystore.jks` (located inside `android/app/` of each app)
*   **Store Password:** `univfoods123`
*   **Key Password:** `univfoods123`
*   **Key Alias:** `upload`
*   **Config file path:** `android/key.properties` (within each Flutter app folder)

---

## 📁 2. Project Directory Structure

```text
curry-delivery-platform/
├── customer_app/        # Flutter App for Customers (Ordering, Cart, Wallet, Live Tracking)
├── delivery_app/        # Flutter App for Riders (Accepting Orders, GPS Tracking, Earnings)
├── vendor_app/          # Flutter App for Stores (Accept Menu Items, Update Order Statuses)
├── admin-panel/         # React + Vite Web App (Dashboard for Orders, Riders, Payouts, Zones)
├── landing_website/     # Static Landing Website (HTML/CSS) for Customer App downloads
├── firebase-functions/  # Firebase Cloud Functions (order status webhooks calling FCM)
├── firebase.json        # Firebase Multi-Site hosting configuration
├── .firebaserc          # Firebase deployment project mappings
└── *.sql                # Database migration scripts and emergency database fix files
```

---

## 💻 3. Local Setup Instructions

Ensure you have **Flutter SDK (stable)** and **Node.js (v18+)** installed globally.

### A. React Admin Panel
1.  Navigate to the directory:
    ```bash
    cd admin-panel
    ```
2.  Install dependencies:
    ```bash
    npm install
    ```
3.  Run the local development server:
    ```bash
    npm run dev
    ```
    *(The site will be hosted at `http://localhost:5173`)*
4.  Build for production:
    ```bash
    npm run build
    ```
    *(Generates a build output directory at `admin-panel/dist`)*

### B. Flutter Apps (Customer, Delivery, Vendor)
Run the following commands for **each** app directory (`customer_app`, `delivery_app`, `vendor_app`):
1.  Navigate into the app folder (e.g. customer_app):
    ```bash
    cd customer_app
    ```
2.  Download pub dependencies:
    ```bash
    flutter pub get
    ```
3.  Run the app on a connected emulator or real Android/iOS device:
    ```bash
    flutter run
    ```
4.  Compile a release build:
    ```bash
    flutter build apk --release    # Generates APK
    flutter build appbundle --release # Generates AAB for Google Play Console
    ```

### C. Firebase Cloud Functions
These functions act as database webhooks that listen to order status modifications in Supabase and send push notifications to clients via FCM.
1.  Navigate to functions directory:
    ```bash
    cd firebase-functions/functions
    ```
2.  Install dependencies:
    ```bash
    npm install
    ```
3.  Run firebase emulator locally (optional):
    ```bash
    firebase emulators:start
    ```

### D. Landing Website
The website is static. You can run it locally using any basic HTTP server:
```bash
cd landing_website
# Using Python
python -m http.server 8000
# Or using Node
npx serve .
```

---

## 🚀 4. Deployment Setup

The static landing website and the Admin Panel are deployed directly to **Firebase Hosting** using a multi-site configuration.

### A. Deploying Landing Web & Admin Panel to Firebase
1.  First, make sure the React Admin Panel is built:
    ```bash
    cd admin-panel
    npm run build
    cd ..
    ```
2.  Log in to the Firebase client account (needs permission to `univfoods-967a6`):
    ```bash
    firebase login
    ```
3.  Ensure the default deployment project is set:
    ```bash
    firebase use default
    ```
4.  Apply hosting targets (if not already applied):
    ```bash
    firebase target:apply hosting univfoods univfoods-967a6
    firebase target:apply hosting univfoods-admin univfoods-admin-panel-3970d
    ```
5.  Deploy both sites simultaneously:
    ```bash
    firebase deploy --only hosting
    ```
    *   **Landing Website** deploys from `landing_website/` to `https://univfoods-967a6.web.app` (custom domain `univfoods.in`).
    *   **Admin Panel** deploys from `admin-panel/dist/` to `https://univfoods-admin-panel-3970d.web.app` (custom domain `admin.univfoods.in`).

### B. Connecting Custom Domains
*   **Main Site (`univfoods.in`):** Go to Firebase Console → Hosting → Click **Add Custom Domain** on the `univfoods` target and map it to `univfoods.in`. Add the A/TXT records provided to your DNS provider (e.g. GoDaddy).
*   **Admin Site (`admin.univfoods.in`):** Switch targets in the Firebase Console Hosting dropdown to `univfoods-admin`, add the custom domain `admin.univfoods.in`, and configure your DNS settings.

### C. Deploying Firebase Cloud Functions
1.  Deploy the order status change FCM notification webhook:
    ```bash
    firebase deploy --only functions
    ```
2.  Set up the database webhook in your Supabase Dashboard:
    *   Go to **Supabase Dashboard** → **Database** → **Webhooks**.
    *   Create a webhook on the `orders` table for `INSERT` and `UPDATE` events.
    *   Set the target URL to the deployed Firebase Function URL:
        `https://us-central1-univfoods-967a6.cloudfunctions.net/onOrderStatusChange`
    *   This ensures that any database status update triggers an FCM push notification.

### D. Alternative Admin Deployment (Netlify)
If you prefer deploying the Admin Panel on Netlify:
1.  Build the React project (`npm run build`).
2.  Go to [app.netlify.com](https://app.netlify.com).
3.  Drag and drop the folder `admin-panel/dist` to deploy.
4.  Under Site Settings → Domain Management, add `admin.univfoods.in`.
5.  Add a **CNAME** record to your DNS registry: Host `admin` pointing to your Netlify site URL (e.g., `your-site.netlify.app`).

---

## 🗄️ 5. Database Schema & Setup

The database runs on Supabase (PostgreSQL with PostGIS enabled).

### Core Tables
*   `public.vendors`: Contains name, coordinates, address, status, ratings, manager info, and `owner_id` linking to Supabase auth users.
*   `public.products`: Stores menu items linked to vendors, prices, availability, categories, and images.
*   `public.orders`: Customer orders, JSON snapshots of cart items (`items` jsonb), vendor references, total costs, status, and delivery coordinates.
*   `public.delivery_riders`: Active delivery partners, vehicles, online status, ratings, and current coordinates (`latitude`, `longitude`).
*   `public.customer_profiles`: Holds user profiles (phone, email, full_name) linked to `auth.users(id)` via an automated triggers database pipeline.
*   `public.app_settings`: Key-value store for app configs (delivery fees, tax rates).
*   `public.order_live_tracking`: Realtime rider location updates.
*   `public.notifications`: Stores notification logs (orders, payments, system messages).

### Initialization Script
If setting up a new Supabase database, copy and run the SQL schema defined in [supabase_schema.sql](file:///c:/Users/ganap/.gemini/antigravity/scratch/curry-delivery-platform/supabase_schema.sql) and [COMPLETE_DB_SETUP.sql](file:///c:/Users/ganap/.gemini/antigravity/scratch/curry-delivery-platform/COMPLETE_DB_SETUP.sql) inside the Supabase SQL editor.

Make sure to run **`COMPLETE_REALTIME_FIX_ALL_APPS.sql`** and **`MASTER_NOTIFICATION_SYSTEM.sql`** to enable real-time replication and notification triggers, which are critical for the mobile apps to sync properly.

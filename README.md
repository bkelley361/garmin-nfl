# NFL Live Scoreboard & Alert Widget for Garmin Venu 2 Plus

A complete, production-ready Garmin Connect IQ widget and serverless proxy for tracking live NFL scores on Garmin watches (specifically tailored for the **Garmin Venu 2 Plus**).

---

## Architecture Overview

```
                      ┌────────────────────────────────────────┐
                      │           ESPN Public API              │
                      │  Raw Scoreboard JSON (~150 KB)         │
                      └──────────────────┬─────────────────────┘
                                         │
                                         ▼
                      ┌────────────────────────────────────────┐
                      │    Cloudflare Worker Proxy (proxy/)    │
                      │  Trims & caches scores to ~1 KB        │
                      └──────────────────┬─────────────────────┘
                                         │  HTTPS
                                         ▼
                      ┌────────────────────────────────────────┐
                      │         Garmin Connect IQ Widget       │
                      │               (NFLTracker/)            │
                      ├──────────────────┬─────────────────────┤
                      │  Glance View     │  Main Screen View   │
                      │  Compact score   │  Full game carousel │
                      │  in watch loop   │  Swipe / Up & Down  │
                      ├──────────────────┴─────────────────────┤
                      │          Background Service            │
                      │  5-minute temporal polling & alert     │
                      │  vibrates & wakes watch on score chg   │
                      └────────────────────────────────────────┘
```

---

## Project Structure

```
.
├── plan.md                                # Original project architectural blueprint
├── README.md                              # Main guide and instructions
├── proxy/                                 # Serverless Cloudflare Worker proxy
│   ├── worker.js                          # ESPN parser, filter, and trimmer
│   ├── wrangler.toml                      # Cloudflare Worker configuration
│   ├── package.json                       # Dependencies & deploy scripts
│   └── test-proxy.js                      # Verification script testing real ESPN API
└── NFLTracker/                            # Connect IQ Widget Project
    ├── manifest.xml                       # Target: venu2plus, Permissions: Comm & Background
    ├── monkey.jungle                      # Monkey C jungle build configuration
    ├── .vscode/                           # VS Code project settings & launch configs
    │   ├── settings.json
    │   └── launch.json
    ├── resources/
    │   ├── strings/
    │   │   └── strings.xml                # AppName string resource
    │   └── drawables/
    │       ├── drawables.xml              # Bitmap launcher icon definition
    │       └── launcher_icon.png          # App launcher icon
    ├── source/
    │   ├── NFLTrackerApp.mc               # App lifecycle, glance/main/background coordinator
    │   ├── NFLGlanceView.mc               # Compact widget preview for glance carousel
    │   ├── NFLMainView.mc                 # Full-screen 416x416 scoreboard & input delegate
    │   └── NFLBackgroundService.mc        # 5-minute background sync & score change alerter
    └── bin/
        └── NFLTracker.prg                 # Compiled binary signed with developer key
```

---

## Quick Start Guide

### Step 1: Deploy the Cloudflare Worker Proxy

1. Open a terminal in `proxy/`:
   ```bash
   cd proxy
   ```
2. Test the proxy locally against real live ESPN data:
   ```bash
   npm test
   ```
   *(You will see parsed game payloads and size metrics: ~1.5 KB for all 14 games vs ~129 bytes for a single team).*
3. Deploy to Cloudflare:
   ```bash
   npm run deploy
   ```
   *Note: If not already logged into Cloudflare, `wrangler` will prompt you to authenticate via your browser. Once deployed, Cloudflare will print your worker URL (e.g., `https://nfl-proxy.<your-subdomain>.workers.dev`).*
4. Copy your deployed worker URL into `NFLTracker/source/NFLTrackerApp.mc`:
   ```monkeyc
   public static const PROXY_URL = "https://nfl-proxy.<your-subdomain>.workers.dev";
   ```

---

### Step 2: Scaling to 10,000+ Users on Cloudflare Free Tier (Method 1)

By default, Cloudflare provides **100,000 free Worker requests per day**. With 10,000 active users polling every 5 minutes on an NFL Sunday, that generates ~800,000 requests. 

You can serve all 10,000+ users **100% free** by routing through a custom domain on Cloudflare:

#### Why this works:
* On the default `*.workers.dev` domain, Cloudflare counts *every* incoming request as a Worker execution before evaluating cache.
* On a **Custom Domain** proxied through Cloudflare (orange-clouded CDN), **Cloudflare's CDN Edge Cache intercepts requests BEFORE invoking the Worker**.
* The proxy code already includes the caching headers:
  ```javascript
  "Cache-Control": "public, max-age=30, s-maxage=30"
  ```
* Cloudflare CDN edge hits are **100% free with UNLIMITED bandwidth/requests**.
* The Worker only executes **once every 30 seconds** across the entire world to refresh ESPN data.
* **Total Worker calls per day: ~2,880** (only **2.8%** of your 100,000 free daily quota!).

#### How to configure it:
1. In the Cloudflare Dashboard, open **Workers & Pages** -> **`nfl-proxy`**.
2. Go to **Settings** -> **Domains & Routes** -> click **Add Custom Domain**.
3. Enter your domain or subdomain (e.g. `nfl.yourdomain.com`).
4. Update `NFLTracker/source/NFLTrackerApp.mc`:
   ```monkeyc
   public static const PROXY_URL = "https://nfl.yourdomain.com";
   ```
5. *(Optional)* In Cloudflare **Caching** -> **Cache Rules**, create a rule for `nfl.yourdomain.com/*` with **Edge TTL: 30 seconds**.

---

### Step 3: Garmin SDK & Device Setup (Venu 2 Plus)

The local environment has already been pre-configured:
- **Java 17 (OpenJDK)** is installed and linked.
- **Connect IQ SDK 9.3.0** is installed at `/opt/homebrew/Caskroom/connectiq/`.
- **Garmin Monkey C VS Code extension** is installed.
- **Developer Key** is generated and saved at `~/.Garmin/developer_key.der`.

To download the **Venu 2 Plus** simulator profile for local emulation:
1. Open the Connect IQ SDK Manager:
   ```bash
   open /Applications/SdkManager.app
   ```
2. Log into your Garmin developer account.
3. In the **Devices** tab, search for **Venu 2 Plus** and click **Download**.

---

### Step 4: Run in the Connect IQ Simulator

1. Open this repository in Visual Studio Code:
   ```bash
   code .
   ```
2. Open `NFLTracker/source/NFLTrackerApp.mc`.
3. Press **F5** (or go to **Run and Debug** -> **Run NFLTracker on Venu 2 Plus**).
4. The Connect IQ Simulator will launch displaying the Venu 2 Plus 416x416 AMOLED screen!
5. In the simulator menu:
   - Select **Simulation > Background Events** to trigger background sync immediately.
   - Tap or swipe up/down to navigate between games.

---

### Step 5: Sideload onto your Physical Garmin Watch (macOS)

Follow these steps to copy the widget directly to your **Garmin Venu 2 Plus** (or any compatible watch):

#### 1. Install an MTP File Transfer Utility
> [!NOTE]
> **Why this is required on macOS:**  
> The Venu 2 Plus (and all music-capable Garmin watches) connects to macOS using **MTP (Media Transfer Protocol)**. macOS Finder cannot mount MTP devices as external drives natively.

Install **OpenMTP** (free and open source):
```bash
brew install --cask openmtp
```
*(Or download directly from [openmtp.ganeshrvel.com](https://openmtp.ganeshrvel.com/)).*

#### 2. Copy the App File
1. Connect your Garmin watch to your Mac using the USB charging cable.
2. If **Garmin Express** is running in your Mac menu bar, **quit Garmin Express** (it locks the USB port).
3. Open **OpenMTP**:
   * The **left panel** shows your Mac.
   * The **right panel** shows your Garmin watch storage.
4. On the watch pane, navigate to:
   ```text
   GARMIN / APPS /
   ```
5. Drag and drop **`bin/NFLTracker.prg`** from your project directory into the **`GARMIN/APPS/`** folder.
6. Safely unplug your watch.

#### 3. Launch on Watch
* Swipe up or down through your watch's **Glance carousel**.
* You will see the **NFL Tracker** glance!
* Tap into it to browse live games, scoring plays, and turnover updates.

---

### Step 6: Publishing to the Garmin Connect IQ Store

To publish the app for anyone to download from the official Garmin Connect IQ Store:

#### 1. Build the Production App Bundle (`.iq` file)
The Connect IQ Store requires an `.iq` export package that bundles signed binaries for all supported devices.

Run the export build command from the workspace root:
```bash
monkeyc -e -f monkey.jungle -o bin/NFLTracker.iq -y ~/.Garmin/developer_key.der
```
*(Alternatively, in VS Code press `Cmd+Shift+P` -> select `Monkey C: Export Project` -> choose your output directory).*

This creates **`bin/NFLTracker.iq`** (packages all 54 devices configured in `manifest.xml`).

#### 2. Upload to the Developer Dashboard
1. Go to the [Garmin Connect IQ Developer Dashboard](https://apps.garmin.com/developer/dashboard) and sign in.
2. Click **Upload a New App**.
3. Select your generated **`bin/NFLTracker.iq`** file.
4. The dashboard will automatically read your `manifest.xml` and detect the 35+ supported watch models.

#### 3. Store Listing Details
* **Title:** NFL Live Scoreboard & Alerts
* **Category:** Sports
* **Payment Type:** Select **"Paid / Requires Payment"** (or "Payment with Free Trial").
* **Payment Description:** In the listing description, add:
  ```text
  $4.99 one-time unlock for full live scores & wrist alerts!
  100% Free during the offseason (March - July).
  Powered by KiezelPay (kzl.io).
  ```
* **Permissions Justification:** 
  * *Communications:* Fetches live ESPN scoreboard data and verifies KiezelPay licenses.
  * *Background Execution:* Wakes watch every 5 minutes during live games to send score and turnover alerts.
* **Screenshots:** Take screenshots from the Connect IQ Simulator (`Ctrl+S` or `Cmd+S` in simulator) and upload them.

#### 4. Approval Process
* Garmin's review team checks new app submissions for crashes and guideline compliance.
* Approval typically takes **24 to 48 hours**. Once approved, your widget goes live globally on the Connect IQ mobile app!

---

## Key Features

### 🏈 Live Alerts: Who Scored & Turnovers
* **Who Scored:** Touchdowns and field goals include player names and play descriptions (e.g., `Stefon Diggs 32 Yd pass from Jayden Daniels`, `Matt Gay 43 Yd Field Goal`).
* **Turnovers:** Interceptions and fumble recoveries buzz your wrist with who was picked off and who recovered it (e.g., `C.Beck INT by W.Bailey`, `Fumble rec by SF-M`).
* **Screen Anti-Clipping:** Uses dynamic text measurement (`fitText`) so play descriptions are never cut off by the curved glass edges of the Venu 2 Plus circular screen.

### 🔋 Smart Adaptive Battery Scheduling
The proxy calculates intelligent wake-up directives sent to the watch to maximize battery life:
* **Live Games:** Polled every **5 minutes** (Garmin's platform minimum for background events).
* **Game Day (Before Kickoff):** Sleeps until **1 minute after kickoff**.
* **Non-Game Days:** Checks only once every **24 hours**.
* **Offseason:** Checks only once every **3 days**.

---

## KiezelPay Monetization ($4.99 One-Time)

The app includes built-in seasonal access management via **[KiezelPay](https://kiezelpay.com/)** (`NFLTracker/source/NFLPayManager.mc`).

### 1. Seasonal Rule
* **August 1 – February 28/29 (NFL Season):** Requires an active KiezelPay unlock ($4.99 one-time). Unlicensed users see the activation card on their watch (`Visit kzl.io/code, enter Code: XXXXX`).
* **March 1 – July 31 (Offseason):** Automatically bypasses the paywall and runs **100% free** for all users.

### 2. When you create your KiezelPay Developer Account:
1. Register at [kiezelpay.com](https://kiezelpay.com/).
2. Create a new product (e.g. "NFL Scoreboard & Alerts") for Garmin.
3. Set your pricing: **$4.99** (one-time purchase).
4. Copy your numeric **Product ID**.
5. Open `NFLTracker/source/NFLPayManager.mc`:
   ```monkeyc
   public static const KIEZELPAY_APP_ID = "YOUR_KIEZELPAY_PRODUCT_ID";
   public static const DEMO_MODE = false;
   ```
6. Rebuild the app with `monkeyc` or VS Code. Demo mode is currently enabled by default so you can continue testing without interruption.

### 3. Friends & Family 100% Discount Codes
You can easily give friends and family free access directly through KiezelPay:
1. In your **KiezelPay Developer Dashboard**, go to **Discounts / Promos** -> **Create Discount**.
2. Set the discount to **100%**.
3. Create a code name (e.g. `FAMILY` or `VIP`).
4. When your friend visits `kzl.io/code` to enter their watch code, they click **"Have a coupon code?"**, enter `FAMILY`, and checkout completes for **$0.00**. Their watch unlocks immediately without charging them.

# Project Proposal: HarmonyOS Travel Diary App

## Part I. Preliminary Requirements Analysis

### Project Overview

**TravelPin** is a location-based travel diary application.

Users can pin photos and captions precisely to map coordinates, generate dynamic travel clips with one click, and leverage AI to intelligently generate social media copy in various styles. The system leverages Huawei Cloud Space and Huawei Account ecosystem to enable distributed data management across devices under the same account. It prioritizes an "offline-first" approach, enabling smooth recording even without a network connection. Meanwhile, through local privacy cleansing and encrypted signature sharing, the system comprehensively ensures user privacy and data security.

### 1. Functional Requirements

This system includes the following 5 orthogonal functional features:

**Interactive Map:**
* Pin photos, text stories, and mood tags to a real map as "memory nodes".
* Browse and filter nodes by time range, geographic area, or custom tags.
* Prevent lag when nodes are dense; support cluster rendering, and allow users to click on clusters to expand and view the details of each item.

**Dynamic Journey Playback:**
* Select and combine memory nodes into a travel route.
* Generate a travel clip full of memories with one click.

**Cross-Platform Route Sharing:**
* Generate an encrypted, signed, and time-limited shareable link for any route.
* Support direct sharing to WeChat or copying to the system clipboard.
* Receivers can view the complete journey without installing the App.

**AI-Assisted Copywriting:**
* Users can input simple drafts, and the system will generate social media copy combined with journey meta-information.
* Support users in selecting tone styles (e.g., poetic, concise, humorous).

**Seamless Multi-Device Sync:**
* Support one-click authorization login with Huawei Account.
* Memory nodes, routes, and drafts are automatically synced across phones, tablets, and computers via Huawei Cloud Space.
* Record easily on the phone and continue editing on a large computer screen.

### 2. Non-Functional Requirements

**Usability**
* **Interaction Efficiency:** Core operations (add/delete/modify nodes, create routes) should be completed within a few clicks on the main page.
* **Learning Curve:** System interface design and interaction operations must remain simple to help users get started quickly.
* **Status Feedback:** The interface must provide clear and non-blocking visual or haptic feedback for all background actions to avoid user confusion about the system status.
* **Accessibility & Adaptability:** The system supports dynamic font scaling to serve users of different age groups.

**Performance**
* **Map Rendering:** Dynamically cluster and selectively render nodes and routes to ensure smooth rendering even in scenarios with many data points.
* **AI Response Time:** LLM copywriting requests should output the first token (TTFB) in a very short time and adopt streaming to maintain a sense of instantaneous interaction.
* **App Startup:** On standard HarmonyOS devices, a cold start to an interactive map page should be completed within a very short time.

**Security & Privacy**
* **Data Classification Protection:** Follow HarmonyOS data classification standards to label user data by sensitivity. High-sensitivity data (e.g., geographic locations, identity credentials) adopts higher-level encrypted storage and access control, ensuring data receives protection matching its risk level when flowing across devices.
* **Secure Sharing:** Share links adopt server-side signature mechanism with time limits and tamper-proof verification; receivers must pass identity verification before accessing content to prevent unauthorized dissemination.
* **AI Content Compliance:** All AI-generated copy must pass content security filtering before being displayed or stored, ensuring compliance with laws, regulations, and platform norms.

**Reliability & Availability**
* **Offline-First:** In completely network-free environments, the application can still normally use basic functions (e.g., creating nodes, editing drafts, browsing history); local data adopts device-level encrypted storage to prevent data theft when devices are lost.
* **Data Recovery:** Provide a fault-tolerance mechanism allowing users to recover data within a set period after deletion; secure erasure is performed on permanent deletion to ensure data cannot be recovered through technical means.
* **Distributed Sync:** Support trusted sync across devices under the same Huawei Account; sync channels adopt end-to-end encryption to ensure cross-device data transmission security.

### 3. Technical Requirements

The system's operating environment, development toolchain, and runtime stack are defined as follows:

* **Client / Front-End (HarmonyOS App):**
    * **Language & UI Framework:** ArkTS with ArkUI declarative UI for native component rendering.
    * **Location Services:** System-level location security control to obtain location information when users actively trigger, ensuring transparent and controllable permission use.
    * **Media Access:** System-level Photo Picker mechanism, adhering to the principle of least privilege — the app does not need full album access permission to select photos.
    * **Local Persistence:** HarmonyOS hierarchical encrypted storage scheme; sensitive data (e.g., user credentials) stored in Trusted Execution Environment (TEE), ordinary data stored in Relational Database (RDB) with device-bound encryption.

* **Back-End & Cloud (Huawei Cloud Services):**
    * **User Authentication:** Integrate Huawei Account authentication service with two-factor authentication support to ensure account security.
    * **Data Sync:** Leverage Huawei Cloud Space distributed data management capabilities to achieve automatic sync across devices under the same account; sync channels are end-to-end encrypted, and the cloud cannot decrypt user data.
    * **Media Storage:** Photos and videos are stored in user's Huawei Cloud Space; the app accesses through authorization, with encryption protection during transmission and storage.
    * **Web Sharing Portal:** A lightweight, read-only web application where shared travel routes require signature verification and validity period check before access.

* **AI & Computing Services:**
    * **Local Edge AI:** Leverage HarmonyOS system-level vision capabilities to perform basic image processing on-device (e.g., scene classification, label generation) — only metadata is extracted, original photos never leave the device. Complex AI tasks (e.g., copywriting) are handled by cloud LLM, receiving only desensitized text metadata.
    * **Cloud LLM:** Remote Large Language Model accessed via AI Gateway for copy generation and content compliance moderation; only desensitized journey metadata is sent to the cloud, excluding original photos and user identity information.

* **Development & Delivery Environment:**
    * **IDE:** DevEco Studio (HarmonyOS official IDE) for front-end development.
    * **Version Control:** Git + GitHub; branch-based workflow with pull request reviews.
    * **Project Management:** GitHub Projects board for sprint planning and progress tracking.
    * **CI/CD:** GitHub Actions for automated linting, testing, and build verification on each PR.
    * **Testing:** Unit tests for core logic modules; integration tests for sync and API layers.

### 4. Data Requirements

* **What data is needed:**
    * **Geospatial Data:** Real-time GPS coordinates (latitude, longitude), movement trajectory points, altitude, heading, and timestamps — forming the backbone of all map and route features.
    * **Media & Content Data:** User-selected photos and videos (accessed via Photo Picker), manually entered text drafts, mood tags, and trip metadata (name, date range, cover image).
    * **AI Context Data:** Journey metadata aggregated from memory nodes — visited POI names (via reverse geocoding), total distance, trip duration, and user-provided draft text — used as input for caption generation. No photos are sent to the cloud LLM.
    * **User & Sync Data:** Huawei Account identifier, device identifiers, data sync status, and conflict resolution logs.

* **How to acquire the data:**
    * **Location:** Acquired through system-level location security control after explicit user authorization; continuous tracking is only active during trip recording sessions.
    * **Media:** Accessed through the system-level Photo Picker, adhering to the principle of least privilege — the app never requests full album access.
    * **POI & Geocoding:** Reverse geocoding via map service APIs to resolve coordinates into human-readable place names.
    * **AI Inputs:** Journey metadata (POI list, distance, duration) is aggregated locally and sent as structured text to the cloud LLM gateway; user draft text is optional additional input.

* **Data processing & storage strategy:**
    * **Privacy Protection:** Before sharing photos, sensitive metadata (e.g., precise location, device information) is removed locally to ensure distributed content does not contain user privacy. AI copywriting uses only scene labels extracted locally, original photos never need to be uploaded.
    * **Hierarchical Storage:** Different encryption levels are adopted based on data sensitivity — high-sensitivity data (e.g., identity credentials) uses device lock screen password-bound encryption, ordinary data uses device-level encryption.
    * **Hot / Cold Tiering:** Active trip data is written at high frequency to local encrypted storage (hot); historical data is asynchronously synced to Huawei Cloud Space during network idle periods, with end-to-end encryption during sync.
    * **Data Lifecycle:** Users can permanently delete any node or trip, triggering cascading deletion and secure erasure from local and cloud storage; shared links automatically expire and become unrecoverable after the validity period.

# Project Proposal: HarmonyOS Travel Diary App

## Part I. Preliminary Requirements Analysis

### Project Overview

**TravelPin** is a location-based travel diary application.

Users can pin photos and captions precisely to map coordinates, generate dynamic travel clips with one click, and leverage AI to intelligently generate social media copy in various styles.
The system adopts a three-tier architecture comprising a local frontend, server backend, and remote cloud. It prioritizes an "offline-first" approach, enabling smooth recording even without a network connection. Meanwhile, through mandatory metadata stripping and encrypted signature sharing, the system comprehensively ensures user privacy and data security.

### 1. Functional Requirements

This system includes the following 5 orthogonal functional features:

**Interactive Map:** * Pin photos, text stories, and mood tags to a real map as "memory nodes".
* Browse and filter nodes by time range, geographic area, or custom tags.
* Prevent lag when nodes are dense; support cluster rendering, and allow users to click on clusters to expand and view the details of each item.

**Dynamic Journey Playback:**
* Select and combine memory nodes into a travel route.
* Generate a travel clip full of memories with one click.

**Cross-Platform Route Sharing:** * Generate an encrypted, signed, and time-limited URL for any route.
* Support direct sharing to WeChat or copying to the system clipboard.
* Receivers can view the complete journey without installing the App.

**AI-Assisted Copywriting:**
* Users can input simple drafts, and the system will generate social media copy combined with journey meta-information.
* Support users in selecting tone styles (e.g., poetic, concise, humorous).

**Seamless Multi-Device Sync:**
* Support one-click authorization login with a Huawei account.
* Sync memory nodes, routes, and drafts across phones, tablets, and computers.
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
* **Mandatory Metadata Stripping:** All privacy data (e.g., device models, coordinates, timestamps) must be forcibly stripped at the local layer prior to any sync or share operations.
* **Secure Sharing:** Share links must be signed using HMAC-SHA256 and include a TTL expiration time; the use of guessable sequential IDs is prohibited.
* **AI Content Compliance:** All AI-generated copy must pass through a content moderation filter before being displayed to the user or persistently stored.

**Reliability & Availability**
* **Offline-First:** In completely network-free environments, the application can still normally use basic functions (e.g., creating nodes, editing drafts, browsing history); the system must use local storage as the primary data source.
* **Data Recovery:** Provide a fault-tolerance mechanism, allowing users to recover data within a set period of time after deletion.

### 3. Technical Requirements

The system's operating environment, development toolchain, and runtime stack are defined as follows:

* **Client / Front-End (HarmonyOS App):**
    * **Language & UI Framework:** ArkTS with ArkUI declarative UI for native component rendering.
    * **Location Services:** HarmonyOS `LocationHub` API for high-precision, low-power GPS coordinate acquisition and continuous tracking.
    * **Media Access:** HarmonyOS system-level Photo Picker (minimal permission model — no full album access required).
    * **Local Persistence:** HarmonyOS Relational Database (RDB) for structured data; local file system for media and cache.
* **Back-End & Cloud (Distributed Services):**
    * **Sync Server:** A distributed sync service implementing eventual consistency via versioned update queues for multi-device conflict resolution.
    * **Spatial Database:** PostgreSQL with PostGIS extension for efficient spatial indexing, clustering queries, and geofencing over large-scale geographic data.
    * **Object Storage:** Cloud OSS (Object Storage Service) for centralized media hosting and thumbnail distribution via CDN.
    * **Web Sharing Portal:** A lightweight, read-only web application for rendering shared travel routes accessible from any browser.
* **AI & Computing Services:**
    * **Local Edge AI:** On-device lightweight ML models for OCR and text vectorization — supports local search and indexing while protecting privacy.
    * **Cloud LLM:** Remote Large Language Model accessed via an AI Gateway for text-to-text caption generation (from journey metadata to styled copy) and content compliance moderation.
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
    * **User & Sync Data:** User profile, device identifiers, sync version vectors, and conflict resolution logs.
* **How to acquire the data:**
    * **Location:** Acquired exclusively via HarmonyOS `LocationHub` API after explicit user authorization; continuous tracking is only active during trip recording sessions.
    * **Media:** Accessed through the system-level Photo Picker, adhering to the principle of least privilege — the app never requests full album access.
    * **POI & Geocoding:** Reverse geocoding via map service APIs to resolve coordinates into human-readable place names.
    * **AI Inputs:** Journey metadata (POI list, distance, duration) is aggregated locally and sent as structured text to the cloud LLM gateway; user draft text is optional additional input.
* **Data processing & storage strategy:**
    * **Privacy Cleansing:** All media undergo mandatory EXIF metadata stripping locally before leaving the device.
    * **Hot / Cold Tiering:** Active trip data is written at high frequency to local RDB (hot); historical and archived trips are asynchronously pushed to cloud PostGIS and OSS during network idle periods (cold).
    * **Retention:** Users can permanently delete any node or trip, triggering cascading removal from local storage, cloud database, and object storage. Shared link data expires automatically after TTL.

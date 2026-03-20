# Project Proposal: HarmonyOS Location-Based Travel Journal App

## Part I. Preliminary Requirement Analysis

### Project Overview

**TravelPin** is a HarmonyOS-native location-based travel journal application. It allows users to pin photos and memories to precise geographic coordinates, replay animated travel routes, and share journeys to social platforms with AI-generated captions. 

The system adopts an offline-first, three-tier architecture (Client, Local Backend, Cloud) to ensure a seamless experience even without network connectivity, while prioritizing user privacy through mandatory metadata stripping and end-to-end security controls.

### 1. Functional Requirements

The proposed system includes the following 5 distinct and orthogonal features:

* **Interactive Spatiotemporal Map:** A personalized, location-anchored life journal built on a world map.
    * Pin photos, text stories, and mood tags to exact GPS coordinates as "memory nodes."
    * Browse and filter nodes by time range, location region, or custom tags.
    * Support cluster rendering when nodes are dense; tap a cluster to expand individual entries.
* **Dynamic Journey Replay:** Cinematic animated playback of archived travel routes.
    * Select and group memory nodes into a named trip; the system auto-generates a continuous trajectory.
    * Play, pause, and scrub through the route with smooth map-camera animations.
    * Overlay timestamped photos and notes along the timeline during playback.
* **Cross-Platform Route Sharing:** One-click generation of shareable web links for travel routes.
    * Generate a cryptographically signed, time-limited URL (HMAC-SHA256 + TTL) for any route.
    * Share the link directly to WeChat, Weibo, or system clipboard.
    * Recipients view the full journey on a read-only web page — no app installation required; support commenting and reactions.
* **AI-Assisted Route Sharing Copywriting:** Seamlessly integrated with the cross-platform sharing feature, this tool helps users overcome writer's block when sharing journeys.
    * Users can input a simple draft or let the system use the journey's metadata (visited POIs, total distance, duration) as context.
    * The built-in cloud LLM transforms basic context into polished social media captions in user-selected tones (e.g., Poetic, Adventurous, Concise).
    * This text-to-text approach ensures fast response times and protects user visual privacy — no photos are sent to the cloud LLM.
* **Multi-Device Seamless Synchronization:** Automatic real-time sync of all data across HarmonyOS devices and web browsers.
    * Memory nodes, routes, and drafts sync across phones, tablets, and the web portal.
    * Record moments on the go via mobile and continue editing on a larger screen.
    * Conflict resolution via timestamp-and-version-based strategy ensures data integrity.

### 2. Non-Functional Requirements

* **Usability:**
    * Core journaling workflows (pin a node, start a route, share) should be completable within 3 taps from the home screen.
    * The app should provide clear visual feedback for all background operations (syncing, AI generation) so users are never left wondering about system status.
* **Performance:**
    * **Map Rendering:** Dynamically cluster and selectively render nodes/routes to maintain smooth frame rates (target ≥ 55 fps) even with thousands of data points.
    * **AI Response Time:** LLM copywriting requests should deliver the first token within 2 seconds (TTFB) to keep the interaction responsive.
    * **App Launch:** Cold start to interactive map screen should complete within 3 seconds on standard HarmonyOS devices.
* **Security & Privacy:**
    * **Mandatory Metadata Stripping:** All EXIF data (device model, coordinates, timestamps) is forcibly stripped at the local layer before any sync or share operation.
    * **Secure Sharing:** Shared links use HMAC-SHA256 signatures with TTL expiration; sequential/guessable IDs are prohibited.
    * **AI Content Compliance:** All AI-generated copy passes content moderation filters before being shown to the user or persisted.
* **Reliability & Availability:**
    * **Offline-First:** The app remains fully functional (create nodes, edit drafts, browse history) with zero network connectivity; local storage is the primary data source.
    * **Eventual Consistency Sync:** On reconnection, queued changes sync via background retry with version-based conflict resolution, targeting a high sync success rate (> 99%).
* **Resource Efficiency:**
    * **Battery:** Background processes suspend unnecessary GPS polling and WebSocket heartbeats to minimize power drain.
    * **Bandwidth:** Under cellular networks, the system automatically fetches low-resolution thumbnails instead of originals and defers bulk sync to Wi-Fi.

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

# User Story Map

This diagram shows the decomposition from high-level user needs down to epics, user stories, tasks, and acceptance criteria.

```mermaid
graph TD
    %% 定义颜色与样式
    classDef need fill:#262057,stroke:#fff,stroke-width:2px,color:#fff,rx:10px,ry:10px;
    classDef epic fill:#D60F5D,stroke:#fff,stroke-width:2px,color:#fff,rx:10px,ry:10px;
    classDef story fill:#0DA2B3,stroke:#fff,stroke-width:2px,color:#fff,rx:10px,ry:10px;
    classDef task fill:#7D7D7D,stroke:#fff,stroke-width:2px,color:#fff,rx:4px,ry:4px;
    classDef criteria fill:#9BD18A,stroke:#fff,stroke-width:2px,color:#fff,rx:4px,ry:4px;

    %% 高层用户需求
    UN["<b>User Need</b><br/>As a user, I want to securely record, organize, replay,<br/>and share travel memories based on map locations<br/>across my HarmonyOS devices"]:::need

    %% 史诗 Epic 划分 (重构为 4 个模块)
    E1["<b>Epic 1: Core Map & Memory</b><br/>Location nodes & Filtering"]:::epic
    E2["<b>Epic 2: Journey Playback & Export</b><br/>Animation & Video Export"]:::epic
    E3["<b>Epic 3: Social Sharing & AI</b><br/>Web Link & AI Copy Generation"]:::epic
    E4["<b>Epic 4: Cloud & Sync</b><br/>Data Backup & Multi-device"]:::epic

    UN --> E1
    UN --> E2
    UN --> E3
    UN --> E4

    %% ================= Epic 1 =================
    US1["<b>US #3 (Check-in) [P0]</b><br/>Attach photos, notes, and mood<br/>tags to specific map coordinates"]:::story
    US2["<b>US #54 (Filter) [P0]</b><br/>Filter map nodes by time<br/>range or custom tags"]:::story
    
    E1 --> US1
    E1 --> US2

    %% ================= Epic 2 =================
    US3["<b>US #6 (Trajectory) [P0]</b><br/>Combine photos/notes into a<br/>dynamic, animated route"]:::story
    US4["<b>US #66 (Playback Control) [P0]</b><br/>Control playback speed and<br/>pause at specific nodes"]:::story
    US5["<b>US #53 (Export) [P0]</b><br/>Export animated journey as a<br/>video or rich-media card"]:::story

    E2 --> US3
    E2 --> US4
    E2 --> US5

    %% ================= Epic 3 =================
    US6["<b>US #2 (Web Link) [P1]</b><br/>Share route via a time-limited<br/>web link for external viewing"]:::story
    US7["<b>US #5 (AI Copy) [P1]</b><br/>Use AI to generate social media<br/>posts based on selected data"]:::story

    E3 --> US6
    E3 --> US7

    %% ================= Epic 4 =================
    US8["<b>US #72 (Backup) [P1]</b><br/>Continuously back up travel data<br/>via Huawei Cloud Space"]:::story
    US9["<b>US #4 (Sync) [P2]</b><br/>Auto-sync nodes recorded on<br/>phone to tablet"]:::story

    E4 --> US8
    E4 --> US9

    %% ================= Tasks =================
    T1["Tasks<br/>Fetch GPS & Photo Picker<br/>Build tagging/filtering logic"]:::task
    T2["Tasks<br/>Animation Engine & Playback Controls<br/>Video Rendering Pipeline"]:::task
    T3["Tasks<br/>Extract metadata for LLM API<br/>Generate Secure H5 Web Page"]:::task
    T4["Tasks<br/>Huawei Account Auth &<br/>Distributed Data Sync"]:::task

    US1 --> T1
    US2 --> T1
    
    US3 --> T2
    US4 --> T2
    US5 --> T2
    
    US6 --> T3
    US7 --> T3
    
    US8 --> T4
    US9 --> T4

    %% ================= Acceptance Criteria =================
    AC1["<b>Acceptance Criteria (Core)</b><br/>Uses minimum permissions; Raw photos do not leave device.<br/>Sub-second response time for map filtering."]:::criteria
    AC2["<b>Acceptance Criteria (Media)</b><br/>Smooth cinematic playback without lag.<br/>Exported video/card maintains high resolution."]:::criteria
    AC3["<b>Acceptance Criteria (Social)</b><br/>Sends only desensitized metadata to LLM. Web links<br/>must use HMAC-SHA256 signature and TTL expiration."]:::criteria
    AC4["<b>Acceptance Criteria (Sync)</b><br/>Offline-first capability; 99.9% sync success rate.<br/>Sensitive data encrypted via HarmonyOS TEE."]:::criteria

    T1 --> AC1
    T2 --> AC2
    T3 --> AC3
    T4 --> AC4
```

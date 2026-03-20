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

    %% 节点定义 (基于 Proposal 需求分析)
    UN["<b>User Need</b><br/>As a user, I want to structurally record, organize, and share my life<br/>and travel memories based on geographical locations using a HarmonyOS app"]:::need

    E1["<b>Epic 1: Core Map & Memory</b><br/>Manage location nodes, dynamic<br/>trajectories, and data synchronization"]:::epic
    E2["<b>Epic 2: Social & AI Features</b><br/>Generate AI copy and share<br/>travel routes cross-platform"]:::epic

    US1["<b>User story (Map Check-in)</b><br/>As a regular user, I want to add<br/>memory nodes at specific GPS<br/>coordinates on the map"]:::story
    US2["<b>User story (Trajectory)</b><br/>As a traveler, I want to combine<br/>multiple nodes into a route and<br/>play it dynamically"]:::story
    US3["<b>User story (Sync)</b><br/>As a multi-device user, I want<br/>my data to sync automatically<br/>between phone and PC"]:::story

    US4["<b>User story (AI Copy)</b><br/>As a social media sharer, I want<br/>the system to automatically generate<br/>social media copy"]:::story
    US5["<b>User story (Sharing)</b><br/>As a content creator, I want to<br/>generate a web link for my travel<br/>route with one click"]:::story

    T1["Tasks<br/>Fetch GPS & Photo Picker"]:::task
    T2["Tasks<br/>Render map animation"]:::task
    T3["Tasks<br/>Cloud queue & retry sync"]:::task
    T4["Tasks<br/>Invoke LLM API"]:::task
    T5["Generate secure<br/>route URL"]:::task
    T6["Develop read-only<br/>H5 page"]:::task

    AC1["Acceptance criteria<br/>(Strip Exif metadata)"]:::criteria
    AC2["Acceptance criteria<br/>(Clustering & Frame rate)"]:::criteria
    AC3["Acceptance criteria<br/>(99.9% sync success)"]:::criteria
    AC4["Acceptance criteria<br/>(Content risk filter)"]:::criteria

    AC5["<b>It's done when the user can:</b><br/>1. Get AI-generated copy based on image & location features.<br/>2. Generate a secure external link (HMAC-SHA256, TTL).<br/>3. View the shared read-only H5 route on an external browser."]:::criteria

    %% 层级连接
    UN --> E1
    UN --> E2

    %% 模拟图中左侧直接从 User Need 连到 User Story 的线
    UN -.- US1

    E1 --> US1
    E1 --> US2
    E1 --> US3

    E2 --> US4
    E2 --> US5

    US1 --> T1
    US1 --> AC1

    US2 --> T2
    US2 --> AC2

    US3 --> T3
    US3 --> AC3

    US4 --> T4
    US4 --> T5
    US4 --> AC4
    US5 --> T6

    %% 将右侧的 User Story 连到共同的 Acceptance Criteria
    US4 --> AC5
    US5 --> AC5
```

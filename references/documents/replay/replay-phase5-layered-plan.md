# Replay Phase 5 Layered Plan

## 1. Scope

Phase 5 is no longer treated as one large “effects bucket”. It should be delivered in three layers so that route readability improves first, then motion clarity, and only then optional demo-grade effects are added.

Core principle:

1. Prioritize route readability over spectacle.
2. Keep manual jumps fast.
3. Keep all high-cost effects behind explicit toggles.

## 2. Delivery Layers

### Layer 1: Route Trail Baseline

Goal: replace the current single static route line with a two-layer route language.

Visual model:

1. Pending route: full-route baseline, lighter and more transparent.
2. Visited route: highlighted trail, brighter and more solid.

Implementation slice:

1. Add route style tokens:
   `routePendingColor`, `routeVisitedColor`, `routePendingWidth`, `routeVisitedWidth`.
2. Add a replay effect toggle:
   `enableRouteTrail`.
3. In `TripReplayPage`, maintain two route overlays:
   one for the full pending route, one for the visited route.
4. On autoplay:
   visited route advances with node progress.
5. On manual jump:
   visited route snaps directly to the target node index.
6. On toggle off:
   fall back to the current static route behavior.

Test gate:

1. Single-node route stays stable.
2. Two-node route shows baseline first, then visited trail after movement.
3. Multi-node route supports manual jump without stale partial trail.
4. Theme switch changes route colors and width consistently.

Release criterion:
Users can clearly distinguish where the replay has already been and where it will go next.

### Layer 2: Moving Route Marker

Goal: make the current active segment obvious without sacrificing responsiveness.

Visual model:

1. Replace the current generic moving icon with a theme-linked travel dot.
2. Keep the dot in UI overlay space, driven by map projection.
3. Reuse node ripple or pulse as the arrival signal.

Implementation slice:

1. Upgrade `movingIconVisible/movingIconScreenX/movingIconScreenY` rendering to a lighter dot-style marker.
2. Bind marker color and glow to the current `ReplayStyleKit`.
3. Keep marker motion synchronized with camera movement and route progress.
4. Preserve the existing fast manual jump behavior.

Test gate:

1. Marker follows the active segment in autoplay.
2. Repeated next/prev operations do not re-show stale marker states.
3. Progress-bar scrubbing does not leave delayed marker callbacks behind.
4. All playback speeds remain visually synchronized.

Release criterion:
Users can immediately tell which segment is currently being traversed.

### Layer 3: Optional Particle Tail

Goal: add demo-grade motion polish only after the first two layers are stable.

Visual model:

1. Subtle tail or spark emission behind the moving marker.
2. Stronger glow only for themes that support it.
3. Default off.

Implementation slice:

1. Validate whether ArkUI overlay is sufficient before introducing Canvas.
2. Add a separate particle toggle.
3. Keep the effect theme-aware and conservative for `Vintage Film`.
4. Ensure cleanup on page exit, pause, and rapid switching.

Test gate:

1. With particles off, behavior matches Layer 2 exactly.
2. With particles on, no obvious frame drop during sustained playback.
3. Theme change, page exit, and backgrounding release all particle state.

Release criterion:
Particles are additive only, never required for route comprehension.

## 3. Integration Notes

1. Layer 1 should be implemented before `Lottie` and before export work.
2. Layer 2 can reuse the current moving icon machinery and should not require MapKit custom marker support.
3. Layer 3 should be allowed to slip without blocking the rest of Phase 5.
4. `ReplayEndOverlay` and `RouteSummaryCard` export remain separate workstreams and should not share a commit with route animation experiments.

## 4. Suggested Commit Strategy

1. `feat(replay): add route trail baseline for replay`
2. `feat(replay): add moving route marker feedback`
3. `feat(replay): add optional route particle tail`
4. `feat(replay): add replay completion summary overlay`
5. `feat(replay): support route summary card export`

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Course**: Southern University of Science and Technology - Software Engineering (2026 Spring)
**Team**: Team Project 26 Spring - Group 7
**Repository**: `sustech-cs304/team-project-26spring-26s-7`

**Project**: HarmonyOS location-based travel journal app (鸿蒙地理位置旅行日记应用)

Core features:
- Pin photos/memories to precise geographic locations on a map
- Create and replay animated travel routes
- One-click cross-platform sharing (WeChat, Weibo)
- AI-powered social media caption generation
- Multi-device sync with offline-first architecture

## Tech Stack

### Frontend (HarmonyOS App)
- **Framework**: ArkTS + ArkUI (declarative UI)
- **Location**: HarmonyOS `LocationHub` API
- **Media**: System Photo Picker (minimal permission model)
- **Local Storage**: RDB (Relational Database) + File System

### Backend & AI
- **Architecture**: Offline-first with eventual consistency sync
- **Local AI**: LLM for OCR/summarization, ML for text vectorization
- **Cloud**: PostGIS for spatial data, Object Storage for media
- **Sync**: Distributed sync server with conflict resolution

### Security & Privacy
-强制 EXIF data stripping on upload
- HMAC-SHA256 signed share links with TTL
- AI content moderation before persistence

## Repository Structure

```
team-project-26spring-26s-7/
├── README.md          # Preliminary requirement analysis (5 functional + non-functional requirements)
├── proposal-7.md      # GitHub Classroom assignment file
├── structure/
│   ├── wbs_dictionary.md      # WBS breakdown: 5 team members (FE: A/B, BE: C/D, QA: E)
│   ├── software_architecture.md # System architecture diagram (3-tier: FE/BE/Cloud)
│   └── *.png          # Generated architecture diagrams
```

## WBS Team Assignment

| Member | Role | Tasks |
|--------|------|-------|
| A | UI/UX Lead | Visual design, prototype, frontend scaffolding |
| B | Interaction Lead | HarmonyOS FileSystem API, map integration |
| C | Infrastructure Lead | Server deployment, local LLM deployment |
| D | AI/Backend Lead | Remote LLM API, application logic |
| E | Compliance Lead | App store compliance, security audit |

## Architecture Layers

1. **Front End** (HarmonyOS App): Map UI, trajectory playback, media picker, share module
2. **Local Back End** (Offline First): Privacy filter (EXIF removal), RDB, sync manager, local ML/LLM
3. **Cloud** (Distributed Services): Sync server, PostGIS, OSS, web portal, AI gateway

## Development Notes

- **Git Flow**: Main branch is protected; PRs for changes
- **Documentation**: All docs must follow structured Markdown with clear headers
- **Language**: Chinese/English bilingual; add space between CJK and Latin characters (盘古之白)
- **Commit Style**: Conventional Commits (feat:, fix:, docs:, etc.)

## Key Files to Reference

- `README.md`: 5 core functional requirements, non-functional requirements (performance, security, reliability)
- `structure/wbs_dictionary.md`: Team task breakdown and responsibilities
- `structure/software_architecture.md`: 3-tier architecture with data flow

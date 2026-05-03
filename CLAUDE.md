# CLAUDE.md — evolution_portal (Flutter)

## Project Overview
Flutter mobile/web app for the Evolution platform.
- Auth: Firebase Authentication
- Backend: andyQueen Django REST API (separate repo)
- Solo developer workflow

## Repository
- GitHub: github.com/francoisk6/evolution_portal (private)
- Default branch: `main`
- Branching strategy: direct to `main` for low-risk changes; feature branch when the change is risky or touches multiple screens/flows

## Commit Convention
Conventional Commits — enforced manually.
Examples:
  feat(auth): add biometric login fallback
  fix(api): handle 401 refresh token expiry
  refactor(widgets): extract PlanCard into shared/
  chore: bump flutter version

## Code Response Format
Every code change must be labeled:
- `[PATCH]` — partial edit to an existing file
- `[FULL REPLACEMENT]` — entire file is replaced

Each response must include:
1. **Change log** — what changed and why
2. **Affected files** — list with paths
3. **Application steps** — exact commands or copy-paste instructions

## Goal Breakdown Format
When breaking down a feature or task:
- **Title** — short name
- **Description** — what it does and why
- **Success criteria** — observable, testable outcome

## Visual Design Rule ⚠️
Do NOT change layout, colors, spacing, typography, component sizing, or widget structure unless explicitly instructed.
This is the UI project. Treat all visual output as locked unless the user says otherwise.

## Architecture Notes

### Directory Layout (expected)
lib/
main.dart
app/              # App-level routing, theme, providers
features/         # Feature-first folders (auth/, dashboard/, etc.)
auth/
screens/
widgets/
controllers/  # or providers/
shared/
widgets/        # Reusable UI components
models/         # Shared data models
services/       # API client, Firebase wrappers
core/
constants/
utils/
### State Management
- [Fill in after /init — Riverpod / Provider / Bloc / setState?]

### API Communication
- Backend: andyQueen Django REST API
- Auth token: Firebase ID token passed as Bearer in Authorization header
- Base URL managed via environment config (not hardcoded)

### Firebase
- Auth only (no Firestore, no FCM — unless noted otherwise)
- Firebase config files: `google-services.json` (Android), `GoogleService-Info.plist` (iOS) — never committed

## What to Avoid
- Do not add packages without asking first
- Do not restructure folders unless asked
- Do not touch `pubspec.lock` formatting
- Do not add test files unless explicitly requested (no formal test policy)
- Do not modify `firebase_options.dart` structure

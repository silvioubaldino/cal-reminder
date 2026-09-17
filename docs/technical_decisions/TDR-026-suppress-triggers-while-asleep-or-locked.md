---
id: TDR-026
type: tdr
title: Drop Triggers that come due while the Mac is asleep or the screen is locked
status: accepted
updated: 2026-09-17
parents: [AYD-011]
related: [RF-04, RNF-03, RNF-04, RN-02, AYD-001]
superseded_by: null
---

# TDR-026: Drop Triggers that come due while the Mac is asleep or the screen is locked

> Append-only: never rewrite. A new decision = a new TDR that supersedes this one
> (`superseded_by`).

## Context
`AYD-011` left "Reminders missed while the Mac slept" as an open question, on the reading that a
past-due Trigger is *dropped* on wake by `rearmAll()`. In practice it isn't, reliably: an armed
Trigger is a `Task.sleep` whose deadline can elapse while the process is suspended, so on wake the
sleep returns immediately and `fire()` runs — racing the `didWakeNotification` handler that was
supposed to cancel it. With several Triggers due across a long sleep, the user gets a burst of
stale Airplanes back to back, announcing Events that already started.

Screen lock was never handled at all. A Reminder due while the Mac is merely locked fires normally,
and `OverlayPanel.level = .screenSaver` puts the animation *above* the lock screen — announced to
nobody, and gone by the time the user is back.

Shutdown and restart are already correct for free: the armed set lives only in memory
(`AYD-011` §Out of scope), so a fresh launch's `reconcile()` never arms a past-due Trigger.

## Decision
1. **A Trigger that comes due while the Mac is asleep or the screen is locked is dropped, not
   queued.** This resolves `AYD-011`'s open question in favor of dropping: the Airplane exists to
   catch the user's eye at a moment they're at the machine (RF-04); firing it late is noise, and
   firing ten of them at once is worse. No grace rule is introduced, so RNF-03 is untouched.
2. **Two independent gates in `Scheduler`, OR'd into the existing `fire()` guard.** `isAsleep` and
   `isLocked` join `enabled` (RF-06). They are separate flags rather than one "suppressed" flag
   because a Mac wakes with the screen still locked — clearing one must not unblock firing while
   the other holds.
3. **Suppression is armed on `willSleepNotification`, not `didSleepNotification`.** The gate has to
   be up *before* the process is suspended; that is what makes the race unwinnable rather than
   merely unlikely. `handleWake()` clears it before `rearmAll()`, keeping the wake path's existing
   order (re-arm against the current clock, then re-Poll — RNF-04).
4. **Lock state comes from the informal `com.apple.screenIsLocked` /
   `com.apple.screenIsUnlocked` distributed notifications.** AppKit exposes no public API for it.
   They are undocumented but long-stable; if they ever stop arriving, the failure is benign —
   `isLocked` stays `false` and the app behaves exactly as it did before this change.
5. **A dropped Trigger stays dropped.** `fire()` returns before `firedIds.insert`, so the id is not
   marked as fired — the same shape as the `enabled` gate. A later Poll may legitimately re-arm it
   if its `fireDate` is somehow still in the future; `reconcile()`'s past-due check handles the
   normal case.

## Alternatives & trade-offs
- **Fire the missed Reminders on wake, collapsed into one Airplane** — rejected: still announces
  Events that already started, and needs the grace rule `AYD-011` flagged as unanswered.
- **Rely on `rearmAll()` alone, called earlier on wake** — rejected: it is the same race, only
  narrower. Nothing orders the suspended `Task.sleep`'s resumption against the wake notification.
- **One combined `suppressed` flag** — rejected: wake-while-locked would clear it and let a stale
  Trigger through, which is the exact bug this fixes.
- **Poll the lock state via `CGSessionCopyCurrentDictionary`** — rejected: needs a timer to be
  useful, and buys nothing over the notifications except a supported API surface for a check whose
  failure mode is already benign.

## Consequences
- `Scheduling` gains `setAsleep(_:)` and `setLocked(_:)`; `AppCoordinator.start()` registers four
  observers instead of one.
- A Reminder whose moment passes while the Mac is asleep, hibernating, shut down, or locked is
  silently dispensed with. `AYD-011`'s open question is closed.
- The user sees nothing on wake until the post-wake Poll finds a genuinely upcoming Trigger.

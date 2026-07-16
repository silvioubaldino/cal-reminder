---
id: PRIVACY-POLICY
type: privacy-policy
title: Privacy Policy
status: approved
updated: 2026-07-16
related: [AYD-005, GLO]
---

# Privacy Policy — cal-reminder

_Last updated: 2026-07-16_

**cal-reminder** is a macOS menu bar app that connects to your Google Calendar (read-only)
and shows an on-screen animation when one of your Events' Reminders is due.

## What the app accesses

- **Calendar data.** With your permission, the app reads the Calendars and timed Events in
  your connected Google account (`calendar.readonly` scope) so it can compute when to show
  a Reminder. It never creates, edits, or deletes anything in your calendar.
- **Account email.** The app reads the connected Google account's email address so it can
  display which account is connected in the menu bar.

## What the app does with this data

- Calendar and email data is used **only on your Mac**, to decide when and what to show in
  the Reminder animation and the menu bar. The app does not run its own servers.
- The app does **not** sell, share, or transmit your calendar or account data to any third
  party. The only network traffic is directly between your Mac and Google's own servers
  (for sign-in and calendar sync).
- The app does **not** track you, and does not use your data for advertising or analytics.

## What is stored, and where

- Your Google sign-in token is stored **only in the macOS Keychain**, protected by the
  operating system. It is never written to disk in plain text and never leaves your Mac.
- Your preferences (Flight Speed, Banner color, which Calendars you've selected to be
  alerted on) are stored locally on your Mac using standard macOS app preferences.
- No calendar content or account data is retained beyond what is needed to compute and show
  upcoming Reminders.

## Your controls

- You can disconnect the app from your Google account at any time from the menu bar, which
  revokes local access to the stored token.
- You can choose which Calendars generate Reminders, or turn the app off entirely, from the
  menu bar.

## Contact

Questions about this policy can be sent to the developer at silvioubaldino@gmail.com.

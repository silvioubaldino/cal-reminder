---
id: PRIVACY-POLICY
type: privacy-policy
title: Privacy Policy
status: approved
updated: 2026-09-16
related: [AYD-010, AYD-012, GLO]
---

# Privacy Policy — cal-reminder

_Last updated: 2026-09-16_

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
  the Reminder animation and the menu bar.
- The app does **not** sell, share, or transmit your calendar or account data to any third
  party. Calendar traffic goes directly between your Mac and Google's own servers (for sign-in
  and calendar sync), and never to us.
- The app does **not** track you and does not use your data for advertising. It does send us
  anonymous usage counts, described below, which you can switch off.

## What we receive

The version of the app downloaded from our site runs a small service of ours so we can tell how
the app is doing in the field. It sends two kinds of report:

- **Usage counts**, roughly hourly and once a day: how many Reminder animations played, how many
  Google accounts you have connected, how many calendars you selected, and which versions of the
  app and of macOS you are running.
- **A random identifier** generated the first time the app runs, so we can tell one installation
  from another. It is not derived from you, your Mac or your Google account, and it lets us count
  installations, nothing more.

These reports never contain your calendar events, your calendar names, your email address, or
anything you typed. We do not keep the IP address the report arrived from. You can switch usage
reporting off at any time from the menu bar, and the app will stop sending it.

**Crash reports** are separate and always ask first. If the app crashes, macOS writes a technical
report about it. On the next launch we show you that report and ask whether to send it. Nothing is
sent unless you say yes, we ask again for each new crash rather than remembering an answer, and
what we receive is kept for 90 days and then deleted.

**If you build the app yourself** from our public source code, none of this happens: with no
configuration of ours in the build, the app contacts no server of ours at all — no usage reports,
no crash reports, and no update checks.

## What is stored, and where

- Your Google sign-in token is stored **only in the macOS Keychain**, protected by the
  operating system. It is never written to disk in plain text and never leaves your Mac.
- Your preferences (Flight Speed, Banner color, which Calendars you've selected to be
  alerted on) are stored locally on your Mac using standard macOS app preferences.
- No calendar content or account data is retained beyond what is needed to compute and show
  upcoming Reminders.
- The random installation identifier described above is stored in the macOS Keychain on your Mac,
  alongside the usage counts waiting to be sent.

## Your controls

- You can disconnect the app from your Google account at any time from the menu bar, which
  revokes local access to the stored token.
- You can choose which Calendars generate Reminders, or turn the app off entirely, from the
  menu bar.
- You can switch off usage reporting from the menu bar, and you can decline any crash report.

## Contact

Questions about this policy can be sent to the developer at silvioubaldino@gmail.com.

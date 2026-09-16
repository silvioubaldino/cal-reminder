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
- The app does **not** track you and does not use your data for advertising. It does send us a
  few anonymous counts, described below, which you can switch off.

## What we receive

The version of the app downloaded from our site sends us a small number of counts, so we can tell
whether the app is working and whether a new version reached people. It sends three things:

- **How many times the Reminder animation played.**
- **One "used today" signal per day**, the first time the app notices a new day while it is
  running — when you start your Mac, when it wakes, or when it shows you a Reminder.
- **One signal when the app is installed**, saying whether it was a first install or an update.

Each of these carries the version of the app and of macOS you are running, and nothing else.

There is **no identifier** in any of it. We do not generate one, do not store one, and do not send
one — so we cannot tell one Mac from another, cannot follow the same installation from one day to
the next, and cannot connect anything we receive to you. We do not keep the IP address the report
arrived from either. What we end up with is a daily number, such as "412 installations were used
today, 380 of them on version 1.4.2". You can switch it off from the menu bar at any time.

These reports never contain your calendar events, your calendar names, your email address, or
anything you typed.

**If you build the app yourself** from our public source code, none of this happens: with no
configuration of ours in the build, the app contacts no server of ours at all — no usage counts
and no update checks.

## What is stored, and where

- Your Google sign-in token is stored **only in the macOS Keychain**, protected by the
  operating system. It is never written to disk in plain text and never leaves your Mac.
- Your preferences (Flight Speed, Banner color, which Calendars you've selected to be
  alerted on) are stored locally on your Mac using standard macOS app preferences.
- No calendar content or account data is retained beyond what is needed to compute and show
  upcoming Reminders.
- The counts waiting to be sent are held locally on your Mac until they are delivered, and
  discarded once they are.

## Your controls

- You can disconnect the app from your Google account at any time from the menu bar, which
  revokes local access to the stored token.
- You can choose which Calendars generate Reminders, or turn the app off entirely, from the
  menu bar.
- You can switch off the usage counts from the menu bar at any time.

## Contact

Questions about this policy can be sent to the developer at silvioubaldino@gmail.com.

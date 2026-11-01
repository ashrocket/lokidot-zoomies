# Let your pet watch the clock

Calendar alarms are available in the **Mac source build**. The published 1.3.2 installers and Windows preview do not include this feature yet.

Open **Calendar alarms…** in the playground or paw menu, or run:

```sh
lokidot calendars
```

1. Click **Connect calendars…** and respond to the macOS permission prompt.
2. Select the calendars you want your pet to watch. Each one shows its account/source name.
3. Choose **At the start**, or **1, 5, 10, or 15 minutes before**.
4. Turn on **Let my pets remind me**.

An upcoming event brings up a small pet-alarm card and, if enabled, a gentle sound. A resting pet takes a lap. Paused pets stay paused, and Reduce Motion keeps them still. **Snooze 5 min** reminds you again; **Dismiss** closes that reminder. Simultaneous reminders are shown in turn. All-day events, cancelled events, and invitations you declined are skipped.

Try it without connecting a calendar:

```sh
lokidot alarm-test
```

Or click **Try a pet alarm**. The test never creates an event or requests calendar access.

## Apple Calendar

Any event calendar visible to this Mac through Apple's calendar system can be selected: iCloud, local calendars, and supported synced accounts. Allow LokiDot when macOS asks. macOS 14 and later call the permission **full access**, because EventKit has no read-only permission for fetching events. LokiDot only reads events; it never creates, edits or deletes them. On macOS 13 the older calendar permission is used.

If access was denied, allow LokiDot in **System Settings → Privacy & Security → Calendars**, then click **Refresh**. The app stays usable without calendar access. A newly signed development build may need permission again.

## Google Calendar

Add Google to **Apple Calendar → Settings → Accounts → + → Google**, sign in through Google's normal flow, and enable Calendars. Wait until those events appear in Apple Calendar, then refresh LokiDot and select the Google calendars you want.

This integration reads Google's calendars through macOS sync. It does not sign directly into Google, ask for a Google API key, or store Google tokens. Sync delays and calendars excluded from Apple's account sync also affect pet alarms. Google's official [Apple Calendar setup guide](https://support.google.com/calendar/answer/99358?hl=en) covers account and calendar selection.

## Keep your pet on duty

Keep LokiDot running and your Mac awake and signed in. Closing the playground leaves the app running in the paw menu. Quitting the app stops alarms. This feature does not install a background service, wake the Mac, or deliver system notifications while the app is closed.

Alarms are hidden while the screen sleeps or the user session is inactive. On return, reminders missed by up to two minutes can appear if the event has not ended; older reminders are skipped. Snoozed reminders also stop when their event ends. Calendar events refresh when the local store changes and at least once a minute while active. The look-ahead window is 24 hours.

## Your events stay local

Event titles are hidden in alerts by default. Enable **Show event titles in alerts** if you want them visible on your screen. Titles and event snapshots stay in memory; local preferences retain selected calendar identifiers and opaque delivery keys/times so restarts do not repeat an alarm. Recent delivery history expires after the event ends plus one day. Snoozes survive restarts while their event remains available. Calendar data is never sent to GitHub or another service by LokiDot.

Turn off **Let my pets remind me** to stop reading events in the background. Revoke access in System Settings to disconnect the app completely. Calendar alarms use their own lead time, rather than copying each event's existing Apple or Google notification settings.

Implementation follows Apple's [EventKit access guidance](https://developer.apple.com/documentation/eventkit/accessing-calendar-using-eventkit-and-eventkitui) and [macOS 14 permission changes](https://developer.apple.com/documentation/technotes/tn3153-adopting-api-changes-for-eventkit-in-ios-macos-and-watchos).

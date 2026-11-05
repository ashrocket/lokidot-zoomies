# Meeting reminders

LokiDot Zoomies reminds you about meetings. Before a meeting, the whippet runs across your screen. A card shows the meeting title, the start time and a **Join** button. The menu bar shows the time to your next meeting.

Meeting reminders are in the Mac source build 2.0.0. The published 1.3.2 installers and the Windows preview do not have them.

## Set up

1. Open **Meeting reminders…** in the paw menu or the playground. You can also run `lokidot calendars`.
2. Connect a calendar source. Use one or more of the sources below.
3. Make sure **Remind me about meetings** is on.
4. Turn on **Open LokiDot at login**. If the app is not open, it cannot remind you.

To see a reminder card without a calendar, click **Try a reminder** or run `lokidot alarm-test`.

## Calendar sources

| Calendar | Recommended source |
| --- | --- |
| iCloud and local calendars | Apple Calendar |
| Google Calendar | Apple Calendar (Google account on this Mac), or the Google link |
| Outlook.com and Microsoft 365 | The Outlook link |

### Apple Calendar

Click **Connect Apple Calendar…** and allow access when macOS asks. Then select the calendars to watch. Each calendar shows its account name.

This source includes every account that you added to Apple Calendar: iCloud, Google, Exchange and others. macOS 14 and later call the permission **full access**, because EventKit has no read-only permission. LokiDot only reads events. It never creates, changes or deletes them.

If you denied access, open **System Settings → Privacy & Security → Calendars**, allow LokiDot, and click **Refresh**.

### Google Calendar link

Use this source when your Google account is not in Apple Calendar.

1. Open Google Calendar on the web.
2. Open **Settings**, then select your calendar under **Settings for my calendars**.
3. Copy **Secret address in iCal format**.
4. Paste the link in **Google or Outlook calendar link** and click **Add link**.

### Outlook link

Use this source for Microsoft 365 work calendars. On October 1, 2026, Microsoft started to turn off Exchange Web Services (EWS) in Exchange Online. Apple Calendar uses EWS for Exchange accounts. Thus a work Outlook calendar can stop syncing to Apple Calendar.

1. Open Outlook on the web.
2. Open **Settings → Calendar → Shared calendars**.
3. Under **Publish a calendar**, select your calendar and **Can view all details**. Click **Publish**.
4. Copy the **ICS** link.
5. Paste the link in **Google or Outlook calendar link** and click **Add link**.

Some organizations do not allow calendar publishing. In that case, ask your administrator, or add the account to Apple Calendar if your organization permits it.

LokiDot reads each link every 10 minutes, when the Mac wakes, and when you click **Refresh**. If a read fails, LokiDot keeps the last good events. The settings window shows the time of the last read and any error.

**CAUTION:** A calendar link gives read access to your calendar. Do not share the link. LokiDot keeps the link only in its preferences on this Mac and sends it only to the calendar server.

If the same meeting comes from two sources, LokiDot shows one reminder. It keeps the copy that has a join link.

## Reminder behavior

- **First reminder**: at the start, or 1, 2, 5, 10 or 15 minutes before. The default is 5 minutes.
- **Remind me again when it starts**: on by default. You get a second card at the start time.
- The card has **Join** (when the meeting has a link), **Remind me at start** (or **Snooze 1 min** near the start) and **Dismiss**.
- The card does not take keyboard focus. A key that you type in another app cannot join or dismiss a meeting.
- **Join** opens links for Zoom, Google Meet, Microsoft Teams, Webex, Amazon Chime, Whereby, Jitsi Meet, Slack huddles, FaceTime, GoTo Meeting and BlueJeans. LokiDot finds the link in the event's conference data, URL, location or notes. It also opens links that Outlook Safe Links or Google redirects wrap.
- The paw menu lists the next meetings in the next 12 hours, each with **Join**.
- LokiDot skips all-day events, cancelled events and invitations that you declined.

### Sleep and missed reminders

LokiDot cannot remind you while the Mac sleeps. When the Mac wakes:

- If a first reminder was missed and the meeting has not started, the card shows.
- If the meeting started less than 10 minutes ago, the card shows once.
- Older reminders do not show.

### Privacy

Meeting titles show on the card and in the menu bar by default. Before you share your screen, turn off **Show meeting titles**. The card then shows "Your next meeting".

Event titles and event data stay in memory. LokiDot saves only the selected calendar identifiers, the calendar links, and opaque reminder keys with times. It saves reminder keys so that a restart does not repeat a reminder. Old keys expire one day after their event ends. LokiDot sends no calendar data to GitHub or to other services.

## Recurring events in links

LokiDot expands recurring events from calendar links on your Mac. It supports `DAILY`, `WEEKLY`, `MONTHLY` and `YEARLY` rules with `INTERVAL`, `COUNT`, `UNTIL`, `BYDAY`, `BYMONTHDAY`, `BYMONTH` and `WKST`. It also supports `EXDATE`, `RDATE`, moved or cancelled single occurrences (`RECURRENCE-ID`), and Windows time zone names from Outlook.

LokiDot does not support `BYSETPOS`, `BYHOUR` and other rare rule parts. It shows such an event once, at its first start. Apple Calendar sources do not have this limit, because macOS expands their rules.

## Resource use

Between reminders, LokiDot has no window on screen and runs no animation. It keeps no dog artwork in memory. One timer waits for the next reminder, and there is no polling every second. Apple Calendar changes arrive as system notifications. The reminder sound plays through the macOS sound service, so Core Audio does not stay in LokiDot's memory.

### Measured values

These values are for build 2.0.0 on a MacBook Pro with an M1 chip and 8 GB of memory, macOS 26.7.2, measured on November 3, 2026. CPU time, wakeups and energy come from the kernel's counters for the process (`proc_pid_rusage`). Memory is the value in the **Memory** column of Activity Monitor (the physical footprint).

CPU during 10 minutes of idle:

| Condition | CPU time | Share of one core | Processor wakeups | Energy |
| --- | --- | --- | --- | --- |
| Reminders off, nothing opened since launch | 0.011 s | 0.002% | 8 | less than 0.001 J |
| Reminders on, one calendar link, a meeting less than one hour away | 0.39 s | 0.065% | 92 | 0.03 J |

The reminders-on period includes the calendar link reads in that period (one read each 10 minutes) and a menu-bar countdown that changes each minute. In the same two periods, the Dock used 1.74 s and 0.12 s of CPU, and SystemUIServer used 0.009 s and 0.020 s. When no meeting is less than one hour away, the countdown does not run.

Memory:

| State | Memory |
| --- | --- |
| Fresh launch, idle | 10.9 MB |
| After the paw menu opens one time | 15.6 MB |
| After a reminder card with sound and a lap | 19.9 MB |
| While the settings window is open | 26.9 MB |
| After the settings window closes | 25.0 MB |
| Highest value during the test (during a lap) | 32.4 MB |

Each step in this table includes the steps above it. LokiDot releases each window, card and lap when it closes, and gives the free memory back to macOS. Most of the increase after use is caches that macOS keeps in the process for menus, buttons and text. When the Mac needs memory, macOS can remove some of these caches. On the same Mac, a test app with only a menu-bar icon uses 9.0 MB.

These values do not include Apple Calendar. When you connect Apple Calendar, macOS loads EventKit into LokiDot, and memory increases. LokiDot also reads the calendar again each time macOS syncs it. We did not measure CPU or memory with Apple Calendar connected.

[Version 2.0.0 verification](VERIFICATION-2.0.0.md) tells how these values were measured, and where the raw logs are.

### Check it yourself

1. Open Activity Monitor and find **LokiDotZoomies**.
2. On the **Memory** tab, read the **Memory** column.
3. On the **CPU** tab, read **CPU Time** and **Idle Wake Ups**. Wait 10 minutes, then read them again.
4. On the **Energy** tab, read **Energy Impact**.

In Terminal, this command shows one sample each minute for 10 minutes:

```sh
top -l 11 -s 60 -stats pid,command,cpu,time,idlew,power,mem -pid $(pgrep -x LokiDotZoomies)
```

`TIME` is the total CPU time since launch. At idle with reminders off, it changes by less than 0.02 s in 10 minutes.

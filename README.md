# Redmine Stopwatch plugin

|  |  |
|--|--|
| ![Redmine Stopwatch plugin](Doc/ru_RU/Manual/images/ChatGPT-Redmine-Stopwatch-crop-128x128.png) | A Redmine plugin that adds an interactive stopwatch timer directly to the site header. It allows you to track real working time on issues and record it via the standard Redmine time tracking mechanism. |

---

## Features

- **Timer in the header** — always available on any Redmine page
- **Context** — the widget displays a link to the current issue or project; when navigating to another page, both contexts are visible
- **Start / Pause / Resume** — control the timer without resetting accumulated time
- **Snaps** — the ⏭ button saves the current time segment and resets the counter for the next issue
- **Stop without redirect** — when the timer is stopped, the user stays on the current page; a counter of unsaved snaps is displayed next to the ☰ icon
- **Persistence** — state is stored on the server: the timer keeps running after closing the tab
- **Cross-tab synchronization** — switching the timer (start, stop, snap, etc.) instantly updates the widget in all open browser tabs via the BroadcastChannel API
- **Snaps page** — a list of all unsaved segments with editable project, issue, time, activity and comment fields
- **Active timer** — a block at the top of the snaps page shows the currently running/paused timer with editable time (H:MM), activity and comment fields; entering a time less than the current one creates a snap with the remainder and continues the timer, entering a greater one — snap and timer reset; saved values are transferred to the snap when the timer is stopped/switched; the ⏹ Stop button stops the timer preserving the comment and activity (blocked if the hours were edited)
- **Editable time** — the Hours field in snaps has become editable (H:MM format); when the time is decreased, the record is automatically split into the specified part and the remainder; increases are limited by a plugin setting
- **Other users' timers** — on the snaps page (with the appropriate permission) active timers of colleagues are displayed in read-only mode with ticking time
- **Three actions per snap** — Save (save fields), Log time (create a Redmine record), Delete (remove segment)
- **Issue autocomplete** — when editing an issue on the snaps page, autocomplete works with automatic project filling
- **Spent time block** — the snaps page displays the user's latest time entries grouped by date, with links to project/issue and an Edit button
- **Plugin settings** — default project, number of days for the Spent time block, maximum time increase per snap

---

## Timer widget

The widget is embedded in Redmine's `#top-menu`. Elements are separated by vertical lines.

| State | Layout |
|-----------|-------|
| Stopped | `[context ▶ \| ☰ badge]` |
| Running (same context) | `[#1234 - H:MM \| ⏸ ⏹ ⏭ \| ☰ badge]` |
| Running (different context) | `[#1234 - H:MM \| ⏸ ⏹ \| ProjectName ⏭ \| ☰ badge]` |
| Paused | same as "Running", but ⏯ instead of ⏸ |

- **▶** — start the timer (binds to the current issue/project)
- **⏸** — pause
- **⏯** — resume from the same point
- **⏹** — stop, save a snap (without navigating to another page)
- **⏭** — save the current segment as a snap, reset the counter, continue working in the new context
- **☰** — open the page with all unsaved snaps; the badge shows their count

Contexts are links: `#123` leads to the issue, `ProjectName` — to the project. Long project names are truncated to 20 characters.

---

## Stopwatch page

The page is divided into four boxed blocks (`.mypage-box`): **Active timer**, **Segments**, **Other users' timers**, **Spent time**.

### "Active timer" block

If the timer is running or paused, a block with the current timer is displayed at the top of the page:
- **Project** / **Issue** — timer context (read-only)
- **Hours** — a ticking editable field (H:MM); when a smaller value is entered — a snap is created and the timer continues with the remainder; when a greater value is entered — snap + timer reset; increases are limited by a plugin setting
- **Activity** — an editable drop-down list of activity types
- **Comments** — an editable text field

Actions:
- **Save** — save activity, comment and (if changed) time to the DB; a snap is created only if Hours has been changed
- **⏹ Stop** — save activity/comment, stop the timer, create a snap; blocked (grayed out) if Hours has been edited
- **Enter** on any field — same as Save

When the timer is stopped or a snap is taken via the widget, saved values are automatically transferred to the created segment.

### Snaps table

Snaps are grouped by date (headers "Today", "Yesterday" for the last two days).

A table with columns: **Project**, **Issue**, **Hours**, **Activity**, **Comments**, **Actions**.

- **Project** — a drop-down list of projects available to the user for Log time
- **Issue** — a text field with autocomplete; when an issue is selected, the project is filled in automatically
- **Hours** — an editable field in H:MM format; when the time is decreased, the record is automatically split into the specified part and the remainder; increases are limited by a plugin setting (default 60 minutes)
- **Activity** — a drop-down list of activity types (depends on the project)
- **Comments** — arbitrary text

Actions:
1. **Save** — save field changes to the database without creating a time entry (Comment is required); when Hours is decreased, a remainder segment is created
2. **Log time** — create a Redmine Time Entry and delete the snap (Project, Activity and Comment are required); when Hours is decreased, a remainder segment is created
3. **Delete** — delete the snap with confirmation

When the project is changed, the issue is cleared. When an issue is selected via autocomplete, the project is filled in automatically.

### "Other users' timers" block

If the **View other users' stopwatch** permission is granted, a block with active timers of other users (read-only) is displayed on the snaps page: user, project, issue, ticking time and state (Running/Paused).

---

## Plugin settings

**Administration > Plugins > Redmine Stopwatch > Configure**

- **Default project** — the project pre-selected for snaps without context. If not set, the drop-down list is empty.
- **Days of spent time to show** — the number of days for which time entries are displayed in the Spent time block on the snaps page (default: 2).
- **Maximum time increase per segment** — the maximum allowed increase of snap time in minutes (default: 60).

---

## Requirements

| Component | Version |
|-----------|--------|
| Redmine | >= 6.1.0 |
| Ruby | >= 3.2 |
| Rails | 7.2 |

---

## Installation

### 1. Place the plugin in Redmine's plugins folder

Copy or clone the repository into Redmine's `plugins` directory under the name `redmine_stopwatch`:

```bash
# Clone
git clone <url> /path/to/redmine/plugins/redmine_stopwatch

# Or a symbolic link (for development)
ln -s /path/to/this/repo /path/to/redmine/plugins/redmine_stopwatch
```

> **Important:** the folder must be named exactly `redmine_stopwatch` — this is the plugin's name.

### 2. Apply database migrations

```bash
cd /path/to/redmine
bundle exec rake redmine:plugins:migrate
```

The following tables are created:
- `stopwatch_timers` — timer state for each user (including comment and activity)
- `stopwatch_segments` — saved time segments waiting to be entered into Log Time

### 3. Restart Redmine

```bash
# Puma / Passenger / other server — restart according to your stack
touch tmp/restart.txt  # for Passenger
```

### 4. Verify the installation

Open **Administration > Plugins** — the `Redmine Stopwatch` plugin should appear in the list.

### 5. Enable permissions

**Administration > Roles and permissions** — for the required roles, activate:
- **Use stopwatch** — access to the timer and snaps page; without this checkbox the user gets a 403 error
- **View other users' stopwatch** — view active timers of other users on the snaps page (optional)

---

## Uninstallation

```bash
cd /path/to/redmine
bundle exec rake redmine:plugins:migrate NAME=redmine_stopwatch VERSION=0
```

After that, remove the plugin folder from `plugins/redmine_stopwatch`.

---

## Plugin structure

```
redmine_stopwatch/
├── init.rb                              # Plugin registration, settings, permissions
├── config/
│   ├── routes.rb                        # API and plugin page routes
│   └── locales/
│       └── en.yml                       # Localization (English)
├── app/
│   ├── controllers/
│   │   └── stopwatch_controller.rb      # Timer API, snaps page, CRUD
│   ├── models/
│   │   ├── stopwatch_timer.rb           # Timer state model
│   │   └── stopwatch_segment.rb         # Time segment model
│   └── views/
│       ├── settings/
│       │   └── _stopwatch_settings.html.erb  # Plugin settings
│       └── stopwatch/
│           ├── _widget.html.erb         # Timer widget in the header
│           └── segments.html.erb        # Snaps page
├── assets/
│   ├── javascripts/
│   │   └── stopwatch.js                 # Widget logic (jQuery)
│   └── stylesheets/
│       └── stopwatch.css                # Widget and snaps page styles
├── db/
│   └── migrate/
│       ├── 001_create_stopwatch_timers.rb
│       ├── 002_create_stopwatch_segments.rb
│       ├── 003_add_started_on_to_stopwatch_timers.rb
│       ├── 004_add_fields_to_stopwatch_segments.rb
│       ├── 005_convert_stopwatch_columns_to_utf8.rb
│       ├── 006_add_comments_to_stopwatch_timers.rb
│       └── 007_add_activity_id_to_stopwatch_timers.rb
└── lib/
    └── stopwatch_hook_listener.rb       # Widget injection and context detection
```

---

## API

All endpoints require authorization and the `:use_stopwatch` permission.

### Timer control (JSON)

| Method | URL | Description |
|--------|-----|----------|
| GET | `/stopwatch/state.json` | Current timer state |
| POST | `/stopwatch/start.json` | Start the timer |
| POST | `/stopwatch/pause.json` | Pause |
| POST | `/stopwatch/resume.json` | Resume |
| POST | `/stopwatch/snap.json` | Snap + reset + continue |
| POST | `/stopwatch/stop.json` | Stop + snap |

`start` and `snap` accept `issue_id` or `project_id` to bind the context.

All responses include `pending_segments_count` for updating the badge.

### Segments (HTML)

| Method | URL | Description |
|--------|-----|----------|
| GET | `/stopwatch/segments` | Snaps page |
| POST | `/stopwatch/segments/:id/update` | Save snap fields |
| POST | `/stopwatch/segments/:id/save` | Create a Time Entry |
| DELETE | `/stopwatch/segments/:id` | Delete the snap |

### Timer (HTML)

| Method | URL | Description |
|--------|-----|----------|
| POST | `/stopwatch/timer/update_comment` | Save comment, activity and (optionally) timer time; when hours are changed — snap with custom time; `stop=1` — additionally stop the timer and create a snap |

### Auxiliary (JSON)

| Method | URL | Description |
|--------|-----|----------|
| GET | `/stopwatch/issue_project/:issue_id.json` | Project ID for the issue (for autocomplete) |

---

## How it works

1. On each Redmine page load, the server renders the current timer state, contexts (page and timer) and the snap counter into the widget's `data-*` attributes.
2. JavaScript reads this data and embeds the widget in the site header (`#top-menu`).
3. The counter is updated every minute on the client side without requests to the server.
4. Control buttons send AJAX requests to the plugin API.
5. Timer state is stored in the database — the timer keeps running at any moment, even if the browser is closed.
6. On stop/snap a snap (segment) is created — a record with a project, issue, time and date. The user can edit the fields and save it as a Time Entry via the snaps page.
7. After each timer action, the widget sends the updated state via BroadcastChannel, and all other tabs instantly redraw their widget.
8. When the timer is switched on the snaps page, the page is automatically reloaded to refresh the data.

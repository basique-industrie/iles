import Domain

extension FirstPartyComplicationCatalog {
    static let clockRecipes: [ComplicationRecipe] = [
        recipe(
            id: "system.clock.current-time",
            name: "Current Time",
            summary: "The current local time in a compact glance.",
            question: "What time is it?",
            sourceID: "system.clock",
            category: .time,
            tags: ["clock", "time", "local"],
            family: .value,
            metricIDs: ["time"],
            labelStyle: .value,
            rank: 100
        ),
        recipe(
            id: "system.clock.day-progress",
            name: "Day Progress",
            summary: "The portion of the current calendar day that has elapsed.",
            question: "How far through today am I?",
            sourceID: "system.clock",
            category: .time,
            tags: ["day", "progress", "today"],
            family: .ring,
            metricIDs: ["dayProgress"],
            rank: 98,
            featured: true
        ),
        recipe(
            id: "system.clock.workday-progress",
            name: "Workday Progress",
            summary: "Progress through the workday hours configured in Clock settings.",
            question: "How far through my workday am I?",
            sourceID: "system.clock",
            category: .time,
            tags: ["workday", "office", "progress"],
            family: .ring,
            metricIDs: ["workdayProgress"],
            rank: 97,
            featured: true
        ),
        recipe(
            id: "system.clock.week-progress",
            name: "Week Progress",
            summary: "The portion of the current week that has elapsed.",
            question: "How far through this week am I?",
            sourceID: "system.clock",
            category: .time,
            tags: ["week", "progress"],
            family: .ring,
            metricIDs: ["weekProgress"],
            rank: 94
        ),
        recipe(
            id: "system.clock.month-progress",
            name: "Month Progress",
            summary: "The portion of the current month that has elapsed.",
            question: "How far through this month am I?",
            sourceID: "system.clock",
            category: .time,
            tags: ["month", "progress"],
            family: .ring,
            metricIDs: ["monthProgress"],
            rank: 92
        ),
        recipe(
            id: "system.clock.year-progress",
            name: "Year Progress",
            summary: "The portion of the current year that has elapsed.",
            question: "How far through this year am I?",
            sourceID: "system.clock",
            category: .time,
            tags: ["year", "progress"],
            family: .ring,
            metricIDs: ["yearProgress"],
            rank: 90
        ),
        recipe(
            id: "system.clock.end-of-day",
            name: "End of Day",
            summary: "A countdown to the end of the current day.",
            question: "How much time is left today?",
            sourceID: "system.clock",
            category: .time,
            tags: ["day", "remaining", "countdown", "midnight"],
            family: .countdown,
            metricIDs: ["endOfDay"],
            transforms: [[.countdown]],
            labelStyle: .compact,
            rank: 96
        ),
    ]

    static let sessionRecipes: [ComplicationRecipe] = [
        recipe(
            id: "session.claude.state",
            name: "Live Session Status",
            summary: "The current Claude Code session phase.",
            question: "Is Claude Code actively working?",
            sourceID: "session.claude",
            category: .sessions,
            tags: ["Claude", "coding", "session", "status"],
            family: .status,
            metricIDs: ["state"],
            labelStyle: .compact,
            rank: 100,
            featured: true
        ),
        recipe(
            id: "session.claude.duration",
            name: "Session Duration",
            summary: "Elapsed time since the current coding session started.",
            question: "How long has this session been running?",
            sourceID: "session.claude",
            category: .sessions,
            tags: ["Claude", "coding", "session", "duration"],
            family: .value,
            metricIDs: ["duration"],
            labelStyle: .value,
            rank: 98,
            featured: true
        ),
        recipe(
            id: "session.claude.project",
            name: "Current Project",
            summary: "The folder name of the active coding session.",
            question: "Which project is Claude Code working in?",
            sourceID: "session.claude",
            category: .sessions,
            tags: ["Claude", "coding", "project", "repository"],
            family: .value,
            metricIDs: ["project"],
            labelStyle: .compact,
            rank: 96
        ),
        recipe(
            id: "session.claude.tasks",
            name: "Completed Tasks",
            summary: "Tasks completed during the current session.",
            question: "How many tasks has this session completed?",
            sourceID: "session.claude",
            category: .sessions,
            tags: ["Claude", "coding", "tasks", "completed"],
            family: .value,
            metricIDs: ["tasks"],
            labelStyle: .value,
            rank: 94
        ),
        recipe(
            id: "session.claude.agents",
            name: "Active Agents",
            summary: "Subagents currently working in the active session.",
            question: "How many agents are working?",
            sourceID: "session.claude",
            category: .sessions,
            tags: ["Claude", "agents", "subagents", "parallel"],
            family: .value,
            metricIDs: ["agents"],
            labelStyle: .value,
            rank: 95
        ),
        recipe(
            id: "session.claude.team",
            name: "Session Team",
            summary: "Session state, completed tasks, and active agents together.",
            question: "What is the overall progress of this coding session?",
            sourceID: "session.claude",
            category: .sessions,
            tags: ["Claude", "session", "tasks", "agents", "summary"],
            family: .summary,
            metricIDs: ["state", "tasks", "agents"],
            labelStyle: .compact,
            rank: 97
        ),
    ]

    static let macSystemRecipes: [ComplicationRecipe] = [
        recipe(id: "system.mac.cpu", name: "CPU Usage", summary: "Current processor utilization across the Mac.", question: "How busy is my Mac's processor?", sourceID: "system.mac", category: .mac, tags: ["CPU", "processor", "usage", "load"], family: .ring, metricIDs: ["cpu"], rank: 100, featured: true),
        recipe(id: "system.mac.memory", name: "Memory Load", summary: "Active, wired, and compressed memory as a share of physical memory.", question: "How much working memory is my Mac carrying?", sourceID: "system.mac", category: .mac, tags: ["memory", "RAM", "load", "pressure"], family: .ring, metricIDs: ["memory"], rank: 99, featured: true),
        recipe(id: "system.mac.storage-available", name: "Storage Available", summary: "The percentage of the startup volume still available for important files.", question: "What percentage of my storage is left?", sourceID: "system.mac", category: .mac, tags: ["storage", "disk", "available", "free", "remaining", "percentage"], family: .ring, metricIDs: ["storageAvailable"], rank: 98, featured: true),
        recipe(id: "system.mac.storage-free", name: "Free Storage", summary: "The exact disk space still available for important files.", question: "How many gigabytes of storage are left?", sourceID: "system.mac", category: .mac, tags: ["storage", "disk", "free", "remaining", "gigabytes"], family: .value, metricIDs: ["storageFree"], labelStyle: .value, rank: 96),
        recipe(id: "system.mac.network", name: "Network Status", summary: "Whether the Mac currently has a usable network path.", question: "Is my Mac online?", sourceID: "system.mac", category: .mac, tags: ["network", "internet", "online", "offline"], family: .status, metricIDs: ["network"], labelStyle: .compact, rank: 95),
        recipe(id: "system.mac.thermal", name: "Thermal State", summary: "The thermal pressure level currently reported by macOS.", question: "Is my Mac running too hot?", sourceID: "system.mac", category: .mac, tags: ["thermal", "heat", "temperature", "performance"], family: .status, metricIDs: ["thermal"], labelStyle: .compact, rank: 93),
        recipe(id: "system.mac.resources", name: "Resource Overview", summary: "CPU, memory load, and occupied storage in one coherent trio.", question: "Are my Mac's core resources under pressure?", sourceID: "system.mac", category: .mac, tags: ["CPU", "memory", "storage", "health", "trio"], family: .cluster, metricIDs: ["cpu", "memory", "storage"], labelStyle: .compact, rank: 98, featured: true),
        recipe(id: "system.mac.cpu-memory", name: "CPU + Memory", summary: "Smoothed processor utilization and working-memory load together.", question: "Which live resource is under more pressure?", sourceID: "system.mac", category: .mac, tags: ["CPU", "memory", "resources", "dual"], family: .dualRing, metricIDs: ["cpu", "memory"], rank: 97),
    ]

    static let focusRecipes: [ComplicationRecipe] = [
        recipe(id: "productivity.focus.state", name: "Focus Status", summary: "Whether a focus session, break, or idle state is active.", question: "Am I currently in a focus session?", sourceID: "productivity.focus", category: .focus, tags: ["focus", "Pomodoro", "status"], family: .status, metricIDs: ["state"], labelStyle: .compact, rank: 100, featured: true),
        recipe(id: "productivity.focus.remaining", name: "Focus Remaining", summary: "Time left in the current focus session or break.", question: "How much time remains in this interval?", sourceID: "productivity.focus", category: .focus, tags: ["focus", "Pomodoro", "remaining", "countdown"], family: .countdown, metricIDs: ["remaining"], labelStyle: .compact, rank: 99, featured: true),
        recipe(id: "productivity.focus.progress", name: "Focus Progress", summary: "Progress through the current focus session or break.", question: "How far through this interval am I?", sourceID: "productivity.focus", category: .focus, tags: ["focus", "Pomodoro", "progress"], family: .ring, metricIDs: ["progress"], rank: 98),
        recipe(id: "productivity.focus.daily-goal", name: "Daily Focus Goal", summary: "Progress toward your configured focused-work goal today.", question: "How close am I to today's focus goal?", sourceID: "productivity.focus", category: .focus, tags: ["focus", "daily", "goal", "deep work"], family: .ring, metricIDs: ["dailyGoal"], rank: 97, featured: true),
        recipe(id: "productivity.focus.sessions", name: "Sessions Today", summary: "Focus sessions completed today.", question: "How many focus sessions have I completed?", sourceID: "productivity.focus", category: .focus, tags: ["focus", "sessions", "count", "today"], family: .value, metricIDs: ["sessions"], labelStyle: .value, rank: 93),
        recipe(id: "productivity.focus.streak", name: "Focus Streak", summary: "Consecutive days on which the daily focus goal was reached.", question: "How long is my focus streak?", sourceID: "productivity.focus", category: .focus, tags: ["focus", "streak", "days", "goal"], family: .value, metricIDs: ["streak"], labelStyle: .value, rank: 90),
        recipe(id: "productivity.focus.overview", name: "Focus + Daily Goal", summary: "Current interval progress and today's focus goal together.", question: "How is this interval contributing to my daily goal?", sourceID: "productivity.focus", category: .focus, tags: ["focus", "overview", "dual", "goal"], family: .dualRing, metricIDs: ["progress", "dailyGoal"], labelStyle: .percentage, rank: 95),
    ]

    static let gitRecipes: [ComplicationRecipe] = [
        recipe(id: "developer.git.status", name: "Repository Status", summary: "Whether the selected repository is clean, changed, or conflicted.", question: "Is this repository ready to commit?", sourceID: "developer.git", category: .developer, tags: ["Git", "repository", "clean", "dirty", "conflict"], family: .status, metricIDs: ["status"], labelStyle: .compact, rank: 100, featured: true),
        recipe(id: "developer.git.branch", name: "Current Branch", summary: "The checked-out branch in the selected repository.", question: "Which branch am I working on?", sourceID: "developer.git", category: .developer, tags: ["Git", "branch", "repository"], family: .value, metricIDs: ["branch"], labelStyle: .compact, rank: 99),
        recipe(id: "developer.git.changes", name: "Changed Files", summary: "The number of modified, staged, and untracked files.", question: "How many files have local changes?", sourceID: "developer.git", category: .developer, tags: ["Git", "changes", "files", "dirty"], family: .value, metricIDs: ["changes"], labelStyle: .value, rank: 98, featured: true),
        recipe(id: "developer.git.sync", name: "Upstream Sync", summary: "Whether the branch is ahead, behind, diverged, or up to date.", question: "Is my branch synchronized with its upstream?", sourceID: "developer.git", category: .developer, tags: ["Git", "upstream", "ahead", "behind", "sync"], family: .status, metricIDs: ["sync"], labelStyle: .compact, rank: 97, featured: true),
        recipe(id: "developer.git.upstream-changes", name: "Upstream Changes", summary: "Sync state with exact ahead and behind counts.", question: "What needs to be pushed or pulled?", sourceID: "developer.git", category: .developer, tags: ["Git", "ahead", "behind", "sync", "summary"], family: .summary, metricIDs: ["sync", "ahead", "behind"], labelStyle: .compact, rank: 92),
        recipe(id: "developer.git.last-commit", name: "Last Commit Age", summary: "Elapsed time since the repository's most recent commit.", question: "How long ago was the last commit?", sourceID: "developer.git", category: .developer, tags: ["Git", "commit", "age", "time"], family: .value, metricIDs: ["lastCommit"], labelStyle: .value, rank: 90),
        recipe(id: "developer.git.overview", name: "Repository Overview", summary: "Working-tree state, changed files, and upstream sync together.", question: "Does this repository need attention?", sourceID: "developer.git", category: .developer, tags: ["Git", "repository", "overview", "summary"], family: .summary, metricIDs: ["status", "changes", "sync"], labelStyle: .compact, rank: 96),
    ]

    static let githubRecipes: [ComplicationRecipe] = [
        recipe(id: "developer.github.ci", name: "CI Status", summary: "The state and conclusion of the latest GitHub Actions workflow run.", question: "Is the latest build passing?", sourceID: "developer.github", category: .developer, tags: ["GitHub", "Actions", "CI", "build", "tests"], family: .status, metricIDs: ["ci"], labelStyle: .compact, rank: 100, featured: true),
        recipe(id: "developer.github.failing-jobs", name: "Failing Jobs", summary: "Jobs that failed, timed out, or were cancelled in the latest run.", question: "How many jobs need attention?", sourceID: "developer.github", category: .developer, tags: ["GitHub", "Actions", "jobs", "failures"], family: .value, metricIDs: ["failingJobs"], labelStyle: .value, rank: 98),
        recipe(id: "developer.github.pull-requests", name: "Open Pull Requests", summary: "Open pull requests in the configured repository.", question: "How many pull requests are open?", sourceID: "developer.github", category: .developer, tags: ["GitHub", "pull requests", "PR", "open"], family: .value, metricIDs: ["openPRs"], labelStyle: .value, rank: 95),
        recipe(id: "developer.github.reviews", name: "Reviews Requested", summary: "Open pull requests requesting a review from the current gh user.", question: "How many reviews are waiting for me?", sourceID: "developer.github", category: .developer, tags: ["GitHub", "review", "pull request", "requested"], family: .value, metricIDs: ["reviews"], labelStyle: .value, rank: 97, featured: true),
        recipe(id: "developer.github.deployment", name: "Deployment Status", summary: "The latest GitHub deployment status for the repository.", question: "Did the latest deployment succeed?", sourceID: "developer.github", category: .developer, tags: ["GitHub", "deployment", "production", "shipping"], family: .status, metricIDs: ["deployment"], labelStyle: .compact, rank: 99, featured: true),
        recipe(id: "developer.github.shipping", name: "Shipping Overview", summary: "CI, review requests, and deployment health together.", question: "Is this repository ready and safe to ship?", sourceID: "developer.github", category: .developer, tags: ["GitHub", "CI", "reviews", "deployment", "shipping", "summary"], family: .summary, metricIDs: ["ci", "reviews", "deployment"], labelStyle: .compact, rank: 99),
        recipe(id: "developer.github.delivery", name: "Delivery Queue", summary: "Open pull requests, review requests, and failing jobs as exact counts.", question: "What is blocking delivery?", sourceID: "developer.github", category: .developer, tags: ["GitHub", "pull requests", "reviews", "jobs", "summary"], family: .summary, metricIDs: ["openPRs", "reviews", "failingJobs"], labelStyle: .compact, rank: 94),
    ]

    static let calendarRecipes: [ComplicationRecipe] = [
        recipe(id: "calendar.events.next", name: "Next Event", summary: "The title of the current or next scheduled event.", question: "What is next on my calendar?", sourceID: "calendar.events", category: .time, tags: ["calendar", "event", "meeting", "next"], family: .value, metricIDs: ["nextTitle"], labelStyle: .compact, rank: 100, featured: true),
        recipe(id: "calendar.events.countdown", name: "Next Event Countdown", summary: "Time until the current or next event starts.", question: "How long until my next event?", sourceID: "calendar.events", category: .time, tags: ["calendar", "event", "meeting", "countdown"], family: .countdown, metricIDs: ["nextStart"], transforms: [[.countdown]], labelStyle: .compact, rank: 99, featured: true),
        recipe(id: "calendar.events.current", name: "Meeting Status", summary: "Whether a meeting is happening now or your time is free.", question: "Am I currently in a meeting?", sourceID: "calendar.events", category: .time, tags: ["calendar", "meeting", "status", "free"], family: .status, metricIDs: ["currentState"], labelStyle: .compact, rank: 98),
        recipe(id: "calendar.events.progress", name: "Meeting Progress", summary: "Progress through the meeting currently in progress.", question: "How far through this meeting am I?", sourceID: "calendar.events", category: .time, tags: ["calendar", "meeting", "progress"], family: .ring, metricIDs: ["meetingProgress"], rank: 97),
        recipe(id: "calendar.events.today", name: "Events Today", summary: "The number of non-all-day events scheduled today.", question: "How busy is my calendar today?", sourceID: "calendar.events", category: .time, tags: ["calendar", "events", "today", "count"], family: .value, metricIDs: ["eventsToday"], labelStyle: .value, rank: 94),
        recipe(id: "calendar.events.duration", name: "Next Event Duration", summary: "The scheduled length of the current or next event.", question: "How long is my next event?", sourceID: "calendar.events", category: .time, tags: ["calendar", "event", "duration"], family: .value, metricIDs: ["nextDuration"], labelStyle: .value, rank: 92),
        recipe(id: "calendar.events.overview", name: "Calendar Overview", summary: "Meeting state, next event, and today's event count together.", question: "What does my immediate schedule look like?", sourceID: "calendar.events", category: .time, tags: ["calendar", "overview", "meeting", "summary"], family: .summary, metricIDs: ["currentState", "nextTitle", "eventsToday"], labelStyle: .compact, rank: 95),
    ]

    static let reminderRecipes: [ComplicationRecipe] = [
        recipe(id: "calendar.reminders.due-today", name: "Due Today", summary: "Incomplete reminders due before the end of today.", question: "How many reminders are due today?", sourceID: "calendar.reminders", category: .time, tags: ["reminders", "tasks", "due", "today"], family: .value, metricIDs: ["dueToday"], labelStyle: .value, rank: 100, featured: true),
        recipe(id: "calendar.reminders.next", name: "Next Reminder", summary: "The next incomplete reminder with a due date.", question: "What reminder is due next?", sourceID: "calendar.reminders", category: .time, tags: ["reminders", "tasks", "next", "due"], family: .value, metricIDs: ["nextTitle"], labelStyle: .compact, rank: 98),
        recipe(id: "calendar.reminders.countdown", name: "Reminder Countdown", summary: "Time until the next reminder is due.", question: "How long until my next task is due?", sourceID: "calendar.reminders", category: .time, tags: ["reminders", "tasks", "countdown", "due"], family: .countdown, metricIDs: ["nextDue"], transforms: [[.countdown]], labelStyle: .compact, rank: 97),
        recipe(id: "calendar.reminders.overdue", name: "Overdue Reminders", summary: "Incomplete reminders whose due date has passed.", question: "How many tasks are overdue?", sourceID: "calendar.reminders", category: .time, tags: ["reminders", "tasks", "overdue", "late"], family: .value, metricIDs: ["overdue"], labelStyle: .value, rank: 96),
        recipe(id: "calendar.reminders.overview", name: "Reminder Overview", summary: "Due-today and overdue counts with the next reminder.", question: "What needs attention in Reminders?", sourceID: "calendar.reminders", category: .time, tags: ["reminders", "tasks", "overview", "summary"], family: .summary, metricIDs: ["dueToday", "overdue", "nextTitle"], labelStyle: .compact, rank: 99, featured: true),
    ]

    static let serviceRecipes: [ComplicationRecipe] = [
        recipe(id: "services.endpoint.status", name: "Service Status", summary: "Whether the configured endpoint is responding successfully.", question: "Is this service up?", sourceID: "services.endpoint", category: .services, tags: ["service", "endpoint", "uptime", "status"], family: .status, metricIDs: ["status"], labelStyle: .compact, rank: 100, featured: true),
        recipe(id: "services.endpoint.latency", name: "Latency Trend", summary: "Direction and severity of recent endpoint response times.", question: "Is this service getting slower?", sourceID: "services.endpoint", category: .services, tags: ["service", "endpoint", "latency", "trend"], family: .trend, metricIDs: ["latency"], labelStyle: .value, rank: 98, featured: true),
        recipe(id: "services.endpoint.latency-value", name: "Latency Value", summary: "The exact response time from the most recent check.", question: "What was the latest response time?", sourceID: "services.endpoint", category: .services, tags: ["service", "latency", "milliseconds"], family: .value, metricIDs: ["latencyValue"], labelStyle: .value, rank: 97),
        recipe(id: "services.endpoint.availability", name: "Last 50 Checks", summary: "Successful responses as a share of the latest fifty local checks.", question: "How reliably has this service responded in recent checks?", sourceID: "services.endpoint", category: .services, tags: ["service", "availability", "checks", "history"], family: .ring, metricIDs: ["availability"], rank: 97),
        recipe(id: "services.endpoint.response", name: "Response Code", summary: "The HTTP result from the most recent endpoint check.", question: "What response did the service return?", sourceID: "services.endpoint", category: .services, tags: ["service", "HTTP", "response", "code"], family: .value, metricIDs: ["responseCode"], labelStyle: .compact, rank: 94),
        recipe(id: "services.endpoint.last-check", name: "Last Checked", summary: "Elapsed time since the endpoint was last checked.", question: "How recently was this service checked?", sourceID: "services.endpoint", category: .services, tags: ["service", "health", "check", "age", "time"], family: .value, metricIDs: ["lastCheck"], transforms: [[.elapsed]], labelStyle: .value, rank: 92),
        recipe(id: "services.endpoint.failures", name: "Consecutive Failures", summary: "Checks that have failed since the last successful response.", question: "How many checks have failed in a row?", sourceID: "services.endpoint", category: .services, tags: ["service", "failures", "errors", "count"], family: .value, metricIDs: ["failures"], labelStyle: .value, rank: 93),
        recipe(id: "services.endpoint.overview", name: "Service Overview", summary: "Status, exact latency, and recent-check availability together.", question: "What is the overall health of this service?", sourceID: "services.endpoint", category: .services, tags: ["service", "health", "overview", "summary"], family: .summary, metricIDs: ["status", "latencyValue", "availability"], labelStyle: .compact, rank: 99, featured: true),
    ]
    static let batteryRecipes: [ComplicationRecipe] = [
        recipe(
            id: "system.battery.charge-ring",
            name: "Battery Charge",
            summary: "Current Mac battery charge as a glanceable ring.",
            question: "How much battery remains?",
            sourceID: "system.battery",
            category: .mac,
            tags: ["battery", "charge", "power"],
            family: .ring,
            metricIDs: ["level"],
            rank: 100,
            featured: true
        ),
        recipe(
            id: "system.battery.power-state",
            name: "Power State",
            summary: "Whether the Mac is charging, plugged in, or on battery.",
            question: "Where is my Mac getting power?",
            sourceID: "system.battery",
            category: .mac,
            tags: ["battery", "charging", "plugged", "power"],
            family: .status,
            metricIDs: ["power"],
            labelStyle: .compact,
            rank: 97
        ),
        recipe(
            id: "system.battery.time-remaining",
            name: "Battery Time Remaining",
            summary: "The estimated time until the battery empties or finishes charging.",
            question: "How long will this charge last?",
            sourceID: "system.battery",
            category: .mac,
            tags: ["battery", "remaining", "duration"],
            family: .countdown,
            metricIDs: ["remaining"],
            labelStyle: .compact,
            rank: 96,
            featured: true
        ),
        recipe(
            id: "system.battery.health",
            name: "Battery Health",
            summary: "The battery condition reported by macOS.",
            question: "Is my battery healthy?",
            sourceID: "system.battery",
            category: .mac,
            tags: ["battery", "health", "condition"],
            family: .status,
            metricIDs: ["health"],
            labelStyle: .compact,
            rank: 90
        ),
        recipe(
            id: "system.battery.overview",
            name: "Battery Overview",
            summary: "Charge, power source, and battery health together.",
            question: "What is the overall state of my battery?",
            sourceID: "system.battery",
            category: .mac,
            tags: ["battery", "overview", "summary"],
            family: .summary,
            metricIDs: ["level", "power", "health"],
            labelStyle: .compact,
            rank: 95
        ),
    ]

}

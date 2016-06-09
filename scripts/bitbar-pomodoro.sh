#!/bin/bash

CURRENT_TIME=$(date +%s)
REMINDER_URI=$1
REMINDER_NAME=$(osascript -lJavaScript <<EOF
var rid = "$REMINDER_URI";
if (rid && rid.startsWith("x-apple-reminder://")) {
    Application("Reminders").reminders.byId(rid).name();
}
EOF
)

echo "$CURRENT_TIME|1|$REMINDER_URI|$REMINDER_NAME" > $TMPDIR/bitbar-pomodoro
echo $REMINDER_NAME

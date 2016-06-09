#!/bin/bash
#
# <bitbar.title>bitbar-pomodoro</bitbar.title>
# <bitbar.version>v1.0</bitbar.version>
# <bitbar.author>Yoshinobu Fujimoto</bitbar.author>
# <bitbar.author.github>jimo1001</bitbar.author.github>
# <bitbar.desc>Pomodoro Technique for BitBar</bitbar.desc>
# <bitbar.image></bitbar.image>

# 25 min
POMODORO_TIME=$((25 * 60))
# 5 min
SHORT_BREAK_TIME=$((5 * 60))
# 15 min
LONG_BREAK_TIME=$((15 * 60))

CALENDAR="Pomodoro"

STATE_FILE=$TMPDIR/bitbar-pomodoro
MENUBAR_LOGO='⟲'

FONT_FAMILY="Ricty"
FONT_SIZE=15

# UNIX time
CURRENT_TIME=$(date +%s)

STATE="$CURRENT_TIME|0||"

if [ -f "$STATE_FILE" ]; then
    STATE=$(cat "$STATE_FILE")
fi

TIME=$(echo "$STATE" | cut -d "|" -f1)
STATUS=$(echo "$STATE" | cut -d "|" -f2)
REMINDER_URI=$(echo "$STATE" | cut -d "|" -f3)
REMINDER_TITLE=$(echo "$STATE" | cut -d "|" -f4)

function changeStatus {
    echo "$CURRENT_TIME|$1|$REMINDER_URI|$REMINDER_TITLE" > "$STATE_FILE";
}

function notify {
    osascript -e "display notification \"$1\" with title \"$MENUBAR_LOGO Pomodoro\"" &> /dev/null
}

function getReminderTitle {
    if [ ! -n "$REMINDER_TITLE" -a -n "$REMINDER_URI" ]; then
        REMINDER_TITLE=$(osascript -lJavaScript -e "Application('Reminders').reminders.byId(\"$REMINDER_URI\").name()")
        changeStatus $STATUS
    fi
    echo $REMINDER_TITLE
}

function startShortBreak {
    changeStatus "2"
    notify "Start short break"
}

function startLongBreak {
    changeStatus "3"
    notify "Start long break"
}

function finishBreak {
    changeStatus "0"
    notify "Break time finished"
}

function startPomodoro {
    changeStatus "1"
    notify "Start Pomodoro\n$(getReminderTitle)"
}

function stopPomodoro {
    changeStatus "0"
    notify "Stop Pomodoro"
}

case "$1" in
"work")
    startPomodoro
    exit
  ;;
"s_break")
    startShortBreak
    exit
  ;;
"l_break")
    startLongBreak
    exit
  ;;
"cancel")
    changeStatus "0"
    notify "Pomodoro cancelled"
    exit
  ;;
esac

function timeLeft {
    local FROM=$1
    local TIME_DIFF=$((CURRENT_TIME - TIME))
    local TIME_LEFT=$((FROM - TIME_DIFF))
    echo "$TIME_LEFT";
}

function getSeconds {
    echo $(($1 % 60))
}

function getMinutes {
    echo $(($1 / 60))
}

function displayTime {
    SECONDS=$(getSeconds "$1")
    MINUTES=$(getMinutes "$1")
    printf "%s %02d:%02d|ansi=true font=$FONT_FAMILY size=$FONT_SIZE color=%s\n" "$MENUBAR_LOGO" "$MINUTES" "$SECONDS" "$2"
}

case "$STATUS" in
"0")
    displayTime "0" "black"
  ;;
"1")
    TIME_LEFT=$(timeLeft $POMODORO_TIME)
    if (( "$TIME_LEFT" < 0 )); then
        if [ -n "$REMINDER_URI" ]; then
            osascript -lJavaScript <<EOF
// Reminders.app
var rApp = Application("Reminders");
var r = rApp.reminders.byId("$REMINDER_URI");
r.body = "🍅" + (r.body() || "");

// Calendar.app
var cApp = Application("Calendar");
var e = new cApp.Event({
    summary: "$(getReminderTitle)",
    startDate: new Date($TIME * 1000),
    endDate: new Date()
});
cApp.calendars.byName("$CALENDAR").events.push(e);
EOF
        fi
        startShortBreak
    fi
    displayTime "$TIME_LEFT" "black"
  ;;
"2")
    TIME_LEFT=$(timeLeft $SHORT_BREAK_TIME)
    if (("$TIME_LEFT" < 0)); then
        finishBreak
    fi
    displayTime "$TIME_LEFT" "green"
  ;;
"3")
    TIME_LEFT=$(timeLeft $LONG_BREAK_TIME)
    if (("$TIME_LEFT" < 0)); then
        finishBreak
    fi
    displayTime "$TIME_LEFT" "green"
  ;;
esac

echo "$(getReminderTitle)"
echo "---"
echo "➠ Start Pomodoro | bash=$0 param1=work terminal=false"
echo "⤿ Short Break | bash=$0 param1=s_break terminal=false"
echo "↺ Long Break | bash=$0 param1=l_break terminal=false"
echo "⤫ Cancel | bash=$0 param1=cancel terminal=false"

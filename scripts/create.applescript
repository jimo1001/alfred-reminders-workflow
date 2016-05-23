// -*- coding: utf-8; mode: js2 -*-


function run(args) {
    if (!args) {
        return;
    }
    var arg = args[0];
    var listId = arg.split(" ")[0];
    var text = arg.substr(listId.length + 1);
    var app = Application("Reminders");

    var newReminder = new app.Reminder();
    newReminder.name = text;
    app.lists.byId(listId).reminders.push(newReminder);
    return text;
}

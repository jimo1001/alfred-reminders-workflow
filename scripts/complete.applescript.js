function run(args) {
    if (!args || !args[0]) {
        return "";
    }
    var query = args[0];
    if (query.startsWith("x-apple-reminder://")) {
        var app = Application("Reminders");
        var reminder = app.reminders.byId(query);
        reminder.completed = true;
        return reminder.name();
    }
    return "";
}

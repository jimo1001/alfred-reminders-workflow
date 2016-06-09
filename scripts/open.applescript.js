function run(args) {
    if (!args || !args[0]) {
        return;
    }
    var query = args[0];
    var app = Application("Reminders");
    app.activate();
    // Reminder
    if (query.startsWith("x-apple-reminder://")) {
        app.reminders.byId(query).show();
        return;
    }
    // List
    Array.prototype.slice.call(app.lists).some(function (list) {
        if (list.id() === query) {
            list.show();
            return true;
        }
        return false;
    });
}

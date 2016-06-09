function run(args) {
    if (!args || !args[0]) {
        return;
    }
    var query = args[0];
    var listId = query.split(" ")[0];
    var text = query.substr(listId.length + 1);
    if (!listId || !text) {
        return;
    }
    var app = Application("Reminders");
    var r = new app.Reminder();
    r.name = text;
    app.lists.byId(listId).reminders.push(r);
    return text;
}

// -*- coding: utf-8; mode: js2 -*-

var URL_SCHEME = "x-apple-reminder:"

function run(args) {
    if (!args || !args[0]) {
        return;
    }
    var arg = args[0];
    var app = Application("Reminders");
    app.activate();
    if (arg.startsWith(URL_SCHEME)) {
        app.reminders.byId(arg).show();
        return;
    }
    Array.prototype.slice.call(app.lists).some(function (list) {
        if (list.id() === arg) {
            list.show();
            return true;
        }
        return false;
    });
    app.open(URL_SCHEME);
}

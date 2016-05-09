// -*- coding: utf-8; mode: js2 -*-

function debug(o) {
    console.log(JSON.stringify(o));
}

function toArray(ref, propNames) {
    if (!isArraySpecifier(ref)) {
        return ref;
    }
    var array = [];
    propNames.forEach(function (name, i) {
        var _ref = ref;
        name.split(".").forEach(function (s) {
            _ref = _ref[s];
        });
        _ref().forEach(function (value, j) {
            if (i === 0) {
                array.push({});
            }
            array[j][name] = value;
        });
    });
    return array;
}

function escapeXML(src) {
    if (!src) {
        return src;
    }
    return src.replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&apos;');
}

function isArraySpecifier(o) {
    return o && o.toString() === "[object ArraySpecifier]";
}

function each(xs, fn) {
    if (!xs || typeof fn !== "function") {
        return;
    }
    var isRef = isArraySpecifier(xs);
    var props;
    for (var i = 0, len = xs.length; i < len; i++) {
        if (isRef) {
            props = xs[i].properties();
        } else {
            props = xs[i];
        }
        if (fn.apply(xs, [props, i]) === false) {
            break;
        }
    }
}

function wrap(str, wrapWith) {
    str = str || "";
    wrapWith = wrapWith ? String(wrapWith) : "";
    return wrapWith + str + wrapWith;
}

function formatDateString(d) {
    var delta = Math.floor((Date.now() - d.getTime()) / 86400000);
    switch(delta) {
    case 0:
        return "Today";
    case 1:
        return "Tomorrow";
    case -1:
        return "Yesterday";
    }
    return [d.getFullYear(), d.getMonth() + 1, d.getDate()].join("-");
}

function formatTimeString(d) {
    return d.toTimeString().substring(0, 5);
}

function formatDateTimeString(d) {
    return formatDateString(d) + " " + formatTimeString(d);
}

function getPriorityLabel(priority) {
    if (priority < 4) {
        return "!!!";
    }
    if (priority < 7) {
        return "!!";
    }
    return "!";
}

function getAccountXml(props) {
    if (!props.id || !props.name) {
        return null;
    }
    var xName = escapeXML(wrap(props.name, '"'));
    return `<item arg="${props.id}" autocomplete="account:${xName}" valid="no">
<title>Account: ${escapeXML(props.name)}</title>
<subtitle>Select the account</subtitle>
</item>`;
}

function getReminderListXml(props, context) {
    if (!props.id || !props.name) {
        return null;
    }
    var xName = escapeXML(wrap(props.name, '"'));
    var autocomplete = "list:" + xName;
    if (context.args.account) {
        autocomplete = "account:" + escapeXML(wrap(context.args.account, '"')) + " " + autocomplete;
    }
    return `<item arg="${props.id}" autocomplete="${autocomplete}">
<title>List: ${escapeXML(props.name)}</title>
<subtitle>Open the reminder&apos;s list in Remainders.app</subtitle>
</item>`;
}

function getReminderItemXml(props, ccontex) {
    if (!props.id || !props.name) {
        return null;
    }
    var listName = props["container.name"];
    var dateStr = formatDateTimeString(props.creationDate);
    return `<item arg="${props.id}">
<title>${escapeXML(props.name)}</title>
<subtitle>${getPriorityLabel(props.priority)} Reminder: created at ${dateStr} (${listName})</subtitle>
</item>`;
}

function getUsageXml() {
    return `<item>
<title>r [OPTIONS] ...</title>
<subtitle>OPTIONS: account:{Account name} list:{Reminder&apos;s list}</subtitle>
</item>`;
}

function getReminderCreationItemXML(context) {
    return `<item arg="${context.refs.list.id()} ${escapeXML(context.text)}">
<title>${context.text}</title>
<subtitle>Create new reminder in ${context.refs.list.name()}</subtitle>
</item>`;
}

function createXML(items) {
    return `<?xml version="1.0"?>
<items>
${items.join("\n")}
</items>`;
}

// parse command line arguments
function parseArgs(args) {
    var context = {
        command: "show",
        text: "",
        args: {
            account: "",
            list: ""
        },
        refs: {
            account: null,
            list: null
        },
        raw: ""
    };
    function parse(target) {
        var parsing = Object.keys(context.args).some(function (key) {
            var prefix = key + ":";
            var value = "";
            if (!target.startsWith(prefix)) {
                return false;
            }
            target = target.substring(prefix.length);
            if (target[0] === '"') {
                value = target.match(/\"([^"]*)\"?/)[1];
                parse(target.substring(value.length + 2).trim());
            } else {
                value = target.split(" ")[0];
                parse(target.substring(value.length).trim());
            }
            context.args[key] = value;
            return true;
        });
        if (!parsing) {
            context.text = target;
        }
    }
    args.forEach(function (arg, i) {
        if (i === 0) {
            context.command = arg;
            return;
        }
        parse(arg);
        context.raw = arg;
    });
    return context;
}

function usage() {
    return createXML([getUsageXml()]);
}

function search(app, context, aRef, lRef, rRef) {
    var items = [];
    if (rRef) {
        toArray(rRef, ["id", "name", "priority", "creationDate", "container.name"]).forEach(function (x) {
            var item = getReminderItemXml(x, context);
            if (item) {
                items.push(item);
            }
        });
    }
    if (!rRef && lRef) {
        toArray(lRef, ["id", "name"]).forEach(function (x) {
            var item = getReminderListXml(x, context);
            if (item) {
                items.push(item);
            }
        });
    }
    if (!lRef && aRef) {
        toArray(aRef, ["id", "name"]).forEach(function (x) {
            var item = getAccountXml(x);
            if (item) {
                items.push(item);
            }
        });
    }
    return createXML(items);
}

function create(app, context) {
    var text = context.text.trim();
    if (!text || "account".startsWith(text) || "list".startsWith(text)) {
        return;
    }
    if (!context.refs.list) {
        context.refs.list = app.defaultList;
    }
    return createXML([getReminderCreationItemXML(context)]);
}

function run(args) {
    if (args.length != 2 || !args[1]) {
        return usage();
    }
    var context = parseArgs(args);
    var app = Application("Reminders");
    var refs = context.refs;
    var reminderFinding = true;

    // Accounts
    var aRef = null;
    if (context.args.account) {
        aRef = app.accounts.whose({
            name: {
                _beginsWith: context.args.account
            }
        });
    } else if ("account".startsWith(context.text)) {
        aRef = app.accounts;
        reminderFinding = false;
    }
    if (aRef && aRef.length === 1) {
        refs.account = aRef[0];
    }
    // Reminder's Lists
    var lRef = null;
    if (context.args.list) {
        lRef = refs.account ? refs.account.lists : app.lists;
        lRef = lRef.whose({
            name: {
                _beginsWith: context.args.list
            }
        });
    } else if ("list".startsWith(context.text)) {
        lRef = refs.account ? refs.account.lists : app.lists;
        reminderFinding = false;
    }
    if (lRef && lRef.length === 1) {
        refs.list = lRef[0];
    }
    switch(context.command) {
    case "search": {
        // Reminders
        var rRef = null;
        if (reminderFinding && context.text) {
            rRef = refs.list ? refs.list.reminders : app.defaultList.reminders;
            rRef = rRef.whose({
                _and: [
                    { completed: false },
                    { name: { _contains: context.text }}
                ]});
        }
        return search(app, context, aRef, lRef, rRef);
    }
    case "create":
        return create(app, context);
    default:
        return;
    }
}

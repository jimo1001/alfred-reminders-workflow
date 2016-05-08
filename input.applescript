// -*- coding: utf-8; mode: js2 -*-

function debug(o) {
    console.log(JSON.stringify(o));
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

function toTitleCase(str) {
    return str.replace(/\w\S*/g, function (txt) {
        return txt.charAt(0).toUpperCase() + txt.substr(1).toLowerCase();
    });
}

function getAccountXml(props) {
    if (!props.id || !props.name) {
        return null;
    }
    var xName = escapeXML(wrap(props.name, '"'));
    return `<item uid="${props.id}" arg="${props.id}" autocomplete="account:${xName}" valid="no">
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
    return `<item uid="${props.id}" arg="${props.id}" autocomplete="${autocomplete}">
<title>List: ${escapeXML(props.name)}</title>
<subtitle>Open the reminder&apos;s list in Remainders.app</subtitle>
</item>`;
}

function getReminderItemXml(props, ccontex) {
    if (!props.id || !props.name) {
        return null;
    }
    var xName = escapeXML(wrap(props.name, '"'));
    var listName = props.container ? props.container.name() : null;
    var dateStr = formatDateTimeString(props.creationDate);
    return `<item uid="${props.id}" arg="${props.id}" autocomplete="${xName}">
<title>${escapeXML(props.name)}</title>
<subtitle>${getPriorityLabel(props.priority)} ${toTitleCase(props.pcls)}: created at ${dateStr} (${listName})</subtitle>
</item>`;
}

function getNoSuchItemIXml() {
    return `<item>
<title>No such item</title>
<subtitle></subtitle>
</item>`;
}

function getUsageXml() {
    return `<item>
<title>r [OPTIONS] ...</title>
<subtitle>OPTIONS: account:{Account name} list:{Reminder&apos;s list}</subtitle>
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

function run(args) {
    if (args.length != 2 || !args[1]) {
        return usage();
    }
    var context = parseArgs(args);
    var app = Application("Reminders");
    var refs = context.refs;
    var items = [];
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
    each(rRef, function (x, i) {
        var item = getReminderItemXml(x, context);
        if (item) {
            items.push(item);
        }
        return i < 5;
    });
    if (rRef && items.length === 0) {
        items.push(getNoSuchItemIXml());
    }
    if (!rRef || refs.list) {
        each(lRef, function (x) {
            var item = getReminderListXml(x, context);
            if (item) {
                items.push(item);
            }
        });
    }
    if (!lRef && aRef) {
        each(aRef, function (x) {
            var item = getAccountXml(x);
            if (item) {
                items.push(item);
            }
        });
    }
    debug(context);
    return createXML(items);
}

//
//  main.swift
//  alfred-reminders-workflow
//
//  Created by jimo1001 on 2016/05/17.
//  Copyright (c) 2016 jimo1001. All rights reserved.
//

import Foundation
import EventKit


enum CommandType {
    case Search
    case Create
}

struct Context {
    var command: CommandType = CommandType.Search
    var words: [String] = []
    var argAccount: String = ""
    var argList: String = ""
    var argRaw: String = ""
    var account: EKSource?
    var list: EKCalendar?
}

func formatDate(date: NSDate) -> String {
    let now = NSDate()
    let formatter = NSDateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    let delta = Int32((date.timeIntervalSince1970 - now.timeIntervalSince1970) / 86400)
    switch delta {
    case 0:
        return "Today"
    case 1:
        return "Tomorrow"
    case 2 ... 9:
        return "\(delta) day later"
    case -1:
        return "Yesterday"
    case -9 ... -2:
        return "\(abs(delta)) day ago"
    default:
        break
    }
    return formatter.stringFromDate(date)
}

func trim(text: String) -> String {
    return text.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceCharacterSet())
}

func getPriorityLabel(priority: Int) -> String {
    switch priority {
    case 1 ... 4:
        return "!!!"
    case 5:
        return " !!"
    case 6 ... 9:
        return "  !"
    default:
        break
    }
    return "   "
}

class AlfredWorkflowReminder {
    var store: EKEventStore
    var context: Context

    init(ctx: Context) {
        store = EKEventStore()
        context = ctx
        if context.argAccount != "" {
            let accounts = getAccountsByName(context.argAccount)
            if accounts.count > 0 {
                context.account = accounts[0]
            }
        }
        if context.argList != "" {
            let lists = getListsByName(context.argList)
            if lists.count > 0 {
                context.list = lists[0]
            }
        }
    }

    func requestAccessForReminder() -> Bool {
        let dsema : dispatch_semaphore_t = dispatch_semaphore_create(0)
        var ok = false
        store.requestAccessToEntityType(EKEntityType.Reminder) {(granted: Bool, err: NSError?) -> Void in
            if granted {
                ok = true
            }
            dispatch_semaphore_signal(dsema)
        }
        dispatch_semaphore_wait(dsema, DISPATCH_TIME_FOREVER)
        return ok
    }

    func getIncompleteReminders() -> [EKReminder] {
        var calendars: [EKCalendar]? = nil
        if context.list != nil {
            calendars = [context.list!]
        } else {
            calendars = getAllLists()
        }
        var reminders: [EKReminder] = []
        let dsema : dispatch_semaphore_t = dispatch_semaphore_create(0)
        let predicate = store.predicateForIncompleteRemindersWithDueDateStarting(nil, ending: nil, calendars: calendars)
        store.fetchRemindersMatchingPredicate(predicate, completion: {(rs) -> Void in
            if rs != nil {
                if self.context.words.count == 0 {
                    reminders = rs!
                } else {
                    reminders = rs!.filter({(r: EKReminder) -> Bool in
                        return self.context.words.filter({(w: String) -> Bool in
                            return r.title.lowercaseString.containsString(w.lowercaseString)
                        }).count > 0
                    })
                }
            }
            dispatch_semaphore_signal(dsema)
        })
        dispatch_semaphore_wait(dsema, DISPATCH_TIME_FOREVER)
        return reminders
    }

    func getAllAccounts() -> [EKSource] {
        return store.sources
    }

    func getAccountsByName(name: String) -> [EKSource] {
        return getAllAccounts().filter({(source: EKSource) -> Bool in
            return source.title.lowercaseString.hasPrefix(name.lowercaseString)
        })
    }
    
    func getSelectedAccount() -> EKSource {
        if self.context.account != nil {
            return self.context.account!
        }
        return getAllAccounts()[0]
    }

    func getAllLists() -> [EKCalendar] {
        return store.calendarsForEntityType(EKEntityType.Reminder).filter({(cal: EKCalendar) -> Bool in
            if self.context.account != nil && cal.source != self.context.account {
                return false
            }
            return true
        })
    }

    func getListsByName(name: String) -> [EKCalendar] {
        return getAllLists().filter({(cal: EKCalendar) -> Bool in
            return cal.title.lowercaseString.hasPrefix(name)
        })
    }
    
    func getSelectedList() -> EKCalendar {
        if self.context.list != nil {
            return self.context.list!
        }
        return self.store.defaultCalendarForNewReminders()
    }
}

func parseArgs(args: [String]) -> Context {
    var ctx = Context()
    for (i, arg) in args.enumerate() {
        if i == 0 {
            continue
        }
        if i == 1 {
            switch arg.lowercaseString {
            case "search":
                ctx.command = CommandType.Search
                break
            case "create":
                ctx.command = CommandType.Create
                break
            default:
                break
            }
            continue
        }
        var tmp: String = ""
        var key: String = ""
        var quote = false
        let chars = arg.characters
        let len = chars.count
        for (j, c) in chars.enumerate() {
            let isLast = (j == len - 1)
            if c == "\"" {
                if !quote {
                    quote = true
                    continue
                }
                switch key {
                case "account":
                    key = ""
                    ctx.argAccount = tmp.lowercaseString
                    break
                case "list":
                    key = ""
                    ctx.argList = tmp.lowercaseString
                    break
                default:
                    ctx.words.append(tmp.lowercaseString)
                    break
                }
                tmp = ""
                quote = false
                continue
            }
            if isLast {
                tmp.append(c)
            }
            if !quote && (c == " " || isLast) {
                tmp = trim(tmp)
                if tmp == "" {
                    continue
                }
                switch key {
                case "account":
                    key = ""
                    ctx.argAccount = tmp.lowercaseString
                    break
                case "list":
                    key = ""
                    ctx.argList = tmp.lowercaseString
                    break
                default:
                    ctx.words.append(tmp.lowercaseString)
                }
                tmp = ""
                continue
            }
            tmp.append(c)
            if tmp.hasPrefix("account:") {
                key = "account"
                tmp = ""
                continue
            }
            if tmp.hasPrefix("list:") {
                key = "list"
                tmp = ""
            }
        }
        ctx.argRaw = arg
    }
    return ctx
}

func getSearchXMLDocument(ctx: Context) -> NSXMLDocument? {
    let awReminder = AlfredWorkflowReminder(ctx: ctx)
    let root = NSXMLElement(name: "items")
    let xml = NSXMLDocument(rootElement: root)
    // Account
    if ctx.words.count > 0 && "account".hasPrefix(ctx.words.last!) {
        for account in awReminder.getAllAccounts() {
            let item = NSXMLElement(name: "item")
            item.addAttribute(
                NSXMLNode.attributeWithName("autocomplete", stringValue: "account:\"\(account.title)\"") as! NSXMLNode
            )
            item.addAttribute(
                NSXMLNode.attributeWithName("valid", stringValue: "no") as! NSXMLNode
            )
            item.addChild(NSXMLElement(name: "title", stringValue: "Account: \(account.title)"))
            item.addChild(NSXMLElement(
                name: "subtitle",
                stringValue: "Select the account"))
            root.addChild(item)
        }
    }
    // List
    if ctx.words.count > 0 && "list".hasPrefix(ctx.words.last!) {
        for list in awReminder.getAllLists() {
            let item = NSXMLElement(name: "item")
            item.addAttribute(
                NSXMLNode.attributeWithName("arg", stringValue: list.calendarIdentifier) as! NSXMLNode
            )
            var autocomplete: String = ""
            if awReminder.context.account != nil {
                autocomplete = "account:\"\(awReminder.context.account!.title)\" "
            }
            autocomplete += "list:\"\(list.title)\""
            item.addAttribute(
                NSXMLNode.attributeWithName("autocomplete", stringValue: autocomplete) as! NSXMLNode
            )
            item.addChild(NSXMLElement(name: "title", stringValue: "List: \(list.title)"))
            item.addChild(NSXMLElement(
                name: "subtitle",
                stringValue: "Open the reminder's list in Reminders.app"))
            root.addChild(item)
        }
    }
    // Reminders
    if root.childCount == 0 {
        for reminder in awReminder.getIncompleteReminders() {
            let item = NSXMLElement(name: "item")
            item.addAttribute(
                NSXMLNode.attributeWithName("arg", stringValue: "x-apple-reminder://" + reminder.calendarItemIdentifier) as! NSXMLNode
            )
            item.addChild(NSXMLElement(name: "title", stringValue: reminder.title))
            item.addChild(NSXMLElement(
                name: "subtitle",
                stringValue: "\(getPriorityLabel(reminder.priority)) Reminder: created at \(formatDate(reminder.creationDate!)) (\(reminder.calendar.title))"))
            root.addChild(item)
        }
    }
    return xml
}

func getCreationXMLDocument(ctx: Context) -> NSXMLDocument? {
    if ctx.words.count == 0 || ctx.words[0] == "" {
        return nil
    }
    let awReminder = AlfredWorkflowReminder(ctx: ctx)
    let root = NSXMLElement(name: "items")
    let xml = NSXMLDocument(rootElement: root)
    let item = NSXMLElement(name: "item")
    let list = awReminder.getSelectedList()
    let text = ctx.words.joinWithSeparator(" ")
    item.addAttribute(
        NSXMLNode.attributeWithName("arg", stringValue: "\(list.calendarIdentifier) \(text)") as! NSXMLNode
    )
    item.addChild(NSXMLElement(name: "title", stringValue: text))
    item.addChild(NSXMLElement(name: "subtitle", stringValue: "Create a new task in \(list.title)"))
    item.addChild(NSXMLElement(name: "icon", stringValue: "icon_add.png"))
    root.addChild(item)
    return xml
}

func run(args: [String]) -> Int32 {
    let ctx = parseArgs(args)
    var xml: NSXMLDocument? = nil
    switch ctx.command {
    case CommandType.Search:
        xml = getSearchXMLDocument(ctx)
        break
    case CommandType.Create:
        xml = getCreationXMLDocument(ctx)
        break
    }
    if xml != nil {
        print(xml!.XMLString)
        return 0
    }
    return 1
}

exit(run(Process.arguments))

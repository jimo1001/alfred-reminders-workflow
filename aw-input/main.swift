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
    let delta = Int32((date.timeIntervalSince1970 - now.timeIntervalSince1970) / 86400)
    switch delta {
    case 0:
        formatter.dateFormat = "'Today' HH:mm"
        break
    case 1:
        formatter.dateFormat = "'Tomorrow' HH:mm"
        break
    case 2 ... 9:
        formatter.dateFormat = "'\(delta) days later'"
        break
    case -1:
        formatter.dateFormat = "'Yesterday' HH:mm"
        break
    case -9 ... -2:
        formatter.dateFormat = "'\(abs(delta)) days ago'"
        break
    default:
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        break
    }
    return formatter.stringFromDate(date)
}

func trim(text: String) -> String {
    return text.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceCharacterSet())
}

func matchRegex(pattern: String, input: String, options: NSRegularExpressionOptions?) -> [String] {
    let options_: NSRegularExpressionOptions = options != nil ? options! : NSRegularExpressionOptions.CaseInsensitive
    do {
        let re = try NSRegularExpression(pattern: pattern, options: options_)
        let nsInput = input as NSString
        let match = re.matchesInString(input, options: [], range: NSMakeRange(0, nsInput.length))
        return match.map({ (res) -> String in
            return nsInput.substringWithRange(res.range)
        })
    } catch _ as NSError {
        return []
    }
}

func getPriorityLabel(priority: Int) -> String {
    switch priority {
    case 1 ... 4:
        return "!!!"
    case 5:
        return "!! "
    case 6 ... 9:
        return "!  "
    default:
        break
    }
    return "   "
}

class AlfredWorkflowReminder {
    var store: EKEventStore
    var context: Context

    init(ctx: Context) {
        self.store = EKEventStore()
        self.context = ctx
        if !context.argAccount.isEmpty {
            let accounts = getAccountsByName(context.argAccount)
            if accounts.count > 0 {
                self.context.account = accounts[0]
            }
        }
        if !context.argList.isEmpty {
            let lists = getListsByName(context.argList)
            if lists.count > 0 {
                context.list = lists[0]
            }
        }
    }

    func requestAccessForReminder() -> Bool {
        if EKEventStore.authorizationStatusForEntityType(EKEntityType.Reminder) == EKAuthorizationStatus.Authorized {
            return true
        }
        let dsema : dispatch_semaphore_t = dispatch_semaphore_create(0)
        var ok = false
        store.requestAccessToEntityType(EKEntityType.Reminder) { (granted: Bool, err: NSError?) -> Void in
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
        store.fetchRemindersMatchingPredicate(predicate, completion: { (rs) -> Void in
            if rs != nil {
                if self.context.words.count == 0 {
                    reminders = rs!
                } else {
                    reminders = rs!.filter({ (r: EKReminder) -> Bool in
                        return !self.context.words.map({ (w: String) -> Bool in
                            let wl = w.lowercaseString
                            return (r.title.lowercaseString.containsString(wl)
                                || r.calendar.title.lowercaseString.containsString(wl)
                                || r.calendar.source.title.lowercaseString.containsString(wl))
                        }).contains(false)
                    })
                }
            }
            dispatch_semaphore_signal(dsema)
        })
        dispatch_semaphore_wait(dsema, DISPATCH_TIME_FOREVER)

        // Sort by 1: Priority, 2: DueDate, 3: CreationDate
        return reminders.sort({ (a: EKReminder, b: EKReminder) -> Bool in
            // Priority
            if a.priority != b.priority {
                return (a.priority == 0 ? 10 : b.priority) < (b.priority == 0 ? 10 : b.priority)
            }
            // DueDate
            if a.dueDateComponents != nil {
                if b.dueDateComponents != nil {
                    let cal = NSCalendar(calendarIdentifier: NSCalendarIdentifierGregorian)!
                    let da = cal.dateFromComponents(a.dueDateComponents!)!
                    let db = cal.dateFromComponents(b.dueDateComponents!)!
                    if (da.compare(db) == NSComparisonResult.OrderedAscending) {
                        return true
                    }
                } else {
                    return true
                }
            } else if b.dueDateComponents != nil {
                return false
            }
            // CreationDate
            return a.creationDate!.compare(b.creationDate!) == NSComparisonResult.OrderedAscending
        })
    }

    func getAllAccounts() -> [EKSource] {
        return store.sources
    }

    func getAccountsByName(name: String) -> [EKSource] {
        return getAllAccounts().filter({ ( source: EKSource) -> Bool in
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
        return store.calendarsForEntityType(EKEntityType.Reminder).filter({ (cal: EKCalendar) -> Bool in
            if self.context.account != nil && cal.source != self.context.account {
                return false
            }
            return true
        })
    }

    func getListsByName(name: String) -> [EKCalendar] {
        return getAllLists().filter({ (cal: EKCalendar) -> Bool in
            return cal.title.lowercaseString.hasPrefix(name.lowercaseString)
        })
    }

    func getSelectedList() -> EKCalendar? {
        if self.context.list != nil {
            return self.context.list
        } else if self.context.account != nil {
            return self.getAllLists().first
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
            let isQuote = c == "\""
            if isQuote || (!quote && (c == " " || isLast)) {
                if isQuote {
                    quote = !quote
                    if quote {
                        continue
                    }
                }
                if isLast {
                    tmp.append(c)
                }
                tmp = trim(tmp)
                if tmp == "" {
                    continue
                }
                switch key {
                case "account":
                    key = ""
                    ctx.argAccount = tmp
                    break
                case "list":
                    key = ""
                    ctx.argList = tmp
                    break
                default:
                    ctx.words.append(tmp)
                    break
                }
                tmp = ""
                continue
            }
            tmp.append(c)
            if tmp.lowercaseString.hasPrefix("ac:") {
                key = "account"
                tmp = ""
                continue
            }
            if tmp.lowercaseString.hasPrefix("ls:") {
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

    let ma = matchRegex("ac:([^ ]*)$", input: ctx.argRaw, options: nil)
    if ma.count > 0 {
        let accounts = ctx.argAccount.isEmpty
            ? awReminder.getAllAccounts()
            : awReminder.getAccountsByName(ctx.argAccount)
        for account in accounts {
            let item = NSXMLElement(name: "item")
            item.addAttribute(
                NSXMLNode.attributeWithName("autocomplete", stringValue: "ac:\"\(account.title)\"") as! NSXMLNode
            )
            item.addAttribute(
                NSXMLNode.attributeWithName("valid", stringValue: "no") as! NSXMLNode
            )
            item.addChild(NSXMLElement(name: "title", stringValue: account.title))
            item.addChild(NSXMLElement(
                name: "subtitle",
                stringValue: "Select the account"))
            item.addChild(NSXMLElement(name: "icon", stringValue: "images/icon_account.png"))
            root.addChild(item)
        }
    }
    // List
    let ml = matchRegex("ls:([^ ])*$", input: ctx.argRaw, options: nil)
    if ml.count > 0 {
        let lists = ctx.argList.isEmpty
            ? awReminder.getAllLists()
            : awReminder.getListsByName(ctx.argList)
        for list in lists {
            let item = NSXMLElement(name: "item")
            item.addAttribute(
                NSXMLNode.attributeWithName("arg", stringValue: list.calendarIdentifier) as! NSXMLNode
            )
            var autocomplete: String = ""
            if awReminder.context.account != nil {
                autocomplete = "ac:\"\(awReminder.context.account!.title)\" "
            }
            autocomplete += "ls:\"\(list.title)\""
            item.addAttribute(
                NSXMLNode.attributeWithName("autocomplete", stringValue: autocomplete) as! NSXMLNode
            )
            item.addChild(NSXMLElement(name: "title", stringValue: "\(list.title) -- \(list.source.title)"))
            item.addChild(NSXMLElement(
                name: "subtitle",
                stringValue: "Display reminders of \(list.source.title)'s \(list.title) with Reminders.app"))
            item.addChild(NSXMLElement(name: "icon", stringValue: "images/icon_list.png"))
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
            var dueAt = ""
            if reminder.dueDateComponents != nil {
                let calendar = NSCalendar.currentCalendar()
                let dueDate = calendar.dateFromComponents(reminder.dueDateComponents!)
                dueAt = "due at \(formatDate(dueDate!)), "
            }
            item.addChild(NSXMLElement(
                name: "subtitle",
                stringValue: "\(getPriorityLabel(reminder.priority)) \(dueAt)created at \(formatDate(reminder.creationDate!)) (\(reminder.calendar.source.title) / \(reminder.calendar.title))"))
            item.addChild(NSXMLElement(name: "icon", stringValue: "images/icon.png"))
            root.addChild(item)
        }
    }
    return xml
}

func getCreationXMLDocument(ctx: Context) -> NSXMLDocument? {
    if ctx.words.count == 0 || ctx.words[0] .isEmpty {
        return nil
    }
    let awReminder = AlfredWorkflowReminder(ctx: ctx)
    let root = NSXMLElement(name: "items")
    let xml = NSXMLDocument(rootElement: root)
    let item = NSXMLElement(name: "item")
    let list = awReminder.getSelectedList()
    let text = ctx.words.joinWithSeparator(" ")
    if list == nil {
        return nil
    }
    item.addAttribute(
        NSXMLNode.attributeWithName("arg", stringValue: "\(list!.calendarIdentifier) \(text)") as! NSXMLNode
    )
    item.addChild(NSXMLElement(name: "title", stringValue: text))
    item.addChild(NSXMLElement(name: "subtitle", stringValue: "Add a reminder to \(list!.source.title)'s \(list!.title)"))
    item.addChild(NSXMLElement(name: "icon", stringValue: "images/icon_add.png"))
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

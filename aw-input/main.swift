//
//  main.swift
//  alfred-reminders-workflow
//
//  Created by @jimo1001 on 2016/05/17.
//  Copyright (c) 2016 @jimo1001 All rights reserved.
//

import Foundation
import EventKit


enum CommandType {
    case search
    case create
}

struct Context {
    var command: CommandType = CommandType.search
    var words: [String] = []
    var argAccount: String = ""
    var argList: String = ""
    var argRaw: String = ""
    var account: EKSource?
    var list: EKCalendar?
}

func formatDate(_ date: Date) -> String {
    let now = Date()
    let formatter = DateFormatter()
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
    return formatter.string(from: date)
}

func trim(_ text: String) -> String {
    return text.trimmingCharacters(in: CharacterSet.whitespaces)
}

func matchRegex(_ pattern: String, input: String, options: NSRegularExpression.Options?) -> [String] {
    let options_: NSRegularExpression.Options = options != nil ? options! : NSRegularExpression.Options.caseInsensitive
    do {
        let re = try NSRegularExpression(pattern: pattern, options: options_)
        let nsInput = input as NSString
        let match = re.matches(in: input, options: [], range: NSMakeRange(0, nsInput.length))
        return match.map({ (res) -> String in
            return nsInput.substring(with: res.range)
        })
    } catch _ as NSError {
        return []
    } catch {
        return []
    }
}

func getPriorityLabel(_ priority: Int) -> String {
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
        if EKEventStore.authorizationStatus(for: EKEntityType.reminder) == EKAuthorizationStatus.authorized {
            return true
        }
        let dsema = DispatchSemaphore(value: 0)
        var ok = false
        store.requestAccess(to: EKEntityType.reminder) { (granted: Bool, err: Error?) -> Void in
            if granted {
                ok = true
            }
            dsema.signal()
        }
        dsema.wait()
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
        let dsema: DispatchSemaphore = DispatchSemaphore(value: 0)
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
        store.fetchReminders(matching: predicate, completion: { (rs) -> Void in
            if rs != nil {
                if self.context.words.count == 0 {
                    reminders = rs!
                } else {
                    reminders = rs!.filter({ (r: EKReminder) -> Bool in
                        return !self.context.words.map({ (w: String) -> Bool in
                            let wl = w.lowercased()
                            return (r.title.lowercased().contains(wl)
                                    || r.calendar.title.lowercased().contains(wl)
                                    || r.calendar.source.title.lowercased().contains(wl))
                        }).contains(false)
                    })
                }
            }
            dsema.signal()
        })
        dsema.wait()

        // Sort by 1: Priority, 2: DueDate, 3: CreationDate
        return reminders.sorted(by: { (a: EKReminder, b: EKReminder) -> Bool in
            // Priority
            if a.priority != b.priority {
                return (a.priority == 0 ? 10 : a.priority) < (b.priority == 0 ? 10 : b.priority)
            }
            // DueDate
            if a.dueDateComponents != nil {
                if b.dueDateComponents != nil {
                    let cal = Calendar(identifier: Calendar.Identifier.gregorian)
                    let da = cal.date(from: a.dueDateComponents!)!
                    let db = cal.date(from: b.dueDateComponents!)!
                    if (da.compare(db) == ComparisonResult.orderedAscending) {
                        return true
                    }
                } else {
                    return true
                }
            } else if b.dueDateComponents != nil {
                return false
            }
            // CreationDate
            return a.creationDate!.compare(b.creationDate!) == ComparisonResult.orderedAscending
        })
    }

    func getAllAccounts() -> [EKSource] {
        return store.sources
    }

    func getAccountsByName(_ name: String) -> [EKSource] {
        return getAllAccounts().filter({ ( source: EKSource) -> Bool in
            return source.title.lowercased().hasPrefix(name.lowercased())
        })
    }

    func getSelectedAccount() -> EKSource {
        if self.context.account != nil {
            return self.context.account!
        }
        return getAllAccounts()[0]
    }

    func getAllLists() -> [EKCalendar] {
        return store.calendars(for: EKEntityType.reminder).filter({ (cal: EKCalendar) -> Bool in
            if self.context.account != nil && cal.source != self.context.account {
                return false
            }
            return true
        })
    }

    func getListsByName(_ name: String) -> [EKCalendar] {
        return getAllLists().filter({ (cal: EKCalendar) -> Bool in
            return cal.title.lowercased().hasPrefix(name.lowercased())
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

func parseArgs(_ args: [String]) -> Context {
    var ctx = Context()
    for (i, arg) in args.enumerated() {
        if i == 0 {
            continue
        }
        if i == 1 {
            switch arg.lowercased() {
            case "search":
                ctx.command = CommandType.search
                break
            case "create":
                ctx.command = CommandType.create
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
        for (j, c) in chars.enumerated() {
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
            if tmp.lowercased().hasPrefix("ac:") {
                key = "account"
                tmp = ""
                continue
            }
            if tmp.lowercased().hasPrefix("ls:") {
                key = "list"
                tmp = ""
            }
        }
        ctx.argRaw = arg
    }
    return ctx
}

func getSearchXMLDocument(_ ctx: Context) -> XMLDocument? {
    let awReminder = AlfredWorkflowReminder(ctx: ctx)
    let root = XMLElement(name: "items")
    let xml = XMLDocument(rootElement: root)
    // Account

    let ma = matchRegex("ac:([^ ]*)$", input: ctx.argRaw, options: nil)
    if ma.count > 0 {
        let accounts = ctx.argAccount.isEmpty
                ? awReminder.getAllAccounts()
                : awReminder.getAccountsByName(ctx.argAccount)
        for account in accounts {
            let item = XMLElement(name: "item")
            item.addAttribute(
                    XMLNode.attribute(withName: "autocomplete", stringValue: "ac:\"\(account.title)\"") as! XMLNode
            )
            item.addAttribute(
                    XMLNode.attribute(withName: "valid", stringValue: "no") as! XMLNode
            )
            item.addChild(XMLElement(name: "title", stringValue: account.title))
            item.addChild(XMLElement(
                    name: "subtitle",
                    stringValue: "Select the account"))
            item.addChild(XMLElement(name: "icon", stringValue: "images/icon_account.png"))
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
            let item = XMLElement(name: "item")
            item.addAttribute(
                    XMLNode.attribute(withName: "arg", stringValue: list.calendarIdentifier) as! XMLNode
            )
            var autocomplete: String = ""
            if awReminder.context.account != nil {
                autocomplete = "ac:\"\(awReminder.context.account!.title)\" "
            }
            autocomplete += "ls:\"\(list.title)\""
            item.addAttribute(
                    XMLNode.attribute(withName: "autocomplete", stringValue: autocomplete) as! XMLNode
            )
            item.addChild(XMLElement(name: "title", stringValue: "\(list.title) -- \(list.source.title)"))
            item.addChild(XMLElement(
                    name: "subtitle",
                    stringValue: "Display reminders of \(list.source.title)'s \(list.title) with Reminders.app"))
            item.addChild(XMLElement(name: "icon", stringValue: "images/icon_list.png"))
            root.addChild(item)
        }
    }
    // Reminders
    if root.childCount == 0 {
        for reminder in awReminder.getIncompleteReminders() {
            let item = XMLElement(name: "item")
            item.addAttribute(
                    XMLNode.attribute(withName: "arg", stringValue: "x-apple-reminder://" + reminder.calendarItemIdentifier) as! XMLNode
            )
            item.addChild(XMLElement(name: "title", stringValue: reminder.title))
            var dueAt = ""
            if reminder.dueDateComponents != nil {
                let calendar = Calendar.current
                let dueDate = calendar.date(from: reminder.dueDateComponents!)
                dueAt = "due at \(formatDate(dueDate!)), "
            }
            item.addChild(XMLElement(
                    name: "subtitle",
                    stringValue: "\(getPriorityLabel(Int(reminder.priority))) \(dueAt)created at \(formatDate(reminder.creationDate!)) (\(reminder.calendar.source.title) / \(reminder.calendar.title))"))
            item.addChild(XMLElement(name: "icon", stringValue: "images/icon.png"))
            root.addChild(item)
        }
    }
    return xml
}

func getCreationXMLDocument(_ ctx: Context) -> XMLDocument? {
    if ctx.words.count == 0 || ctx.words[0].isEmpty {
        return nil
    }
    let awReminder = AlfredWorkflowReminder(ctx: ctx)
    let root = XMLElement(name: "items")
    let xml = XMLDocument(rootElement: root)
    let item = XMLElement(name: "item")
    let list = awReminder.getSelectedList()
    let text = ctx.words.joined(separator: " ")
    if list == nil {
        return nil
    }
    item.addAttribute(
            XMLNode.attribute(withName: "arg", stringValue: "\(list!.calendarIdentifier) \(text)") as! XMLNode
    )
    item.addChild(XMLElement(name: "title", stringValue: text))
    item.addChild(XMLElement(name: "subtitle", stringValue: "Add a reminder to \(list!.source.title)'s \(list!.title)"))
    item.addChild(XMLElement(name: "icon", stringValue: "images/icon_add.png"))
    root.addChild(item)
    return xml
}

func run(_ args: [String]) -> Int32 {
    let ctx = parseArgs(args)
    var xml: XMLDocument? = nil
    switch ctx.command {
    case CommandType.search:
        xml = getSearchXMLDocument(ctx)
        break
    case CommandType.create:
        xml = getCreationXMLDocument(ctx)
        break
    }
    if xml != nil {
        print(xml!.xmlString)
        return 0
    }
    return 1
}

exit(run(CommandLine.arguments))

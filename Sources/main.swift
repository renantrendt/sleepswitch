import AppKit

// Menu-bar app that shows the current `pmset disablesleep` state and lets you switch it.
// Reading needs no privileges. Changing it runs `pmset -a disablesleep <n>` as root:
//   • first via `sudo -n` (silent, once the scoped sudoers rule from enable-nopass.sh is installed)
//   • falling back to the macOS admin-password dialog if that rule isn't present yet.

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var current: Int = 0            // 1 = sleep disabled (stays awake), 0 = normal sleep
    private var busy = false
    private var timer: Timer?

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.delegate = self                 // menuNeedsUpdate rebuilds it fresh each open
        statusItem.menu = menu

        refresh()                            // read + paint the icon now
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()                  // catch changes made elsewhere (e.g. Terminal)
        }
    }

    // MARK: - Reading state (no sudo)

    private func readState() -> Int {
        let out = capture("/usr/bin/pmset", ["-g"])
        for raw in out.split(separator: "\n") {
            let line = String(raw)
            guard line.contains("SleepDisabled") else { continue }
            // grab the trailing integer, e.g. " SleepDisabled\t\t1"
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if let last = parts.last, let v = Int(last) { return v }
        }
        return 0   // line absent → default 0
    }

    private func refresh() {
        current = readState()
        updateIcon()
    }

    private func updateIcon() {
        guard let btn = statusItem.button else { return }
        let awake = current == 1
        let name = awake ? "sun.max.fill" : "moon.zzz.fill"
        let img = NSImage(systemSymbolName: name,
                          accessibilityDescription: awake ? "Sleep disabled" : "Sleep allowed")
        img?.isTemplate = true
        btn.image = img
        btn.imagePosition = .imageOnly       // icon only — no number
        btn.title = ""
        btn.toolTip = awake ? "Never sleeps (sleep disabled)" : "Sleeps normally"
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        current = readState()
        updateIcon()
        menu.removeAllItems()

        let header = NSMenuItem(
            title: current == 1 ? "Never sleeps  (sleep disabled)" : "Sleeps normally",
            action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let never = NSMenuItem(title: "Never sleep", action: #selector(setNever), keyEquivalent: "")
        never.state = current == 1 ? .on : .off
        never.target = self
        never.isEnabled = !busy
        menu.addItem(never)

        let allow = NSMenuItem(title: "Allow sleep", action: #selector(setAllow), keyEquivalent: "")
        allow.state = current == 0 ? .on : .off
        allow.target = self
        allow.isEnabled = !busy
        menu.addItem(allow)

        if busy {
            let b = NSMenuItem(title: "Applying…", action: nil, keyEquivalent: "")
            b.isEnabled = false
            menu.addItem(b)
        }

        if !passwordlessReady() {
            let hint = NSMenuItem(title: "First switch asks for your password once,", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            let hint2 = NSMenuItem(title: "then it's instant forever after.", action: nil, keyEquivalent: "")
            hint2.isEnabled = false
            menu.addItem(.separator())
            menu.addItem(hint)
            menu.addItem(hint2)
        }

        menu.addItem(.separator())
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func setNever() { apply(1) }
    @objc private func setAllow() { apply(0) }
    @objc private func refreshNow() { refresh() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Changing state (root)

    // True once the scoped NOPASSWD sudoers rule is in place (silent toggles).
    private func passwordlessReady() -> Bool {
        run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "1"]) == 0
    }

    private func apply(_ value: Int) {
        if value == current || busy { return }
        busy = true
        updateIcon()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            // 1) silent path — works once the scoped sudoers rule is installed
            var ok = self.run("/usr/bin/sudo",
                              ["-n", "/usr/bin/pmset", "-a", "disablesleep", "\(value)"]) == 0
            // 2) fallback — ONE admin prompt that both applies the change AND installs the
            //    scoped NOPASSWD rule, so this prompt never appears again.
            if !ok {
                ok = self.run("/usr/bin/osascript", ["-e", self.bootstrapScript(value)]) == 0
            }
            _ = ok
            DispatchQueue.main.async {
                self.busy = false
                self.refresh()   // reflects the real value whether it succeeded or was cancelled
            }
        }
    }

    // Builds the one-time bootstrap: validate + install the sudoers rule, then run pmset.
    // The rule permits ONLY `pmset -a disablesleep 0|1` for this user, and is checked with
    // `visudo -cf` before install so a bad file can never break sudo.
    private func bootstrapScript(_ value: Int) -> String {
        let user = NSUserName()
        let safe = user.allSatisfy { $0.isLetter || $0.isNumber || "._-".contains($0) }
        let rule = "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
        var sh = "/usr/bin/pmset -a disablesleep \(value)"
        if safe {
            sh = "t=$(mktemp); echo '\(rule)' > \"$t\"; "
               + "if /usr/sbin/visudo -cf \"$t\" >/dev/null 2>&1; then "
               + "/usr/bin/install -m 0440 -o root -g wheel \"$t\" /etc/sudoers.d/sleepswitch; fi; "
               + "rm -f \"$t\"; " + sh
        }
        let escaped = sh
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }

    // MARK: - Process helpers

    @discardableResult
    private func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    private func capture(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

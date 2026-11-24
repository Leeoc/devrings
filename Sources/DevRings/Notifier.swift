import AppKit
import DevRingsCore
import Observation
@preconcurrency import UserNotifications

/// Posts the ring notices that are due. Called after every refresh, so text is current when it's sent.
@MainActor @Observable
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private(set) var authorization = UNAuthorizationStatus.notDetermined
    /// Opens the menu, or History for the recap, when a notification is clicked.
    var onOpen: (Notice.Kind) -> Void = { _ in }

    private struct Sent: Codable {
        var day: String
        var ids: Set<String>
    }

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        Task { await updateAuthorization() }
    }

    func requestPermission() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        await updateAuthorization()
    }

    func updateAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    func check(_ history: History) {
        guard authorization == .authorized || authorization == .provisional else { return }
        var sent = Storage.load(Sent.self, from: "notifications.json") ?? Sent(day: history.today, ids: [])
        if sent.day != history.today { sent = Sent(day: history.today, ids: []) }
        let due = history.notices(at: .now, sent: sent.ids) { $0.title }
        guard !due.isEmpty else { return }
        for notice in due {
            let content = UNMutableNotificationContent()
            content.title = notice.title
            content.body = notice.body
            content.sound = notice.kind == .closed ? .default : nil
            content.userInfo = ["kind": notice.kind == .recap ? "recap" : "menu"]
            center.add(UNNotificationRequest(identifier: "\(history.today)-\(notice.id)", content: content, trigger: nil))
            sent.ids.formUnion(history.noticeIDsCovered(by: notice))
        }
        try? Storage.save(sent, to: "notifications.json")
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let recap = response.notification.request.content.userInfo["kind"] as? String == "recap"
        await MainActor.run { onOpen(recap ? .recap : .closed) }
    }
}

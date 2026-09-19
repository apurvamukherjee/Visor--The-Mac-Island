import Foundation

enum AppNotificationItem: Identifiable, Equatable, Sendable {
    case message(MessagesMessage)
    case mail(MailMessage)
    case system(SystemNotificationModel)

    var id: String {
        switch self {
        case .message(let message):
            return "msg-\(message.id)"
        case .mail(let mail):
            return "mail-\(mail.rowID)"
        case .system(let notification):
            return "sys-\(notification.id)"
        }
    }

    var receivedDate: Date {
        switch self {
        case .message(let message):
            return message.receivedDate
        case .mail(let mail):
            return mail.receivedDate
        case .system(let notification):
            return notification.receivedDate
        }
    }
}

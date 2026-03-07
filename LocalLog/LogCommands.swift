import Foundation

enum LogCommand {
    static let newEntry = Notification.Name("LogCommand.newEntry")
    static let toggleHistory = Notification.Name("LogCommand.toggleHistory")
    static let toggleFullscreen = Notification.Name("LogCommand.toggleFullscreen")
    static let focusSearch = Notification.Name("LogCommand.focusSearch")
    static let startVideoEntry = Notification.Name("LogCommand.startVideoEntry")
    static let deleteEntry = Notification.Name("LogCommand.deleteEntry")
    static let increaseTextSize = Notification.Name("LogCommand.increaseTextSize")
    static let decreaseTextSize = Notification.Name("LogCommand.decreaseTextSize")
    static let resetTextSize = Notification.Name("LogCommand.resetTextSize")
}

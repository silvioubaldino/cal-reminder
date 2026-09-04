import Foundation

/// Pure formatter for the Banner text (RF-05), on two lines: the Event title, then the
/// time information — `<Title>\nat HH:MM (in X min)`. The explicit break keeps the title
/// and the time apart instead of leaving the split to automatic wrapping. A Reminder at
/// start time (0 minutes, RF-15) reads "starting now" instead of "in 0 min".
enum BannerText {
    static func bannerText(title: String, start: Date, minutesBefore: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let time = formatter.string(from: start)
        let when = minutesBefore == 0 ? "starting now" : "in \(minutesBefore) min"
        return "\(title)\nat \(time) (\(when))"
    }
}

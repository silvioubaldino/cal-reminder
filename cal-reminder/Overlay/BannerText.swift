import Foundation

/// Pure formatter for the Banner text (RF-05), on two lines: the Event title, then the
/// time information — `<Title>\nat HH:MM (in X min)`. The explicit break keeps the title
/// and the time apart instead of leaving the split to automatic wrapping.
enum BannerText {
    static func bannerText(title: String, start: Date, minutesBefore: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let time = formatter.string(from: start)
        return "\(title)\nat \(time) (in \(minutesBefore) min)"
    }
}

import Foundation

/// Pure formatter for the Banner text (RF-05): `<Title> at HH:MM (in X min)`.
enum BannerText {
    static func bannerText(title: String, start: Date, minutesBefore: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let time = formatter.string(from: start)
        return "\(title) at \(time) (in \(minutesBefore) min)"
    }
}

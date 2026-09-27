import Foundation

/// User-facing (Polish) texts for price alerts; used by local notifications and ntfy.
public enum PriceAlertFormatter {
    public static func title(for alert: PriceAlert) -> String {
        let arrow = alert.move.isRise ? "▲" : "▼"
        return "\(alert.asset.name) \(arrow) \(percent(alert.move.changePercent)) w \(window(alert.rule.windowHours))"
    }

    public static func body(for alert: PriceAlert) -> String {
        let currency = (alert.currency ?? alert.asset.currency ?? "").uppercased()
        let suffix = currency.isEmpty ? "" : " \(currency)"
        let reference = alert.move.isRise ? "minimum" : "maksimum"
        return "Cena \(price(alert.move.to.price))\(suffix) (\(reference) w oknie: \(price(alert.move.from.price))\(suffix)). "
            + "Próg reguły: \(percent(alert.rule.thresholdPercent, signed: false)) / \(window(alert.rule.windowHours))."
    }

    /// `+9,2%`, `-10,0%`
    public static func percent(_ value: Double, signed: Bool = true) -> String {
        let sign = signed && value > 0 ? "+" : ""
        return sign + String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",") + "%"
    }

    /// `48 h`, `1,5 h`, `7 dni`
    public static func window(_ hours: Double) -> String {
        if hours >= 72, hours.truncatingRemainder(dividingBy: 24) == 0 {
            return "\(Int(hours / 24)) dni"
        }
        return formatNumber(hours).replacingOccurrences(of: ".", with: ",") + " h"
    }

    /// `65 520,50`, `0,1234`
    public static func price(_ value: Double) -> String {
        let decimals = value >= 100 ? 2 : (value >= 1 ? 3 : 6)
        let raw = String(format: "%.\(decimals)f", value)
        let parts = raw.split(separator: ".", maxSplits: 1)
        var integer = String(parts[0])
        var grouped = ""
        while integer.count > 3 {
            grouped = " " + integer.suffix(3) + grouped
            integer.removeLast(3)
        }
        grouped = integer + grouped
        return parts.count > 1 ? grouped + "," + parts[1] : grouped
    }
}

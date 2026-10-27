import AppKit
import CoreLocation

/// Current conditions via Open-Meteo (no key) for the island header. Location from CoreLocation.
final class WeatherMonitor: NSObject, CLLocationManagerDelegate {
    static let changed = Notification.Name("ClipStackWeatherChanged")
    struct Reading { let tempC: Double; let code: Int; let place: String }
    private(set) var reading: Reading?

    private let lm = CLLocationManager()
    private var timer: Timer?
    private var coord: CLLocationCoordinate2D?
    private var observer: NSObjectProtocol?

    override init() {
        super.init()
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyKilometer
        observer = NotificationCenter.default.addObserver(forName: Settings.changed, object: nil, queue: .main) { [weak self] _ in self?.applyEnabled() }
        applyEnabled()
    }

    private func applyEnabled() {
        timer?.invalidate(); timer = nil
        guard Settings.weatherEnabled else { reading = nil; NotificationCenter.default.post(name: Self.changed, object: self); return }
        lm.requestWhenInUseAuthorization()
        lm.startUpdatingLocation()
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in self?.fetch() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        coord = l.coordinate
        lm.stopUpdatingLocation()
        fetch()
        CLGeocoder().reverseGeocodeLocation(l) { [weak self] p, _ in
            if let name = p?.first?.locality, var r = self?.reading { r = Reading(tempC: r.tempC, code: r.code, place: name); self?.reading = r; NotificationCenter.default.post(name: Self.changed, object: self) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { NSLog("ClipStack: location: \(error.localizedDescription)") }

    private func fetch() {
        guard let c = coord,
              let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(c.latitude)&longitude=\(c.longitude)&current=temperature_2m,weather_code") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let cur = o["current"] as? [String: Any], let t = cur["temperature_2m"] as? Double else { return }
            let code = cur["weather_code"] as? Int ?? 0
            DispatchQueue.main.async {
                self?.reading = Reading(tempC: t, code: code, place: self?.reading?.place ?? "")
                NotificationCenter.default.post(name: Self.changed, object: self)
            }
        }.resume()
    }

    static func symbol(for code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

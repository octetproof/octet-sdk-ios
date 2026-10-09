import SwiftUI
import WebKit
import CoreLocation

/// The three GNSS & Radio Lab "theaters" (3D orbit globe, cell triangulation, and
/// the combined octet-location demo) are self-contained HTML/JS scenes shared
/// **verbatim** with the Android sample (bundled under `web/`). They were written
/// against a tiny `AndroidBridge` (getTle / getLand / close) plus native-pushed
/// setters (setObserver / setFix / setFused / setLive / setTowers).
///
/// On iOS we host them in a `WKWebView` and inject an `AndroidBridge` **shim** at
/// document start, so the exact same HTML runs with no changes: `getTle`/`getLand`
/// return the bundled data, `close` posts back to dismiss. The device fix comes
/// from Core Location (the real OS fused fix). GNSS per-satellite data and cell
/// identities aren't exposed by iOS, so the scenes run in their simulated/estimated
/// mode with a "simulated" badge — honest about the platform limit.
enum Theater: Identifiable {
    case orbit, cell, location

    var id: String { subdir }

    var subdir: String {
        switch self {
        case .orbit: return "web/orbit"
        case .cell: return "web/cell"
        case .location: return "web/location"
        }
    }
    var title: String {
        switch self {
        case .orbit: return "GNSS · Orbits (3D)"
        case .cell: return "Cell · Triangulation"
        case .location: return "octet-location"
        }
    }
}

/// Full-screen theater presented over the Sensors screen. The HTML draws its own
/// "‹ Back" button, which dismisses via the bridge.
struct TheaterView: View {
    let theater: Theater
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TheaterWebView(theater: theater, onClose: { dismiss() })
            .ignoresSafeArea()
            .statusBarHidden(false)
    }
}

struct TheaterWebView: UIViewRepresentable {
    let theater: Theater
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(theater: theater, onClose: onClose) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true

        // AndroidBridge shim + bundled data, injected before the page runs so the
        // shared HTML's `if (window.AndroidBridge)` path works untouched.
        let tle = context.coordinator.readAsset("gnss", "tle", "web/orbit")
        let land = context.coordinator.readAsset("land", "geojson", "web/orbit")
        let shim = """
        window.__TLE__ = \(jsString(tle));
        window.__LAND__ = \(jsString(land));
        window.AndroidBridge = {
          getTle: function(){ return window.__TLE__; },
          getLand: function(){ return window.__LAND__; },
          close: function(){ window.webkit.messageHandlers.bridge.postMessage("close"); }
        };
        """
        let user = WKUserScript(source: shim, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        cfg.userContentController.addUserScript(user)
        cfg.userContentController.add(context.coordinator, name: "bridge")

        let web = WKWebView(frame: .zero, configuration: cfg)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        web.navigationDelegate = context.coordinator
        context.coordinator.web = web

        if let index = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: theater.subdir),
           let root = Bundle.main.url(forResource: "web", withExtension: nil) {
            web.loadFileURL(index, allowingReadAccessTo: root)
        }
        context.coordinator.start()
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, CLLocationManagerDelegate {
        let theater: Theater
        let onClose: () -> Void
        weak var web: WKWebView?
        private let loc = CLLocationManager()
        private var ready = false

        init(theater: Theater, onClose: @escaping () -> Void) {
            self.theater = theater; self.onClose = onClose; super.init()
            loc.delegate = self
            loc.desiredAccuracy = kCLLocationAccuracyBest
        }
        func start() {
            loc.requestWhenInUseAuthorization()
            loc.startUpdatingLocation()
        }

        func readAsset(_ name: String, _ ext: String, _ subdir: String) -> String {
            guard let u = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdir),
                  let s = try? String(contentsOf: u, encoding: .utf8) else { return "" }
            return s
        }

        // MARK: page lifecycle
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            eval("window.showSimulatedBadge && window.showSimulatedBadge(true)")
            pushFix(loc.location)
        }

        // MARK: bridge (close)
        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "bridge" { DispatchQueue.main.async { self.onClose() } }
        }

        // MARK: location → scene
        func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            pushFix(locations.last)
        }
        func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
            if m.authorizationStatus == .authorizedWhenInUse || m.authorizationStatus == .authorizedAlways {
                m.startUpdatingLocation()
            }
        }

        private func pushFix(_ l: CLLocation?) {
            guard ready, let l = l else { return }
            let lat = l.coordinate.latitude, lon = l.coordinate.longitude
            let acc = max(l.horizontalAccuracy, 0)
            switch theater {
            case .orbit:
                eval("window.setObserver(\(lat),\(lon))")
            case .cell:
                eval("window.setFix(\(lat),\(lon),\(acc))")
                eval("window.setTowers('[]')")            // no cell identities on iOS → demo layout
            case .location:
                eval("window.setGnss(\(lat),\(lon),\(acc))")
                eval("window.setFused(\(lat),\(lon),\(acc),'Fused (OS)')")
                eval("window.setLive(0,0)")
                eval("window.setTowers('[]')")
            }
        }
        private func eval(_ js: String) { web?.evaluateJavaScript(js, completionHandler: nil) }
    }
}

/// JSON-encode a Swift string into a safe JS string literal (quoted + escaped).
private func jsString(_ s: String) -> String {
    if let data = try? JSONSerialization.data(withJSONObject: s, options: .fragmentsAllowed),
       let lit = String(data: data, encoding: .utf8) {
        return lit
    }
    return "\"\""
}

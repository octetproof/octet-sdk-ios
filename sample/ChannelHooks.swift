import SwiftUI
import OctetSDK

#if !OCTET_SAMPLE_INTERNAL
/// This app has the Generate and Verify tabs only, so these hooks do nothing.
enum Channel {
    static func logLevel() -> LogLevel { .info }
    static func creditServiceUrl(activationServerUrl: String) -> String? { nil }
    static func glossaryText(for key: String) -> String? { nil }
}

struct ChannelTabs: View {
    var body: some View { EmptyView() }
}

struct ChannelHeaderAccessory: View {
    var body: some View { EmptyView() }
}

struct ChannelGenerateExtras: View {
    var body: some View { EmptyView() }
}

extension View {
    func channelTitleTap() -> some View { self }
    func channelChrome() -> some View { self }
}
#endif

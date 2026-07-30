import SwiftUI

@main
struct UnoClientApp: App {
    @State private var session: SessionStore

    init() {
        #if DEBUG
            TestDrive.seedIfRequested()
        #endif
        let store = SessionStore()
        #if DEBUG
            TestDrive.driveIfRequested(store)
        #endif
        _session = State(initialValue: store)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
        }
    }
}

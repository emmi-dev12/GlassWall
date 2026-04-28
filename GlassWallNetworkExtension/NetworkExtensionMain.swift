// MARK: - Network Extension Entry Point
// NEProvider subclasses are instantiated by the OS — no main() needed.
// This file registers both providers with the extension host.

import NetworkExtension

// The OS discovers these classes via the Info.plist keys
// NSExtension → NSExtensionPrincipalClass for FilterDataProvider, and
// NEFilterDataProviderClass / NEFilterControlProviderClass.
// Both classes are referenced here to ensure the linker includes them.
private let _dataProvider    = FilterDataProvider.self
private let _controlProvider = FilterControlProvider.self

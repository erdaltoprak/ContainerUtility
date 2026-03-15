import SwiftUI

private struct ContainerCLIAdapterEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppDependencies.containerCLIAdapter
}

extension EnvironmentValues {
    var containerCLIAdapter: ContainerCLIAdapter {
        get { self[ContainerCLIAdapterEnvironmentKey.self] }
        set { self[ContainerCLIAdapterEnvironmentKey.self] = newValue }
    }
}

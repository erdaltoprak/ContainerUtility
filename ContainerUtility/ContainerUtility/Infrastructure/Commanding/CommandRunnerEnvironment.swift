import SwiftUI

enum AppDependencies {
    static let commandRunner = CommandRunner()
    static let containerCLIAdapter = ContainerCLIAdapter(commandRunner: commandRunner)
}

private struct CommandRunnerEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppDependencies.commandRunner
}

extension EnvironmentValues {
    var commandRunner: CommandRunner {
        get { self[CommandRunnerEnvironmentKey.self] }
        set { self[CommandRunnerEnvironmentKey.self] = newValue }
    }
}

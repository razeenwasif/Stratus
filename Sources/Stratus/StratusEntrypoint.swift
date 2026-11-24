import Foundation
import SwiftUI

@main
@MainActor
struct StratusEntrypoint {
    static func main() {
        let args = CommandLine.arguments
            .dropFirst()
            .filter { !$0.hasPrefix("-psn_") }

        if args.isEmpty {
            StratusApp.main()
            return
        }

        let code: Int32
        if args.contains("--mcp") {
            code = runMainAsync { await MCPServer.run() }
        } else {
            let cliArgs = Array(args)
            code = runMainAsync { await StratusCLI.run(arguments: cliArgs) }
        }
        exit(code)
    }

    private static func runMainAsync(_ body: @escaping @MainActor () async -> Int32) -> Int32 {
        var exitCode: Int32?
        Task { @MainActor in
            exitCode = await body()
            CFRunLoopStop(CFRunLoopGetMain())
        }
        while exitCode == nil {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        return exitCode ?? 0
    }
}

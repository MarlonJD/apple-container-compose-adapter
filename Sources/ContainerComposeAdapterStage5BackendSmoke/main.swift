// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import ContainerComposeAdapter
import Foundation

@main
struct Stage5BackendSmokeCommand {
    static func main() {
        do {
            let options = try Stage5BackendSmokeCommandOptions.parse(Array(CommandLine.arguments.dropFirst()))
            let result = try Stage5BackendSmokeCommandRunner().run(options: options)
            print(
                "stage5-backend-smoke: wrote \(result.record.dryRuns.count) no-runtime dry-run surface(s) to \(options.evidenceJSONL.path)"
            )
            if options.validateEvidence {
                print("stage5-validation: passed \(result.record.coveredCapabilities.count) capability check(s)")
            }
        } catch Stage5BackendSmokeCommandError.helpRequested {
            print(Stage5BackendSmokeCommandHelp.text)
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            Foundation.exit(64)
        }
    }
}

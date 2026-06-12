// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import ContainerComposeAdapter
import Foundation

@main
struct Stage4MicrobenchmarkPlanCommand {
    static func main() {
        do {
            let options = try Stage4MicrobenchmarkPlanCommandOptions.parse(Array(CommandLine.arguments.dropFirst()))
            let result = try Stage4MicrobenchmarkPlanCommandRunner().run(options: options)
            print(
                "stage4-plan: wrote \(result.plan.probes.count) no-runtime probe(s) to \(options.evidenceJSONL.path)"
            )
            if let operationEvidence = options.operationEvidenceJSONL {
                print(
                    "stage4-operations: wrote \(result.operations.count) no-runtime operation(s) to \(operationEvidence.path)"
                )
            }
            if options.validateEvidence {
                print(
                    "stage4-validation: passed \(result.plan.probes.count) probe(s), \(result.operations.count) operation(s)"
                )
            }
        } catch Stage4MicrobenchmarkPlanCommandError.helpRequested {
            print(Stage4MicrobenchmarkPlanCommandHelp.text)
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            Foundation.exit(64)
        }
    }
}

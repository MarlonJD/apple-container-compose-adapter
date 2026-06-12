// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

public enum RuntimePrerequisiteMessages {
    public static let virtualizationEntitlementMissing = """
    Process lacks com.apple.security.virtualization entitlement required by Virtualization.framework.

    LinuxPod runtime execution must use a signed executable, not plain swift run. Rebuilds can replace the binary and remove the local signature.

    Remediation:
    1. Run swift build.
    2. Run scripts/sign-debug-runtime.sh.
    3. Re-run the signed binary from .build/arm64-apple-macosx/debug/container-compose-adapter with the approved runtime flags.
    """
}

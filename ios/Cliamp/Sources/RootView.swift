import CliampCore
import SwiftUI

/// Placeholder shell. The design system and navigation replace this in
/// phase 1; for now it only proves the target and package wiring.
struct RootView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text(CliampIdentity.displayName)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
            Text("port in progress")
                .font(.system(size: 13, design: .monospaced))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.071, green: 0.039, blue: 0.031))
        .foregroundStyle(Color(red: 0.973, green: 0.894, blue: 0.831))
        .preferredColorScheme(.dark)
    }
}

#Preview {
    RootView()
}

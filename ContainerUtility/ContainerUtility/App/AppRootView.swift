import SwiftUI

struct AppRootView: View {
    @AppStorage(.hasCompletedOnboardingKey) private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                ContentView()
                    .transition(.opacity)
            } else {
                OnboardingView {
                    withAnimation(.snappy(duration: 0.35, extraBounce: 0)) {
                        hasCompletedOnboarding = true
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.snappy(duration: 0.35, extraBounce: 0), value: hasCompletedOnboarding)
    }
}

#Preview {
    AppRootView()
}

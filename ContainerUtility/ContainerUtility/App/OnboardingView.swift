import SwiftUI

struct OnboardingView: View {
    @AppStorage(.showMenuBarExtraKey) private var showMenuBarExtra = true

    @State private var loginLaunchController = LoginLaunchController.shared
    @State private var openAtLogin = LoginLaunchController.shared.isOpenAtLoginEnabled
    @State private var isUpdatingOpenAtLogin = false
    @State private var loginLaunchErrorMessage: String?

    let onContinue: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.12),
                    Color.cyan.opacity(0.08),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    heroCard
                    featureStrip
                    menuBarCard
                    launchCard
                    actionRow
                }
                .frame(maxWidth: 820, alignment: .leading)
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .background(.background)
        .task {
            syncOpenAtLoginState()
        }
        .alert("Open at Login", isPresented: loginLaunchErrorIsPresented) {
            Button("OK", role: .cancel) {
                loginLaunchErrorMessage = nil
            }
        } message: {
            Text(loginLaunchErrorMessage ?? "ContainerUtility could not update the login item setting.")
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.blue.opacity(0.85),
                                    Color.cyan.opacity(0.75)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 72, height: 72)
                .shadow(color: .blue.opacity(0.18), radius: 18, y: 10)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome to ContainerUtility")
                        .font(.system(size: 32, weight: .bold))

                    Text("ContainerUtility gives you a focused dashboard for containers, images, networks, volumes, and runtime health on macOS.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(cardBorder(cornerRadius: 28))
    }

    private var featureStrip: some View {
        HStack(alignment: .top, spacing: 16) {
            OnboardingFeatureCard(
                title: "Inspect Resources",
                detail: "See containers, images, networks, and volumes together without bouncing between tools.",
                systemImage: "shippingbox",
                tint: .blue
            )

            OnboardingFeatureCard(
                title: "Check Runtime Health",
                detail: "Track engine state, compatibility, and preflight results before something turns into a surprise.",
                systemImage: "heart.text.square",
                tint: .green
            )

            OnboardingFeatureCard(
                title: "Review Activity",
                detail: "Keep recent commands and outcomes visible when you need to confirm what changed.",
                systemImage: "clock.arrow.circlepath",
                tint: .cyan
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var menuBarCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.cyan)
                    .frame(width: 32, height: 32)
                    .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Lives in your menu bar")
                        .font(.headline)

                    Text("After setup, click the menu bar icon to reopen ContainerUtility and get back to the full dashboard when you need it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(cardBorder(cornerRadius: 24))
    }

    private var launchCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Launch Behavior")
                .font(.title3.weight(.semibold))

            Text("Open at Login is optional and stays off until you enable it. You can change this later in Settings.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Toggle("Open at Login", isOn: openAtLoginBinding)
                .disabled(isUpdatingOpenAtLogin)

            Text(openAtLoginDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if loginLaunchController.needsApproval {
                Button("Open Login Items Settings") {
                    loginLaunchController.openLoginItemsSettings()
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(cardBorder(cornerRadius: 24))
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)

            Button("Open Dashboard") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var openAtLoginBinding: Binding<Bool> {
        Binding(
            get: { openAtLogin },
            set: { newValue in
                let previousValue = openAtLogin
                openAtLogin = newValue
                isUpdatingOpenAtLogin = true

                Task { @MainActor in
                    defer { isUpdatingOpenAtLogin = false }

                    do {
                        try loginLaunchController.setOpenAtLoginEnabled(newValue)
                        syncOpenAtLoginState()
                    } catch {
                        openAtLogin = previousValue
                        loginLaunchErrorMessage = error.localizedDescription
                    }
                }
            }
        )
    }

    private var loginLaunchErrorIsPresented: Binding<Bool> {
        Binding(
            get: { loginLaunchErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    loginLaunchErrorMessage = nil
                }
            }
        )
    }

    private var openAtLoginDescription: String {
        if loginLaunchController.needsApproval {
            return "macOS needs your approval in System Settings before ContainerUtility can launch automatically."
        }

        if openAtLogin {
            if showMenuBarExtra {
                return "ContainerUtility will launch at login and stay in the menu bar."
            }

            return "ContainerUtility will launch at login and open the main window because the menu bar extra is turned off."
        }

        return "ContainerUtility only launches when you open it yourself."
    }

    private var cardBackground: some ShapeStyle {
        Color.primary.opacity(0.035)
    }

    private func cardBorder(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(.white.opacity(0.08))
    }

    private func syncOpenAtLoginState() {
        loginLaunchController.refreshStatus()
        openAtLogin = loginLaunchController.isOpenAtLoginEnabled
    }
}

private struct OnboardingFeatureCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(title)
                .font(.headline)

            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
    }
}

#Preview {
    OnboardingView {}
}

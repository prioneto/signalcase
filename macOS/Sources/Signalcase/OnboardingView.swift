import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var page = 0

    private let pageCount = 4

    var body: some View {
        VStack(spacing: 0) {
            topBar

            pageContent
                .frame(maxWidth: 920, maxHeight: .infinity)
                .padding(.horizontal, 56)

            footer
        }
        .padding(28)
        .background(
            ZStack {
                SignalTheme.background
                RadialGradient(
                    colors: [SignalTheme.lime.opacity(0.075), .clear],
                    center: .topTrailing,
                    startRadius: 30,
                    endRadius: 520
                )
            }
        )
        .foregroundStyle(SignalTheme.text)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(SignalTheme.lime)
                    .frame(width: 32, height: 32)
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(.black)
            }
            Text("SIGNALCASE")
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .tracking(1.2)

            Spacer()

            HStack(spacing: 6) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? SignalTheme.text : SignalTheme.text.opacity(0.16))
                        .frame(width: index == page ? 22 : 6, height: 6)
                }
            }
            .animation(.easeOut(duration: 0.18), value: page)
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case 0:
            welcomePage
        case 1:
            projectPage
        case 2:
            connectionsPage
        default:
            workflowPage
        }
    }

    private var welcomePage: some View {
        VStack(spacing: 34) {
            Spacer(minLength: 20)

            VStack(spacing: 14) {
                Text("Catch the bug,\nnot the noise.")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .tracking(-1.5)
                    .multilineTextAlignment(.center)
                Text("Signalcase turns failures from the tools you already use into clear, evidence-backed cases your team can fix.")
                    .font(.system(size: 14))
                    .foregroundStyle(SignalTheme.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 580)
            }

            HStack(spacing: 16) {
                onboardingStage(icon: "point.3.connected.trianglepath.dotted", title: "Connect", detail: "Your services", tint: SignalTheme.blue)
                flowArrow
                onboardingStage(icon: "waveform.path.ecg", title: "Detect", detail: "Real failures", tint: SignalTheme.orange)
                flowArrow
                onboardingStage(icon: "checklist", title: "Resolve", detail: "One clear case", tint: SignalTheme.lime)
            }

            Spacer()
        }
    }

    private var projectPage: some View {
        HStack(spacing: 66) {
            onboardingCopy(
                eyebrow: "STEP 1 · PROJECT",
                title: "Show Signalcase where your code lives.",
                body: "Link the project folder you want to monitor. When a failure is detected, Signalcase uses it to point you toward relevant files and lines."
            )

            VStack(spacing: 14) {
                Image(systemName: model.linkedProjectURL == nil ? "folder.badge.plus" : "folder.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(SignalTheme.lime)
                    .frame(width: 72, height: 72)
                    .background(SignalTheme.lime.opacity(0.10), in: RoundedRectangle(cornerRadius: 19))

                VStack(spacing: 5) {
                    Text(model.projectName)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text(model.linkedProjectURL?.path ?? "No project selected")
                        .font(.system(size: 10))
                        .foregroundStyle(SignalTheme.muted)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.center)
                }

                Button(model.linkedProjectURL == nil ? "Choose project folder" : "Choose a different folder") {
                    model.chooseProject()
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())

                Button(model.isCloudBusy ? "Cancel browser sign-in" : (model.isSignedIn ? "Signed in as \(model.cloudEmail ?? "team member")" : "Sign in with GitHub")) {
                    if model.isCloudBusy { model.cancelCloudAuthentication() }
                    else { Task { await model.signInToSignalcase() } }
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())
                .disabled(model.isSignedIn && !model.isCloudBusy)
            }
            .padding(30)
            .frame(width: 340)
            .frame(minHeight: 280)
            .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(SignalTheme.border))
        }
    }

    private var connectionsPage: some View {
        HStack(spacing: 66) {
            onboardingCopy(
                eyebrow: "STEP 2 · CONNECTIONS",
                title: "Bring the evidence together.",
                body: "Connect the services that know what happened. Signalcase reads recent activity when you sync, then keeps only events that look like real failures."
            )

            VStack(spacing: 0) {
                sourceRow("Supabase", icon: "cylinder.fill", color: SignalTheme.lime)
                divider
                sourceRow("Render", icon: "server.rack", color: SignalTheme.purple)
                divider
                sourceRow("Stripe", icon: "creditcard.fill", color: SignalTheme.blue)
                divider
                sourceRow("RevenueCat", icon: "cart.fill", color: SignalTheme.yellow)
                divider
                sourceRow("Sentry + app logs", icon: "waveform.path.ecg", color: SignalTheme.orange)
            }
            .padding(.vertical, 8)
            .frame(width: 340)
            .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(SignalTheme.border))
        }
    }

    private var workflowPage: some View {
        HStack(spacing: 66) {
            onboardingCopy(
                eyebrow: "STEP 3 · WORKFLOW",
                title: "A small workflow for real bugs.",
                body: "Sync logs, open a case, review its timeline and relevant code, then move it forward. No feature backlog and no enterprise process."
            )

            VStack(spacing: 0) {
                ForEach(Array(CaseStatus.allCases.enumerated()), id: \.element.id) { index, status in
                    HStack(spacing: 13) {
                        Circle()
                            .fill(statusColor(status))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(status.title)
                                .font(.system(size: 12, weight: .semibold))
                            Text(status.explanation)
                                .font(.system(size: 9.5))
                                .foregroundStyle(SignalTheme.muted)
                                .lineLimit(2)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 17)
                    .padding(.vertical, 13)

                    if index < CaseStatus.allCases.count - 1 { divider.padding(.leading, 38) }
                }
            }
            .frame(width: 350)
            .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(SignalTheme.border))
        }
    }

    private var footer: some View {
        HStack {
            if page == 0 {
                Button("Skip setup") { model.completeOnboarding() }
                    .buttonStyle(OnboardingTextButtonStyle())
                    .focusEffectDisabled()
            } else {
                Button("Back") { withAnimation { page -= 1 } }
                    .buttonStyle(OnboardingTextButtonStyle())
                    .focusEffectDisabled()
            }

            Spacer()

            if page == pageCount - 1 {
                Button("Finish for now") { model.completeOnboarding() }
                    .buttonStyle(OnboardingTextButtonStyle())
                    .focusEffectDisabled()

                Button("Connect sources") { model.completeOnboarding(openConnections: true) }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .focusEffectDisabled()
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(page == 0 ? "Get started" : "Continue") {
                    withAnimation(.easeOut(duration: 0.18)) { page += 1 }
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .focusEffectDisabled()
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func onboardingCopy(eyebrow: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(eyebrow)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(SignalTheme.lime)
            Text(title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .tracking(-0.8)
                .fixedSize(horizontal: false, vertical: true)
            Text(body)
                .font(.system(size: 13))
                .foregroundStyle(SignalTheme.muted)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 390, alignment: .leading)
    }

    private func onboardingStage(icon: String, title: String, detail: String, tint: Color) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(tint)
            VStack(spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 9)).foregroundStyle(SignalTheme.muted)
            }
        }
        .frame(width: 140, height: 100)
        .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var flowArrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(SignalTheme.muted)
    }

    private func sourceRow(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(SignalTheme.muted)
        }
        .padding(.horizontal, 15)
        .frame(height: 48)
    }

    private var divider: some View {
        Rectangle().fill(SignalTheme.border).frame(height: 1)
    }

    private func statusColor(_ status: CaseStatus) -> Color {
        switch status {
        case .new: SignalTheme.orange
        case .triaged: SignalTheme.yellow
        case .fixing: SignalTheme.blue
        case .verified: SignalTheme.lime
        }
    }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.black.opacity(configuration.isPressed ? 0.65 : 1))
            .padding(.horizontal, 18)
            .frame(height: 40)
            .background(SignalTheme.lime.opacity(configuration.isPressed ? 0.78 : 1), in: RoundedRectangle(cornerRadius: 11))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .focusEffectDisabled()
    }
}

private struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(SignalTheme.text.opacity(configuration.isPressed ? 0.65 : 1))
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(SignalTheme.raised.opacity(configuration.isPressed ? 0.65 : 1), in: RoundedRectangle(cornerRadius: 10))
            .focusEffectDisabled()
    }
}

private struct OnboardingTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(SignalTheme.muted.opacity(configuration.isPressed ? 0.55 : 1))
            .padding(.horizontal, 12)
            .frame(height: 38)
            .contentShape(Rectangle())
            .focusEffectDisabled()
    }
}

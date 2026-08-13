import SwiftUI

struct SessionRestoringView: View {
    var body: some View {
        ZStack {
            SignalTheme.background
                .ignoresSafeArea()

            VStack(spacing: 14) {
                SignalcaseAuthMark(size: 48)
                ProgressView()
                    .controlSize(.small)
                    .tint(SignalTheme.lime)
                Text("Opening Signalcase…")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(SignalTheme.muted)
            }
        }
        .foregroundStyle(SignalTheme.text)
    }
}

struct AuthenticationGateView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            SignalTheme.background
                .ignoresSafeArea()

            RadialGradient(
                colors: [SignalTheme.lime.opacity(0.10), .clear],
                center: .topTrailing,
                startRadius: 30,
                endRadius: 650
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                brand
                Spacer()
                signInCard
                Spacer()
                Text("SIGNALCASE FOR MAC")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(SignalTheme.muted)
            }
            .padding(30)
        }
        .foregroundStyle(SignalTheme.text)
    }

    private var brand: some View {
        HStack(spacing: 10) {
            SignalcaseAuthMark(size: 34)
            Text("SIGNALCASE")
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .tracking(1.2)
            Spacer()
        }
    }

    private var signInCard: some View {
        VStack(spacing: 25) {
            VStack(spacing: 12) {
                Text("Your bugs, in one place.")
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .tracking(-0.8)
                Text("Sign in to keep projects, team connections, and case history attached to the right workspace.")
                    .font(.system(size: 12))
                    .foregroundStyle(SignalTheme.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 410)
            }

            VStack(spacing: 0) {
                authBenefit("folder.fill", "Separate projects", "Each product keeps its own cases and connections.", SignalTheme.lime)
                divider
                authBenefit("person.2.fill", "Ready for your team", "The same workspace can be used across multiple Macs.", SignalTheme.blue)
                divider
                authBenefit("key.fill", "Secure connections", "Provider authorization stays tied to your account.", SignalTheme.purple)
            }
            .background(SignalTheme.raised, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(SignalTheme.border))

            VStack(spacing: 10) {
                Button {
                    if model.isCloudBusy {
                        model.cancelCloudAuthentication()
                    } else {
                        Task { await model.signInToSignalcase() }
                    }
                } label: {
                    HStack(spacing: 11) {
                        if model.isCloudBusy {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.black)
                        } else {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .font(.system(size: 13, weight: .bold))
                        }
                        Text(model.isCloudBusy ? "Cancel browser sign-in" : "Continue with GitHub")
                        Spacer()
                        if !model.isCloudBusy {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 15)
                    .frame(height: 44)
                    .background(SignalTheme.lime, in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(AuthenticationButtonStyle())
                .focusEffectDisabled()
                .keyboardShortcut(.defaultAction)

                Text("New here? Continuing creates your Signalcase account automatically.")
                    .font(.system(size: 9.25))
                    .foregroundStyle(SignalTheme.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(30)
        .frame(width: 500)
        .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(SignalTheme.border))
        .shadow(color: .black.opacity(0.26), radius: 34, y: 18)
    }

    private func authBenefit(_ icon: String, _ title: String, _ detail: String, _ tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(SignalTheme.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 13)
        .frame(height: 56)
    }

    private var divider: some View {
        Rectangle()
            .fill(SignalTheme.border)
            .frame(height: 1)
            .padding(.leading, 53)
    }
}

private struct SignalcaseAuthMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28)
                .fill(SignalTheme.lime)
                .frame(width: size, height: size)
            Image(systemName: "waveform.path.ecg.rectangle.fill")
                .font(.system(size: size * 0.43, weight: .black))
                .foregroundStyle(.black)
        }
    }
}

private struct AuthenticationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

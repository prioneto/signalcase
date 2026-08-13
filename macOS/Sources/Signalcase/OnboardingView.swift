import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var page = 0
    @State private var newProjectName = ""

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
                title: "Create a home for this app.",
                body: "Each project has its own connections, cases, and history. Create one for the product you are working on, or choose an existing project."
            )

            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 9) {
                    Image(systemName: "person.crop.circle.fill.badge.checkmark")
                        .foregroundStyle(SignalTheme.lime)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed in")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(model.cloudEmail ?? "Signalcase account")
                            .font(.system(size: 8.5))
                            .foregroundStyle(SignalTheme.muted)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 11)
                .frame(height: 43)
                .background(SignalTheme.raised, in: RoundedRectangle(cornerRadius: 10))

                if !model.cloudProjects.isEmpty {
                    Text("YOUR PROJECTS")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(SignalTheme.muted)
                    VStack(spacing: 5) {
                        ForEach(model.cloudProjects) { project in
                            Button { model.selectProject(project) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: model.cloudProjectID == project.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(model.cloudProjectID == project.id ? SignalTheme.lime : SignalTheme.muted)
                                    Text(project.name)
                                        .font(.system(size: 10.5, weight: .semibold))
                                    Spacer()
                                }
                                .padding(.horizontal, 11)
                                .frame(height: 36)
                                .background(model.cloudProjectID == project.id ? SignalTheme.raised : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Text("NEW PROJECT")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(SignalTheme.muted)
                HStack(spacing: 8) {
                    TextField("Fitref", text: $newProjectName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .padding(.horizontal, 11)
                        .frame(height: 38)
                        .background(SignalTheme.raised, in: RoundedRectangle(cornerRadius: 10))
                    Button("Create") {
                        Task {
                            if await model.createProject(named: newProjectName) {
                                newProjectName = ""
                            }
                        }
                    }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
                    .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isCloudBusy)
                }
            }
            .padding(22)
            .frame(width: 360)
            .frame(minHeight: 300)
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
                sourceRow("Supabase", detail: "Approve read-only log access in your browser", icon: "cylinder.fill", color: SignalTheme.lime)
                divider
                sourceRow("Render", detail: "Add an API key and choose your services", icon: "server.rack", color: SignalTheme.purple)
                divider
                sourceRow("Application Logs", detail: "Copy a small error-reporting snippet into your app", icon: "terminal.fill", color: SignalTheme.blue)
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
                title: "An inbox that knows when a bug returns.",
                body: "New failures enter your Inbox. Keep real problems Active, resolve them when fixed, and Signalcase will reopen any resolved case that happens again."
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
                .disabled(page == 1 && model.cloudProjectID == nil)
                .opacity(page == 1 && model.cloudProjectID == nil ? 0.45 : 1)
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

    private func sourceRow(_ title: String, detail: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(detail)
                    .font(.system(size: 8.5))
                    .foregroundStyle(SignalTheme.muted)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(SignalTheme.muted)
        }
        .padding(.horizontal, 15)
        .frame(height: 57)
    }

    private var divider: some View {
        Rectangle().fill(SignalTheme.border).frame(height: 1)
    }

    private func statusColor(_ status: CaseStatus) -> Color {
        switch status {
        case .new: SignalTheme.orange
        case .active: SignalTheme.blue
        case .resolved: SignalTheme.lime
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

import AppKit
import SwiftUI

enum SignalTheme {
    static let background = Color(red: 0.095, green: 0.096, blue: 0.089)
    static let sidebar = Color(red: 0.065, green: 0.066, blue: 0.061)
    static let surface = Color.white.opacity(0.055)
    static let raised = Color.white.opacity(0.082)
    static let raisedHover = Color.white.opacity(0.115)
    static let border = Color.white.opacity(0.075)
    static let text = Color.white.opacity(0.92)
    static let muted = Color.white.opacity(0.50)
    static let lime = Color(red: 0.78, green: 0.97, blue: 0.33)
    static let blue = Color(red: 0.34, green: 0.68, blue: 1.00)
    static let orange = Color(red: 1.00, green: 0.42, blue: 0.22)
    static let purple = Color(red: 0.70, green: 0.54, blue: 1.00)
    static let yellow = Color(red: 1.00, green: 0.78, blue: 0.24)
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.isRestoringCloudSession {
                SessionRestoringView()
            } else if !model.isSignedIn {
                AuthenticationGateView()
                    .environmentObject(model)
            } else if model.isOnboardingPresented {
                OnboardingView()
                    .environmentObject(model)
            } else {
                applicationShell
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let toast = model.toastMessage {
                ToastView(message: toast)
                    .padding(20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.toastMessage)
    }

    private var applicationShell: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 216)

            Rectangle().fill(SignalTheme.border).frame(width: 1)

            Group {
                if let item = model.selectedCase {
                    CaseDetailView(item: item)
                        .id(item.id)
                } else {
                    CaseListView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(SignalTheme.background)
        .foregroundStyle(SignalTheme.text)
        .sheet(isPresented: $model.isCapturePresented) {
            CaptureSheet()
                .environmentObject(model)
        }
        .sheet(isPresented: $model.isSettingsPresented) {
            SettingsSheet()
                .environmentObject(model)
        }
        .sheet(isPresented: $model.isFeedbackPresented) {
            FeedbackSheet()
                .environmentObject(model)
        }
    }
}

private struct LegacySidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.top, 24)
                .padding(.horizontal, 18)

            Button { model.isCapturePresented = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 15, weight: .bold))
                    Text("Sync recent logs")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    Spacer()
                    Text("⌘N")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .opacity(0.65)
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(SignalTheme.lime, in: RoundedRectangle(cornerRadius: 15))
                .contentShape(Rectangle())
            }
            .buttonStyle(ScaleButtonStyle())
            .padding(.horizontal, 14)
            .padding(.top, 28)

            Text("CASES")
                .sectionLabel()
                .padding(.horizontal, 20)
                .padding(.top, 26)
                .padding(.bottom, 8)

            VStack(spacing: 3) {
                ForEach(CaseFilter.allCases) { filter in
                    filterButton(filter)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text("PROJECT")
                    .sectionLabel()
                    .padding(.horizontal, 10)

                Menu {
                    ForEach(model.cloudProjects) { project in
                        Button {
                            model.selectProject(project)
                        } label: {
                            if model.cloudProjectID == project.id {
                                Label(project.name, systemImage: "checkmark")
                            } else {
                                Text(project.name)
                            }
                        }
                    }
                    if !model.cloudProjects.isEmpty { Divider() }
                    Button("Create or manage projects…") { model.openSettings(.general) }
                } label: {
                    HStack(spacing: 11) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(SignalTheme.lime.opacity(0.12))
                                .frame(width: 36, height: 36)
                            Image(systemName: "rectangle.stack.fill")
                                .foregroundStyle(SignalTheme.lime)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.projectName)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            Text(model.cloudProjectID == nil ? "Create a project" : "\(model.cases.count) cases")
                                .font(.system(size: 9))
                                .foregroundStyle(SignalTheme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(SignalTheme.muted)
                    }
                    .padding(10)
                    .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .contentShape(Rectangle())
                }
                .buttonStyle(HoverButtonStyle())
                .menuIndicator(.hidden)

                Button { model.openSettings(.connections) } label: {
                    HStack(spacing: 11) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(SignalTheme.blue.opacity(0.12))
                                .frame(width: 36, height: 36)
                            Image(systemName: "point.3.connected.trianglepath.dotted")
                                .foregroundStyle(SignalTheme.blue)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Integrations")
                                .font(.system(size: 11, weight: .semibold))
                            Text("\(model.connectedCount) ready · \(model.rawEvents.count) stored events")
                                .font(.system(size: 9))
                                .foregroundStyle(SignalTheme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(SignalTheme.muted)
                    }
                    .padding(10)
                    .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .contentShape(Rectangle())
                }
                .buttonStyle(HoverButtonStyle())
            }
            .padding(12)
            .padding(.bottom, 8)
        }
        .background(SignalTheme.sidebar)
    }

    private var brand: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(SignalTheme.lime)
                    .frame(width: 38, height: 38)
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.black)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("SIGNALCASE")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .tracking(1.2)
                Text("BUG EVIDENCE, READY")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(SignalTheme.muted)
                    .tracking(0.8)
            }
        }
    }

    private func filterButton(_ filter: CaseFilter) -> some View {
        Button { model.filter = filter } label: {
            HStack(spacing: 11) {
                Image(systemName: filterIcon(filter))
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 18)
                Text(filter.title)
                    .font(.system(size: 11, weight: model.filter == filter ? .semibold : .regular))
                Spacer()
                Text("\(model.count(for: filter))")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(model.filter == filter ? SignalTheme.lime : SignalTheme.muted)
            }
            .foregroundStyle(model.filter == filter ? SignalTheme.text : SignalTheme.muted)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(
                model.filter == filter ? SignalTheme.lime.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 11)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverButtonStyle())
    }

    private func filterIcon(_ filter: CaseFilter) -> String {
        switch filter {
        case .new: "circle"
        case .active: "bolt.fill"
        case .resolved: "checkmark.circle.fill"
        }
    }
}

private struct LegacyCaseListView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.filter.title)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("\(model.filteredCases.count) grouped problems")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(SignalTheme.muted)
                    }
                    Spacer()
                    Circle()
                        .fill(SignalTheme.lime.opacity(0.12))
                        .frame(width: 32, height: 32)
                        .overlay {
                            Circle().fill(SignalTheme.lime).frame(width: 7, height: 7)
                        }
                }

                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(SignalTheme.muted)
                    TextField("Search errors, IDs, files…", text: $model.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 13)
                .frame(height: 42)
                .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 13))
                .overlay {
                    RoundedRectangle(cornerRadius: 13).stroke(SignalTheme.border)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 18)

            Rectangle().fill(SignalTheme.border).frame(height: 1)

            if model.filteredCases.isEmpty {
                VStack(spacing: 13) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 24))
                        .foregroundStyle(SignalTheme.muted)
                    Text("No real cases yet")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Connect a source, then sync recent activity.\nOnly errors and unusual warnings become cases.")
                        .font(.system(size: 10))
                        .foregroundStyle(SignalTheme.muted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                    Button("Open settings") { model.openSettings(.connections) }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.filteredCases) { item in
                            LegacyCaseRow(item: item, isSelected: model.selectedCaseID == item.id) {
                                model.select(item)
                            }
                        }
                    }
                }
            }
        }
        .background(SignalTheme.background)
    }
}

private struct LegacyCaseRow: View {
    let item: SignalCase
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(item.reference)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(SignalTheme.muted)
                    Spacer()
                    Text(relativeDate(item.lastSeen))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(SignalTheme.muted)
                }

                Text(item.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(SignalTheme.text)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                HStack(spacing: 9) {
                    Text(item.status.title.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(statusColor)

                    Text("\(item.occurrenceCount) OCCURRENCES")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SignalTheme.muted)

                    Spacer()

                    SourceStack(sources: item.sources, size: 22)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? SignalTheme.lime.opacity(0.075) : Color.clear)
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle().fill(SignalTheme.lime).frame(width: 3)
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(SignalTheme.border).frame(height: 1).padding(.leading, 20)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverButtonStyle())
    }

    private var statusColor: Color {
        color(for: item.status)
    }
}

private struct CaseDetailView: View {
    @EnvironmentObject private var model: AppModel
    let item: SignalCase
    @State private var confirmDelete = false
    @State private var confirmIgnore = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                detailHeader
                titleBlock
                impactStrip
                findingsSection
                timelineSection
                lowerSection
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.bottom, 40)
        }
        .background(SignalTheme.background)
        .alert("Delete only this case?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete this case", role: .destructive) { model.deleteSelectedCase() }
        } message: {
            Text("This removes \(item.reference) and the events already collected for it. If the error happens again, Signalcase will create a new case. You can restore this one from Event diagnostics.")
        }
        .alert("Mute this error type?", isPresented: $confirmIgnore) {
            Button("Cancel", role: .cancel) {}
            Button("Mute future occurrences", role: .destructive) { model.ignoreSelectedFingerprint() }
        } message: {
            Text("This removes the current case and stops every future occurrence of the same error pattern from creating a case. You can unmute it from Event diagnostics.")
        }
    }

    private var detailHeader: some View {
        HStack(spacing: 12) {
            Button { model.showCaseList() } label: {
                Label("Cases", systemImage: "chevron.left")
                    .compactAction()
            }
            .buttonStyle(HoverButtonStyle())

            Text(item.reference)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(SignalTheme.muted)
            Text("·")
                .foregroundStyle(SignalTheme.muted)
            HStack(spacing: 6) {
                Circle().fill(color(for: item.status)).frame(width: 6, height: 6)
                Text(item.status.title.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(color(for: item.status))
            }
            .help(item.status.explanation)

            Spacer()

            Button { model.copySelectedCase() } label: {
                Label("Copy packet", systemImage: "doc.on.doc")
                    .compactAction()
            }
            .buttonStyle(HoverButtonStyle())

            Menu {
                Button("Mute this error type", systemImage: "speaker.slash") { confirmIgnore = true }
                Divider()
                Button("Delete this case only", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: {
                Image(systemName: "ellipsis")
                    .compactAction()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Button { model.performSelectedCaseAction() } label: {
                HStack(spacing: 8) {
                    Text(item.status.primaryActionTitle)
                    Image(systemName: item.status.actionSystemImage)
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 15)
                .frame(height: 34)
                .background(SignalTheme.lime, in: RoundedRectangle(cornerRadius: 9))
                .contentShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .padding(.top, 18)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(SignalTheme.border).frame(height: 1) }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(item.severity.title)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(severityColor(item.severity))
                Text(item.environment.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(SignalTheme.muted)
            }

            Text(item.title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .tracking(-0.4)
                .lineLimit(3)

            Text(item.summary)
                .font(.system(size: 11.5))
                .foregroundStyle(SignalTheme.muted)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 26)
        .padding(.bottom, 22)
    }

    private var impactStrip: some View {
        HStack(spacing: 20) {
            metric("Occurrences", value: "\(item.occurrenceCount)", icon: "repeat")
            metric("Users", value: "\(item.affectedUsers)", icon: "person.2")
            metric("First seen", value: relativeDate(item.firstSeen), icon: "clock")
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up")
                    .foregroundStyle(SignalTheme.muted)
                SourceStack(sources: item.sources, size: 23)
            }
            Spacer()
        }
        .padding(.vertical, 13)
        .overlay(alignment: .top) { Rectangle().fill(SignalTheme.border).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(SignalTheme.border).frame(height: 1) }
    }

    private var findingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Findings")
                        .font(.system(size: 13, weight: .semibold))
                    Text(item.detectionNote.isEmpty ? "Exact matches and time-based context are labeled separately." : item.detectionNote)
                        .font(.system(size: 9.5))
                        .foregroundStyle(SignalTheme.muted)
                        .lineLimit(1)
                }
                Spacer()
            }

            VStack(spacing: 0) {
                ForEach(Array(item.findings.enumerated()), id: \.element.id) { index, finding in
                    FindingRow(index: index + 1, finding: finding)
                    if index < item.findings.count - 1 {
                        Rectangle().fill(SignalTheme.border).frame(height: 1).padding(.leading, 43)
                    }
                }
            }
            .background(SignalTheme.surface.opacity(0.62), in: RoundedRectangle(cornerRadius: 11))
            .overlay { RoundedRectangle(cornerRadius: 11).stroke(SignalTheme.border) }
        }
        .padding(.top, 28)
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Timeline")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(item.events.count) events")
                    .font(.system(size: 9))
                    .foregroundStyle(SignalTheme.muted)
            }

            VStack(spacing: 0) {
                ForEach(Array(item.events.sorted { $0.timestamp < $1.timestamp }.enumerated()), id: \.element.id) { index, event in
                    EventRow(event: event, showConnector: index < item.events.count - 1)
                }
            }
            .padding(14)
            .background(SignalTheme.surface.opacity(0.38), in: RoundedRectangle(cornerRadius: 11))
        }
        .padding(.top, 28)
    }

    private var lowerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Reproduce")
                .font(.system(size: 13, weight: .semibold))
            ForEach(Array(item.reproduction.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(SignalTheme.lime)
                        .frame(width: 20, height: 20)
                        .background(SignalTheme.lime.opacity(0.09), in: Circle())
                    Text(step)
                        .font(.system(size: 10))
                        .foregroundStyle(SignalTheme.muted)
                        .lineSpacing(2)
                }
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
        .padding(.top, 28)
    }

    private func metric(_ label: String, value: String, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(SignalTheme.muted)
            Text(value)
                .font(.system(size: 10.5, weight: .semibold))
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(SignalTheme.muted)
        }
    }
}

private struct FindingRow: View {
    let index: Int
    let finding: CaseFinding

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: toneIcon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(toneColor)
                .frame(width: 26, height: 26)
                .background(toneColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(finding.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text(finding.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(SignalTheme.muted)
                    .lineSpacing(2)
            }
            Spacer()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
    }

    private var toneColor: Color {
        switch finding.tone {
        case .good: SignalTheme.lime
        case .warning: SignalTheme.yellow
        case .failure: SignalTheme.orange
        case .neutral: SignalTheme.blue
        }
    }

    private var toneIcon: String {
        switch finding.tone {
        case .good: "checkmark.circle.fill"
        case .warning: "clock.fill"
        case .failure: "exclamationmark.triangle.fill"
        case .neutral: "link"
        }
    }
}

private struct EventRow: View {
    let event: LogEvent
    let showConnector: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Text(timeOnly(event.timestamp))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(SignalTheme.muted)
                .frame(width: 66, alignment: .leading)

            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(sourceColor(event.source).opacity(0.14)).frame(width: 31, height: 31)
                    Image(systemName: event.source.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(sourceColor(event.source))
                }
                if showConnector {
                    Rectangle().fill(SignalTheme.border).frame(width: 1, height: 38)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(event.title)
                        .font(.system(size: 11, weight: .semibold))
                    if event.level == .error {
                        Text("ERROR")
                            .font(.system(size: 7, weight: .black, design: .monospaced))
                            .foregroundStyle(SignalTheme.orange)
                    } else if event.level == .deploy {
                        Text("DEPLOY")
                            .font(.system(size: 7, weight: .black, design: .monospaced))
                            .foregroundStyle(SignalTheme.purple)
                    }
                }
                Text(event.detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(SignalTheme.muted)
                    .lineLimit(3)
                if let requestID = event.requestID {
                    Text(requestID)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SignalTheme.blue)
                }
                Text(event.correlation.title.uppercased())
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(event.correlation.isProven ? SignalTheme.lime : event.correlation == .timeWindow ? SignalTheme.yellow : SignalTheme.muted)
            }
            .padding(.top, 6)

            Spacer()

            Text(event.source.title.uppercased())
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(sourceColor(event.source))
                .padding(.top, 8)
        }
        .frame(minHeight: showConnector ? 68 : 48, alignment: .top)
    }
}

private struct CaptureSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = 15
    @State private var selectedSources: Set<LogSource> = [.supabase, .github, .render, .application]

    private let windows = [5, 15, 30, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sync logs")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                    Text("Check recent activity for real failures.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(SignalTheme.muted)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(CircleButtonStyle())
                    .focusEffectDisabled()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Time window").font(.system(size: 11, weight: .semibold))
                Picker("Time window", selection: $minutes) {
                    ForEach(windows, id: \.self) { window in
                        Text(window == 60 ? "1 hour" : "\(window) min").tag(window)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .tint(SignalTheme.lime)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Sources").font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text("\(selectedSources.intersection(model.availableSyncSources).count) selected")
                        .font(.system(size: 9))
                        .foregroundStyle(SignalTheme.muted)
                }

                VStack(spacing: 0) {
                    ForEach([LogSource.supabase, .github, .render, .application]) { source in
                        sourceRow(source)
                        if source != .application {
                            Rectangle().fill(SignalTheme.border).frame(height: 1).padding(.leading, 46)
                        }
                    }
                }
                .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(SignalTheme.border))
            }

            HStack {
                Button { model.importLogs() } label: {
                    Label("Import log file", systemImage: "doc.badge.plus")
                }
                .buttonStyle(QuietButtonStyle())

                Spacer()

                Button {
                    Task {
                        await model.syncRecentLogs(minutes: minutes, sources: selectedSources)
                        guard model.lastSyncReport != nil else { return }
                        model.isCapturePresented = false
                        try? await Task.sleep(for: .milliseconds(220))
                        model.openSettings(.activity)
                    }
                } label: {
                    HStack(spacing: 9) {
                        if model.isCapturing {
                            ProgressView().controlSize(.small).tint(.black)
                        } else {
                            Image(systemName: "waveform.path.ecg")
                        }
                        Text(model.isCapturing ? "Checking…" : "Sync logs")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 17)
                    .frame(height: 38)
                    .background(SignalTheme.lime, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(model.isCapturing || selectedSources.intersection(model.availableSyncSources).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(SignalTheme.background)
        .onAppear {
            selectedSources.formIntersection(model.availableSyncSources)
            if selectedSources.isEmpty { selectedSources = model.availableSyncSources }
        }
    }

    private func sourceRow(_ source: LogSource) -> some View {
        let connected = model.availableSyncSources.contains(source)
        let selected = connected && selectedSources.contains(source)
        return Button {
            guard connected else {
                model.isCapturePresented = false
                Task {
                    try? await Task.sleep(for: .milliseconds(180))
                    model.openSettings(.connections)
                }
                return
            }
            if selected { selectedSources.remove(source) }
            else { selectedSources.insert(source) }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: source.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(sourceColor(source))
                    .frame(width: 24)
                Text(source.title)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text(connected ? (selected ? "Included" : "Not included") : "Set up")
                    .font(.system(size: 9))
                    .foregroundStyle(SignalTheme.muted)
                Image(systemName: connected ? (selected ? "checkmark.circle.fill" : "circle") : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? SignalTheme.lime : SignalTheme.muted)
                    .frame(width: 16)
            }
            .padding(.horizontal, 13)
            .frame(height: 43)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverButtonStyle())
    }
}

private struct SettingsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("Settings")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(SignalTheme.muted)
                            .frame(width: 28, height: 28)
                            .background(SignalTheme.surface, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .help("Close settings")
                    .keyboardShortcut(.cancelAction)
                }
                .padding(.bottom, 22)

                Text("PREFERENCES")
                    .sectionLabel()
                    .padding(.horizontal, 11)
                    .padding(.bottom, 8)

                VStack(spacing: 4) {
                    ForEach(SettingsSection.allCases) { section in
                        settingsButton(section)
                    }
                }

                Spacer()

                Text("SIGNALCASE 0.1")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(SignalTheme.muted)
                    .padding(.horizontal, 10)
            }
            .padding(20)
            .frame(width: 205)
            .background(SignalTheme.sidebar)

            Rectangle().fill(SignalTheme.border).frame(width: 1)

            Group {
                switch model.settingsSection {
                case .general:
                    GeneralSettingsView()
                case .team:
                    TeamSettingsView()
                case .billing:
                    BillingSettingsView()
                case .connections:
                    ConnectionsSettingsView()
                case .activity:
                    DiagnosticsSheet()
                }
            }
            .environmentObject(model)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 940, height: 690)
        .background(SignalTheme.background)
    }

    private func settingsButton(_ section: SettingsSection) -> some View {
        let selected = model.settingsSection == section
        return Button { model.settingsSection = section } label: {
            HStack(spacing: 11) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? SignalTheme.lime : SignalTheme.muted)
                    .frame(width: 18)
                Text(section.title)
                Spacer()
            }
            .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? SignalTheme.text : SignalTheme.muted)
            .padding(.horizontal, 11)
            .frame(height: 40)
            .background(selected ? SignalTheme.raised : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? SignalTheme.border : Color.clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(HoverButtonStyle())
        .focusEffectDisabled()
    }
}

private struct FeedbackSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var kind: FeedbackKind = .bug
    @State private var subject = ""
    @State private var message = ""
    @State private var includeAppDetails = true
    @State private var submissionError: String?
    @State private var isSubmitting = false

    private var canSubmit: Bool {
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("FEEDBACK").sectionLabel()
                    Text("How can we help?")
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                    Text("Choose a type and tell us what happened.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(SignalTheme.muted)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SignalTheme.muted)
                        .frame(width: 30, height: 30)
                        .background(SignalTheme.surface, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(HoverButtonStyle())
                .focusEffectDisabled()
                .keyboardShortcut(.cancelAction)
                .help("Close feedback")
            }

            HStack(spacing: 8) {
                ForEach(FeedbackKind.allCases) { option in
                    feedbackTypeButton(option)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("SUBJECT").sectionLabel()
                TextField(subjectPlaceholder, text: $subject)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 13)
                    .frame(height: 40)
                    .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(SignalTheme.border))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("DETAILS").sectionLabel()
                ZStack(alignment: .topLeading) {
                    if message.isEmpty {
                        Text(kind.prompt)
                            .font(.system(size: 11))
                            .foregroundStyle(SignalTheme.muted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $message)
                        .font(.system(size: 11.5))
                        .scrollContentBackground(.hidden)
                        .padding(5)
                }
                .frame(minHeight: 142)
                .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(SignalTheme.border))
            }

            Toggle(isOn: $includeAppDetails) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include app details")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Adds the Signalcase version, macOS version, project name, and connected source names—not logs or credentials.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(SignalTheme.muted)
                }
            }
            .toggleStyle(.switch)

            if let submissionError {
                Label(submissionError, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(SignalTheme.orange)
            }

            HStack(spacing: 10) {
                Text(model.isSignedIn ? "Feedback is sent to the Signalcase team." : "Sign in to Signalcase before sending.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(SignalTheme.muted)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(QuietButtonStyle())
                if !model.isSignedIn {
                    Button(model.isCloudBusy ? "Signing in…" : "Sign in") {
                        Task { await model.signInToSignalcase() }
                    }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(model.isCloudBusy)
                }
                Button {
                    Task {
                        isSubmitting = true
                        submissionError = nil
                        defer { isSubmitting = false }
                        do {
                            try await model.submitFeedback(
                                kind: kind,
                                subject: subject,
                                message: message,
                                includeAppDetails: includeAppDetails
                            )
                        } catch {
                            submissionError = error.localizedDescription
                        }
                    }
                } label: {
                    if isSubmitting {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text("Sending…")
                        }
                    } else {
                        Label("Send feedback", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSubmit || !model.isSignedIn || isSubmitting)
                .opacity(canSubmit && model.isSignedIn && !isSubmitting ? 1 : 0.42)
            }
        }
        .padding(26)
        .frame(width: 620, height: 580)
        .background(SignalTheme.background)
        .foregroundStyle(SignalTheme.text)
    }

    private var subjectPlaceholder: String {
        switch kind {
        case .bug: "Short summary of the problem"
        case .question: "What do you need help with?"
        case .feature: "Short name for the idea"
        }
    }

    private func feedbackTypeButton(_ option: FeedbackKind) -> some View {
        let selected = kind == option
        return Button {
            kind = option
            submissionError = nil
        } label: {
            HStack(spacing: 9) {
                Image(systemName: option.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? SignalTheme.lime : SignalTheme.muted)
                Text(option.title)
                    .font(.system(size: 10.5, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? SignalTheme.text : SignalTheme.muted)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(selected ? SignalTheme.raised : SignalTheme.surface, in: RoundedRectangle(cornerRadius: 11))
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(selected ? SignalTheme.lime.opacity(0.38) : SignalTheme.border)
            )
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(HoverButtonStyle())
        .focusEffectDisabled()
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var newProjectName = ""
    @State private var isCreatingProject = false
    @State private var isProjectPickerPresented = false
    @State private var confirmsProjectDeletion = false
    @State private var confirmsAccountDeletion = false
    @FocusState private var isProjectNameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("GENERAL").sectionLabel()
                    Text("General")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("Your account, current project, and sync preferences.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(SignalTheme.muted)
                }

                settingsSection("ACCOUNT") {
                    VStack(spacing: 0) {
                        settingsRow(
                            icon: model.isSignedIn ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle",
                            tint: model.isSignedIn ? SignalTheme.lime : SignalTheme.muted,
                            title: model.cloudEmail ?? "Signalcase account",
                            detail: model.isSignedIn ? "Signed in" : "Sign in to use projects and connections",
                            actionTitle: model.isCloudBusy ? "Cancel" : (model.isSignedIn ? "Sign out" : "Sign in")
                        ) {
                            Task {
                                if model.isCloudBusy { model.cancelCloudAuthentication() }
                                else if model.isSignedIn { await model.signOutOfSignalcase() }
                                else { await model.signInToSignalcase() }
                            }
                        }
                    }
                    .settingsSurface()
                }

                settingsSection("PROJECT") {
                    projectManager
                        .settingsSurface()
                }

                settingsSection("SYNC") {
                    VStack(spacing: 0) {
                        HStack(spacing: 13) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(SignalTheme.blue)
                                .frame(width: 28, height: 28)
                                .background(SignalTheme.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Keep connected logs current")
                                    .font(.system(size: 11.5, weight: .semibold))
                                Text("Only checks new activity while Signalcase is open")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(SignalTheme.muted)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { model.automaticSyncEnabled },
                                set: { model.updateAutomaticSync(enabled: $0) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 64)

                        if model.automaticSyncEnabled {
                            rowDivider
                            HStack {
                                Text("Check every")
                                    .font(.system(size: 10.5, weight: .medium))
                                Spacer()
                                Picker("Check every", selection: Binding(
                                    get: { model.automaticSyncIntervalMinutes },
                                    set: { model.updateAutomaticSync(intervalMinutes: $0) }
                                )) {
                                    Text("5 min").tag(5)
                                    Text("15 min").tag(15)
                                    Text("30 min").tag(30)
                                    Text("60 min").tag(60)
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                .frame(width: 260)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 52)
                        }
                    }
                    .settingsSurface()
                }

                settingsSection("HELP") {
                    VStack(spacing: 0) {
                        settingsRow(
                            icon: "sparkles",
                            tint: SignalTheme.yellow,
                            title: "Show onboarding",
                            detail: "Review setup and the case workflow",
                            actionTitle: "Show",
                            action: model.restartOnboarding
                        )
                    }
                    .settingsSurface()
                }

                if model.isSignedIn {
                    settingsSection("DANGER ZONE") {
                        VStack(spacing: 0) {
                            if model.cloudProjectID != nil {
                                settingsRow(
                                    icon: "trash",
                                    tint: SignalTheme.orange,
                                    title: "Delete current project",
                                    detail: "Permanently removes its cases, connections, and team access",
                                    actionTitle: "Delete"
                                ) { confirmsProjectDeletion = true }
                                rowDivider
                            }
                            settingsRow(
                                icon: "person.crop.circle.badge.minus",
                                tint: SignalTheme.orange,
                                title: "Delete account",
                                detail: "Permanently removes your account and workspaces you solely own",
                                actionTitle: "Delete"
                            ) { confirmsAccountDeletion = true }
                        }
                        .settingsSurface()
                    }
                }
            }
            .padding(26)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SignalTheme.background)
        .alert("Delete this project?", isPresented: $confirmsProjectDeletion) {
            Button("Cancel", role: .cancel) {}
            Button("Delete project", role: .destructive) {
                Task { _ = await model.deleteCurrentProject() }
            }
        } message: {
            Text("This permanently deletes the project, shared cases, and provider connections for every teammate.")
        }
        .alert("Delete your Signalcase account?", isPresented: $confirmsAccountDeletion) {
            Button("Cancel", role: .cancel) {}
            Button("Delete account", role: .destructive) {
                Task { _ = await model.deleteAccount() }
            }
        } message: {
            Text("This cannot be undone. Transfer ownership first if a workspace still has other members.")
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).sectionLabel()
            content()
        }
    }

    private var projectManager: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                Image(systemName: model.cloudProjectID == nil ? "rectangle.stack.badge.plus" : "rectangle.stack.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(model.cloudProjectID == nil ? SignalTheme.muted : SignalTheme.lime)
                    .frame(width: 34, height: 34)
                    .background(
                        (model.cloudProjectID == nil ? SignalTheme.muted : SignalTheme.lime).opacity(0.09),
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.projectName)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                    Text(model.isSignedIn
                        ? (model.cloudProjectID == nil ? "Choose or create a project" : "Current project")
                        : "Sign in to use projects")
                        .font(.system(size: 9.25))
                        .foregroundStyle(SignalTheme.muted)
                }
                Spacer()

                if model.isSignedIn, !isCreatingProject {
                    if model.cloudProjects.count > 1 || (model.cloudProjectID == nil && !model.cloudProjects.isEmpty) {
                        projectPickerButton
                    }
                    Button(action: beginCreatingProject) {
                        Image(systemName: "plus")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(SignalTheme.text)
                            .frame(width: 30, height: 30)
                            .background(SignalTheme.raised, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(HoverButtonStyle())
                    .focusEffectDisabled()
                    .help("New project")
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 64)

            if isCreatingProject {
                rowDivider
                projectCreator
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if isProjectPickerPresented {
                rowDivider
                projectPickerPanel
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var projectPickerButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                isProjectPickerPresented.toggle()
            }
        } label: {
            HStack(spacing: 7) {
                Text(model.cloudProjectID == nil ? "Choose" : "Switch")
                    .font(.system(size: 9.5, weight: .semibold))
                Image(systemName: isProjectPickerPresented ? "chevron.up" : "chevron.down")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(SignalTheme.muted)
            }
            .foregroundStyle(SignalTheme.text)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                isProjectPickerPresented ? SignalTheme.raisedHover : SignalTheme.raised,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isProjectPickerPresented ? SignalTheme.lime.opacity(0.32) : SignalTheme.border)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(HoverButtonStyle())
        .focusEffectDisabled()
        .fixedSize()
    }

    private var projectPickerPanel: some View {
        VStack(spacing: 4) {
            ForEach(model.cloudProjects) { project in
                projectPickerOption(project)
            }
        }
        .padding(8)
    }

    private func projectPickerOption(_ project: CloudProject) -> some View {
        let isSelected = model.cloudProjectID == project.id
        return Button {
            guard !isSelected else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                isProjectPickerPresented = false
            }
            model.selectProject(project)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? SignalTheme.lime : SignalTheme.muted)
                    .frame(width: 28, height: 28)
                    .background(
                        (isSelected ? SignalTheme.lime : SignalTheme.muted).opacity(0.09),
                        in: RoundedRectangle(cornerRadius: 8)
                    )

                Text(project.name)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(SignalTheme.text)
                    .lineLimit(1)

                Spacer()

                if isSelected {
                    Text("Current")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(SignalTheme.lime)
                } else {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(SignalTheme.muted)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 42)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? SignalTheme.lime.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(HoverButtonStyle())
        .focusEffectDisabled()
        .disabled(isSelected)
    }

    private var projectCreator: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.stack.badge.plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SignalTheme.muted)
                TextField("Project name", text: $newProjectName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5, weight: .medium))
                    .focused($isProjectNameFocused)
                    .onSubmit(createProject)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(SignalTheme.background, in: RoundedRectangle(cornerRadius: 9))
            .overlay { RoundedRectangle(cornerRadius: 9).stroke(SignalTheme.border) }

            Button("Cancel") {
                withAnimation(.easeOut(duration: 0.16)) {
                    isCreatingProject = false
                    newProjectName = ""
                }
            }
            .buttonStyle(QuietButtonStyle())

            Button(model.isCloudBusy ? "Creating…" : "Create", action: createProject)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(cleanProjectName.isEmpty || model.isCloudBusy)
        }
        .padding(12)
    }

    private var cleanProjectName: String {
        newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func beginCreatingProject() {
        withAnimation(.easeOut(duration: 0.16)) {
            isProjectPickerPresented = false
            isCreatingProject = true
        }
        isProjectNameFocused = true
    }

    private func createProject() {
        let name = cleanProjectName
        guard !name.isEmpty, !model.isCloudBusy else { return }
        Task {
            if await model.createProject(named: name) {
                newProjectName = ""
                withAnimation(.easeOut(duration: 0.16)) {
                    isCreatingProject = false
                }
            }
        }
    }

    private func settingsRow(
        icon: String,
        tint: Color,
        title: String,
        detail: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(SignalTheme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            Button(actionTitle, action: action)
                .buttonStyle(QuietButtonStyle())
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 64)
    }

    private var rowDivider: some View {
        Rectangle().fill(SignalTheme.border).frame(height: 1).padding(.leading, 55)
    }
}

private struct TeamSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var email = ""
    @State private var inviteAsOwner = false

    private var isOwner: Bool { model.cloudTeam?.currentRole == "owner" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("TEAM").sectionLabel()
                    Text("People")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("Everyone in this workspace sees the same cases and statuses.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(SignalTheme.muted)
                }

                if model.cloudProjectID == nil {
                    emptyState("Choose a project to manage its team.")
                } else if let team = model.cloudTeam {
                    if isOwner {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("INVITE").sectionLabel()
                            HStack(spacing: 8) {
                                TextField("teammate@company.com", text: $email)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 12)
                                    .frame(height: 38)
                                    .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(SignalTheme.border))
                                Button(inviteAsOwner ? "Owner" : "Member") { inviteAsOwner.toggle() }
                                    .buttonStyle(QuietButtonStyle())
                                Button(model.isCloudBusy ? "Inviting…" : "Invite") {
                                    Task {
                                        if await model.inviteTeamMember(
                                            email: email,
                                            role: inviteAsOwner ? "owner" : "member"
                                        ) { email = "" }
                                    }
                                }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isCloudBusy)
                            }
                            Text("Creates a seven-day invitation and copies its link.")
                                .font(.system(size: 9.5))
                                .foregroundStyle(SignalTheme.muted)
                        }
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text("MEMBERS").sectionLabel()
                            Spacer()
                            Text("\(team.members.count) of \(team.memberLimit)")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(SignalTheme.muted)
                        }
                        VStack(spacing: 0) {
                            ForEach(Array(team.members.enumerated()), id: \.element.id) { index, member in
                                memberRow(member)
                                if index < team.members.count - 1 { divider }
                            }
                        }
                        .settingsSurface()
                    }

                    if !team.invitations.isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("PENDING").sectionLabel()
                            VStack(spacing: 0) {
                                ForEach(Array(team.invitations.enumerated()), id: \.element.id) { index, invite in
                                    HStack(spacing: 12) {
                                        Image(systemName: "envelope")
                                            .foregroundStyle(SignalTheme.yellow)
                                            .frame(width: 28)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(invite.email).font(.system(size: 11, weight: .semibold))
                                            Text("Invited as \(invite.role)")
                                                .font(.system(size: 9.5)).foregroundStyle(SignalTheme.muted)
                                        }
                                        Spacer()
                                        if isOwner {
                                            Button("Revoke") { Task { await model.revokeInvitation(invite) } }
                                                .buttonStyle(QuietButtonStyle())
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 58)
                                    if index < team.invitations.count - 1 { divider }
                                }
                            }
                            .settingsSurface()
                        }
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(26)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .background(SignalTheme.background)
        .task { await model.refreshTeamAndBilling() }
    }

    private func memberRow(_ member: CloudTeamMember) -> some View {
        HStack(spacing: 12) {
            Image(systemName: member.role == "owner" ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                .font(.system(size: 14))
                .foregroundStyle(member.isCurrentUser ? SignalTheme.lime : SignalTheme.blue)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.email)
                    .font(.system(size: 11, weight: .semibold))
                Text(member.isCurrentUser ? "You · \(member.role.capitalized)" : member.role.capitalized)
                    .font(.system(size: 9.5)).foregroundStyle(SignalTheme.muted)
            }
            Spacer()
            if isOwner, !member.isCurrentUser {
                Button(member.role == "owner" ? "Make member" : "Make owner") {
                    Task { await model.updateMember(member, role: member.role == "owner" ? "member" : "owner") }
                }
                .buttonStyle(QuietButtonStyle())
                Button("Remove") { Task { await model.removeMember(member) } }
                    .buttonStyle(QuietButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 62)
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(SignalTheme.muted)
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var divider: some View { Rectangle().fill(SignalTheme.border).frame(height: 1).padding(.leading, 56) }
}

private struct BillingSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("BILLING").sectionLabel()
                    Text("Signalcase Team")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("One plan for your shared workspace.")
                        .font(.system(size: 10.5)).foregroundStyle(SignalTheme.muted)
                }

                if let billing = model.cloudBilling {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(billing.status.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                Text(billing.access ? "Your workspace is active" : "Subscribe to keep syncing new evidence")
                                    .font(.system(size: 10.5)).foregroundStyle(SignalTheme.muted)
                            }
                            Spacer()
                            Circle().fill(billing.access ? SignalTheme.lime : SignalTheme.orange).frame(width: 9, height: 9)
                        }

                        HStack(spacing: 0) {
                            limit("Members", "\(billing.memberLimit)")
                            limit("Projects", "\(billing.projectLimit)")
                            limit("Event history", "\(billing.eventRetentionDays) days")
                        }

                        if billing.canManage {
                            HStack {
                                if billing.provider == "stripe" {
                                    Button("Manage subscription") { Task { await model.openBillingPortal() } }
                                        .buttonStyle(PrimaryButtonStyle())
                                } else {
                                    Button(billing.configured ? "Subscribe" : "Payments coming soon") {
                                        Task { await model.openCheckout() }
                                    }
                                    .buttonStyle(PrimaryButtonStyle())
                                    .disabled(!billing.configured)
                                }
                                Button("Refresh") { Task { await model.refreshTeamAndBilling() } }
                                    .buttonStyle(QuietButtonStyle())
                            }
                        } else {
                            Text("A workspace owner manages the subscription.")
                                .font(.system(size: 10)).foregroundStyle(SignalTheme.muted)
                        }
                    }
                    .padding(20)
                    .settingsSurface()
                } else if model.cloudProjectID == nil {
                    Text("Choose a project to see its workspace plan.")
                        .font(.system(size: 11)).foregroundStyle(SignalTheme.muted)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(26)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .background(SignalTheme.background)
        .task { await model.refreshTeamAndBilling() }
    }

    private func limit(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: 12, weight: .semibold))
            Text(title).font(.system(size: 9)).foregroundStyle(SignalTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ConnectionsSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedSource: LogSource = .supabase
    @State private var token = ""
    @State private var authorizationHeader = ""
    @State private var signingSecret = ""
    @State private var showsApplicationSetup = false
    @State private var showsLocalApplicationSetup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("CONNECTIONS").sectionLabel()
                Text("Evidence sources")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Connect the places where failures appear.")
                    .font(.system(size: 11))
                    .foregroundStyle(SignalTheme.muted)
            }

            HStack(alignment: .top, spacing: 12) {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.integrations) { integration in
                            Button { selectedSource = integration.source } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: integration.source.systemImage)
                                        .foregroundStyle(sourceColor(integration.source))
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(integration.source.title)
                                            .font(.system(size: 11, weight: .semibold))
                                        Text(stateLabel(integration))
                                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                                            .foregroundStyle(stateColor(integration.state))
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(SignalTheme.muted)
                                }
                                .padding(.horizontal, 11)
                                .frame(height: 44)
                                .background(selectedSource == integration.source ? SignalTheme.raised : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(HoverButtonStyle())
                        }
                    }
                    .padding(6)
                }
                .frame(width: 184)
                .frame(maxHeight: .infinity)
                .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 11))
                .overlay { RoundedRectangle(cornerRadius: 11).stroke(SignalTheme.border) }

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 17) {
                            sourceHeader
                            configurationFields

                            if let error = integration(for: selectedSource)?.errorMessage, !error.isEmpty {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundStyle(SignalTheme.orange)
                                    .padding(11)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(SignalTheme.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                            }
                        }
                        .padding(17)
                    }

                    Rectangle().fill(SignalTheme.border).frame(height: 1)
                    actionBar
                        .padding(14)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 11))
                .overlay { RoundedRectangle(cornerRadius: 11).stroke(SignalTheme.border) }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SignalTheme.background)
        .onChange(of: selectedSource) {
            token = ""
            authorizationHeader = ""
            signingSecret = ""
            showsApplicationSetup = false
            showsLocalApplicationSetup = false
        }
    }

    private var sourceHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: selectedSource.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(sourceColor(selectedSource))
                .frame(width: 38, height: 38)
                .background(sourceColor(selectedSource).opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text(selectedSource == .application ? "Application Logs" : selectedSource.title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text(integration(for: selectedSource)?.detail ?? "")
                    .font(.system(size: 9.5))
                    .foregroundStyle(SignalTheme.muted)
            }
            Spacer()
            if let integration = integration(for: selectedSource) {
                Text(stateLabel(integration))
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(stateColor(integration.state))
                    .padding(.horizontal, 9)
                    .frame(height: 25)
                    .background(stateColor(integration.state).opacity(0.09), in: Capsule())
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            if selectedSource == .application,
               integration(for: .application)?.state == .waitingForEvent {
                Circle().fill(SignalTheme.blue).frame(width: 6, height: 6)
                Text(model.receiverStatus)
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(SignalTheme.muted)
                    .lineLimit(1)
            }
            if selectedSource == .supabase, model.isCloudBusy, model.supabaseProjects.isEmpty {
                Button("Cancel") { model.cancelCloudAuthentication() }
                    .buttonStyle(QuietButtonStyle())
            }
            if selectedSource == .supabase, !model.supabaseProjects.isEmpty {
                Button(model.isChangingSupabaseProject ? "Cancel change" : "Cancel project selection") {
                    model.cancelSupabaseProjectSelection()
                }
                    .buttonStyle(QuietButtonStyle())
            }
            if selectedSource == .github, model.isCloudBusy, model.githubRepositories.isEmpty {
                Button("Cancel") { model.cancelCloudAuthentication() }
                    .buttonStyle(QuietButtonStyle())
            }
            if selectedSource == .github, !model.githubRepositories.isEmpty {
                Button(model.isChangingGitHubRepository ? "Cancel change" : "Cancel repository selection") {
                    model.cancelGitHubRepositorySelection()
                }
                .buttonStyle(QuietButtonStyle())
            }
            if selectedSource == .render, model.isRenderDiscoveryActive {
                Button("Cancel") { model.cancelRenderDiscovery() }
                    .buttonStyle(QuietButtonStyle())
            }
            if let state = integration(for: selectedSource)?.state,
               [.connected, .waitingForEvent].contains(state),
               !(selectedSource == .render && model.isRenderDiscoveryActive) {
                Button("Disconnect") { model.disconnect(selectedSource) }
                    .buttonStyle(QuietButtonStyle())
            }
            Spacer()
            if selectedSource == .supabase,
               model.supabaseProjects.isEmpty,
               integration(for: .supabase)?.state != .connected {
                Button {
                    Task { await model.connectSupabase() }
                } label: {
                    Text(model.isCloudBusy
                        ? "Waiting in browser…"
                        : (integration(for: .supabase)?.state == .connected
                            ? "Reconnect Supabase"
                            : (model.isSignedIn ? "Connect Supabase" : "Sign in & connect")))
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.isCloudBusy)
            } else if selectedSource == .supabase {
                Text("Choose a project above")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(SignalTheme.muted)
            } else if selectedSource == .github {
                if !model.githubRepositories.isEmpty {
                    Text("Choose a repository above")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(SignalTheme.muted)
                } else if integration(for: .github)?.state == .connected {
                    Button {
                        Task { await model.changeGitHubRepository() }
                    } label: {
                        Text(model.isCloudBusy ? "Loading…" : "Change repository")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.isCloudBusy)
                } else {
                    Button {
                        Task { await model.connectGitHub() }
                    } label: {
                        Text(model.isCloudBusy ? "Waiting in browser…" : "Connect GitHub")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.isCloudBusy)
                }
            } else if selectedSource == .render {
                if model.isRenderDiscoveryActive {
                    Button {
                        Task { await model.connectSelectedRenderServices() }
                    } label: {
                        Text(model.isCloudBusy
                            ? "Checking logs…"
                            : "Connect \(model.selectedRenderServiceIDs.count) service\(model.selectedRenderServiceIDs.count == 1 ? "" : "s")")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.isCloudBusy || model.selectedRenderWorkspaceID == nil || model.selectedRenderServiceIDs.isEmpty)
                } else if integration(for: .render)?.state == .connected {
                    Button {
                        Task { await model.discoverRender() }
                    } label: {
                        Text(model.isCloudBusy ? "Refreshing…" : "Change services")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.isCloudBusy)
                } else {
                    Button {
                        Task { await model.discoverRender(token: token) }
                    } label: {
                        Text(model.isCloudBusy ? "Finding services…" : "Find my services")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.isCloudBusy || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else if selectedSource == .application {
                if model.productionApplicationAuthorization.isEmpty {
                    Button {
                        Task { await model.saveConnection(source: .application, token: "") }
                    } label: {
                        Text(model.isCloudBusy ? "Creating…" : "Create endpoint")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.isCloudBusy)
                } else {
                    Text(integration(for: .application)?.state == .connected
                        ? "Receiving application errors"
                        : "Send one error to finish setup")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(SignalTheme.muted)
                }
            } else {
                Button {
                    Task {
                        await model.saveConnection(
                            source: selectedSource,
                            token: token,
                            authorizationHeader: authorizationHeader,
                            signingSecret: signingSecret
                        )
                    }
                } label: {
                    Text("Save & test")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.isCloudBusy)
            }
        }
    }

    @ViewBuilder
    private var configurationFields: some View {
        switch selectedSource {
        case .supabase:
            connectionProgress(
                ["Authorize", "Choose project", "Ready"],
                current: integration(for: .supabase)?.state == .connected
                    ? 3
                    : (model.supabaseProjects.isEmpty ? 0 : 1)
            )
            if model.supabaseProjects.isEmpty {
                if model.selectedSupabaseProject != nil || !model.configuration.supabaseProjectRef.isEmpty {
                    selectedSupabaseProjectCard
                } else {
                    setupPrompt(
                        "Authorize Supabase",
                        "Sign in in your browser, then choose a project.",
                        icon: "arrow.up.right.square.fill",
                        tint: SignalTheme.lime
                    )
                }
            } else {
                compactSection(model.isChangingSupabaseProject ? "Choose another project" : "Choose a project") {
                    ForEach(model.supabaseProjects) { project in
                        supabaseProjectButton(project)
                    }
                }
            }
        case .github:
            connectionProgress(
                ["Install app", "Choose repository", "Ready"],
                current: integration(for: .github)?.state == .connected
                    ? 3
                    : (model.githubRepositories.isEmpty ? 0 : 1)
            )
            if !model.githubRepositories.isEmpty {
                compactSection(model.isChangingGitHubRepository ? "Choose another repository" : "Choose a repository") {
                    ForEach(model.githubRepositories) { repository in
                        githubRepositoryButton(repository)
                    }
                }
            } else if model.selectedGitHubRepository != nil {
                selectedGitHubRepositoryCard
            } else {
                setupPrompt(
                    "Install Signalcase on GitHub",
                    "Choose the repositories Signalcase may read. No token needs to be pasted.",
                    icon: "arrow.up.right.square.fill",
                    tint: SignalTheme.text
                )
            }
        case .render:
            connectionProgress(
                ["API key", "Choose services", "Ready"],
                current: integration(for: .render)?.state == .connected && !model.isRenderDiscoveryActive
                    ? 3
                    : (model.isRenderDiscoveryActive ? 1 : 0)
            )
            if integration(for: .render)?.state == .connected, !model.isRenderDiscoveryActive {
                renderConnectionSummary
            } else if model.isRenderDiscoveryActive {
                if model.renderWorkspaces.count > 1 {
                    compactSection("Workspace") {
                        ForEach(model.renderWorkspaces) { workspace in
                            renderWorkspaceButton(workspace)
                        }
                    }
                } else if let workspace = model.renderWorkspaces.first {
                    selectedValueRow("Workspace", workspace.name, icon: "building.2.fill", tint: SignalTheme.purple)
                }

                compactSection("Services") {
                    if model.renderServicesForSelectedWorkspace.isEmpty {
                        setupResult(
                            model.selectedRenderWorkspaceID == nil
                                ? "Choose a workspace to see its services."
                                : "No services with runtime logs were found in this workspace.",
                            icon: "server.rack",
                            tint: SignalTheme.purple
                        )
                    } else {
                        ForEach(model.renderServicesForSelectedWorkspace) { service in
                            renderServiceButton(service)
                        }
                    }
                }
            } else {
                compactSection("Paste your API key") {
                    VStack(alignment: .leading, spacing: 9) {
                        externalLink("Open Render API keys", "https://dashboard.render.com/u/settings#api-keys")
                        secretField("API KEY", "rnd_…", text: $token)
                    }
                }
            }
        case .application:
            connectionProgress(
                ["Create endpoint", "Add snippet", "Receive error"],
                current: integration(for: .application)?.state == .connected
                    ? 3
                    : (model.productionApplicationAuthorization.isEmpty ? 0 : 1)
            )
            if model.productionApplicationAuthorization.isEmpty {
                setupPrompt(
                    "Create an error endpoint",
                    "Signalcase generates the URL and secret for you.",
                    icon: "antenna.radiowaves.left.and.right",
                    tint: SignalTheme.blue
                )
            } else if integration(for: .application)?.state == .connected, !showsApplicationSetup {
                applicationConnectionSummary
            } else {
                if integration(for: .application)?.state == .connected {
                    HStack {
                        Text("SETUP DETAILS").sectionLabel()
                        Spacer()
                        Button("Hide") {
                            withAnimation(.easeOut(duration: 0.16)) { showsApplicationSetup = false }
                        }
                        .buttonStyle(QuietButtonStyle())
                    }
                }
                compactSection("1. Add these variables") {
                    copyCard("ENVIRONMENT VARIABLES", applicationEnvironment)
                }
                compactSection("2. Send errors") {
                    copyCard("JAVASCRIPT SNIPPET", applicationExample)
                }
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        showsLocalApplicationSetup.toggle()
                    }
                } label: {
                    HStack {
                        Label("Local testing", systemImage: "laptopcomputer")
                        Spacer()
                        Image(systemName: showsLocalApplicationSetup ? "chevron.up" : "chevron.down")
                    }
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(SignalTheme.muted)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if showsLocalApplicationSetup {
                    VStack(spacing: 8) {
                        setupNumberField("PORT", value: $model.configuration.revenueCatPort)
                        copyCard("LOCAL ENDPOINT", localApplicationEndpoint)
                    }
                }
            }
        case .stripe, .revenueCat, .sentry:
            EmptyView()
        }
    }

    private func connectionProgress(_ titles: [String], current: Int) -> some View {
        HStack(spacing: 7) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                let completed = index < current
                let active = index == current
                HStack(spacing: 6) {
                    Group {
                        if completed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 7.5, weight: .bold))
                        } else {
                            Text("\(index + 1)")
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        }
                    }
                    .foregroundStyle(completed || active ? Color.black : SignalTheme.muted)
                    .frame(width: 18, height: 18)
                    .background(
                        completed || active ? SignalTheme.lime : SignalTheme.raised,
                        in: Circle()
                    )

                    Text(title)
                        .font(.system(size: 8.5, weight: active || completed ? .semibold : .regular))
                        .foregroundStyle(active || completed ? SignalTheme.text : SignalTheme.muted)
                        .lineLimit(1)
                }

                if index < titles.count - 1 {
                    Rectangle()
                        .fill(index < current ? SignalTheme.lime.opacity(0.55) : SignalTheme.border)
                        .frame(maxWidth: .infinity)
                        .frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 40)
        .background(SignalTheme.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(SignalTheme.border) }
    }

    private func compactSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).sectionLabel()
            VStack(spacing: 7) { content() }
        }
    }

    private func setupPrompt(_ title: String, _ detail: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(detail)
                    .font(.system(size: 9.25))
                    .foregroundStyle(SignalTheme.muted)
            }
            Spacer()
        }
        .padding(12)
        .background(SignalTheme.raised.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
    }

    private func selectedValueRow(_ label: String, _ value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased()).sectionLabel()
                Text(value)
                    .font(.system(size: 10.5, weight: .semibold))
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(SignalTheme.lime)
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 48)
        .background(SignalTheme.raised.opacity(0.72), in: RoundedRectangle(cornerRadius: 9))
    }

    private var applicationConnectionSummary: some View {
        HStack(spacing: 11) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SignalTheme.lime)
            VStack(alignment: .leading, spacing: 3) {
                Text("Application logs connected")
                    .font(.system(size: 11.5, weight: .semibold))
                Text("Errors are arriving in Signalcase")
                    .font(.system(size: 9.25))
                    .foregroundStyle(SignalTheme.muted)
            }
            Spacer()
            Button("View setup") {
                withAnimation(.easeOut(duration: 0.16)) { showsApplicationSetup = true }
            }
            .buttonStyle(QuietButtonStyle())
        }
        .padding(13)
        .background(SignalTheme.lime.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
        .overlay { RoundedRectangle(cornerRadius: 11).stroke(SignalTheme.lime.opacity(0.16)) }
    }

    private var renderConnectionSummary: some View {
        let services = model.configuration.renderSelectedServices ?? []
        let fallbackCount = model.configuration.renderResourceIDs
            .split(separator: ",")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SignalTheme.lime)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.configuration.renderWorkspaceName ?? "Render workspace")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text("\(services.isEmpty ? fallbackCount : services.count) service\((services.isEmpty ? fallbackCount : services.count) == 1 ? "" : "s") connected")
                        .font(.system(size: 9.25))
                        .foregroundStyle(SignalTheme.muted)
                }
                Spacer()
                Text("SYNCING")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(SignalTheme.lime)
            }

            if !services.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(services.enumerated()), id: \.element.id) { index, service in
                        if index > 0 { Rectangle().fill(SignalTheme.border).frame(height: 1) }
                        HStack(spacing: 10) {
                            Image(systemName: "server.rack")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(SignalTheme.purple)
                                .frame(width: 24, height: 24)
                                .background(SignalTheme.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(service.name)
                                    .font(.system(size: 10.5, weight: .semibold))
                                Text([service.repositoryName, service.branch].compactMap { $0 }.joined(separator: " · ").isEmpty
                                    ? service.typeTitle
                                    : [service.repositoryName, service.branch].compactMap { $0 }.joined(separator: " · "))
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(SignalTheme.muted)
                            }
                            Spacer()
                            Text(service.typeTitle.uppercased())
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundStyle(SignalTheme.muted)
                        }
                        .padding(.horizontal, 11)
                        .frame(minHeight: 48)
                    }
                }
                .background(SignalTheme.background.opacity(0.62), in: RoundedRectangle(cornerRadius: 9))
                .overlay { RoundedRectangle(cornerRadius: 9).stroke(SignalTheme.border) }
            }
        }
        .padding(13)
        .background(SignalTheme.lime.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
        .overlay { RoundedRectangle(cornerRadius: 11).stroke(SignalTheme.lime.opacity(0.16)) }
    }

    private func renderWorkspaceButton(_ workspace: RenderWorkspaceOption) -> some View {
        let selected = model.selectedRenderWorkspaceID == workspace.id
        return Button {
            model.selectRenderWorkspace(workspace.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? SignalTheme.lime : SignalTheme.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(workspace.name)
                        .font(.system(size: 10.5, weight: .semibold))
                    if let email = workspace.email, email != workspace.name {
                        Text(email)
                            .font(.system(size: 8.5))
                            .foregroundStyle(SignalTheme.muted)
                    }
                }
                Spacer()
                let count = model.renderServices.filter { $0.ownerID == workspace.id }.count
                Text("\(count) SERVICE\(count == 1 ? "" : "S")")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(SignalTheme.muted)
            }
            .padding(.horizontal, 11)
            .frame(minHeight: 47)
            .background(selected ? SignalTheme.lime.opacity(0.06) : SignalTheme.background.opacity(0.62), in: RoundedRectangle(cornerRadius: 9))
            .overlay { RoundedRectangle(cornerRadius: 9).stroke(selected ? SignalTheme.lime.opacity(0.22) : SignalTheme.border) }
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(HoverButtonStyle())
        .focusEffectDisabled()
    }

    private func renderServiceButton(_ service: RenderServiceOption) -> some View {
        let selected = model.selectedRenderServiceIDs.contains(service.id)
        return Button {
            model.toggleRenderService(service.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? SignalTheme.lime : SignalTheme.muted)
                Image(systemName: "server.rack")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(SignalTheme.purple)
                    .frame(width: 25, height: 25)
                    .background(SignalTheme.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 3) {
                    Text(service.name)
                        .font(.system(size: 10.5, weight: .semibold))
                    Text(service.repositoryName.map { repository in
                        service.branch.map { "\(repository) · \($0)" } ?? repository
                    } ?? "No linked repository")
                        .font(.system(size: 8.5))
                        .foregroundStyle(SignalTheme.muted)
                }
                Spacer()
                Text(service.typeTitle.uppercased())
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(SignalTheme.muted)
            }
            .padding(.horizontal, 11)
            .frame(minHeight: 51)
            .background(selected ? SignalTheme.lime.opacity(0.055) : SignalTheme.background.opacity(0.62), in: RoundedRectangle(cornerRadius: 9))
            .overlay { RoundedRectangle(cornerRadius: 9).stroke(selected ? SignalTheme.lime.opacity(0.20) : SignalTheme.border) }
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(HoverButtonStyle())
        .focusEffectDisabled()
    }

    private func setupNumberField(_ label: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).sectionLabel()
            TextField("9782", value: value, format: .number).textFieldStyle(.plain)
                .padding(.horizontal, 10).frame(height: 34)
                .background(SignalTheme.raised, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func secretField(_ label: String, _ placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).sectionLabel()
            SecureField(placeholder, text: text).textFieldStyle(.plain)
                .padding(.horizontal, 10).frame(height: 34)
                .background(SignalTheme.raised, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func externalLink(_ title: String, _ value: String) -> some View {
        Button {
            guard let url = URL(string: value) else { return }
            NSWorkspace.shared.open(url)
        } label: {
            Label(title, systemImage: "arrow.up.right")
        }
        .buttonStyle(QuietButtonStyle())
    }

    private func githubRepositoryButton(_ repository: GitHubRepositoryOption) -> some View {
        let isCurrent = model.selectedGitHubRepository?.id == repository.id
        return Button {
            Task { await model.chooseGitHubRepository(repository) }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: repository.isPrivate ? "lock.fill" : "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(SignalTheme.text)
                    .frame(width: 28, height: 28)
                    .background(SignalTheme.text.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(repository.name)
                        .font(.system(size: 11, weight: .semibold))
                    Text("\(repository.owner ?? repository.fullName) · \(repository.defaultBranch)")
                        .font(.system(size: 8.5))
                        .foregroundStyle(SignalTheme.muted)
                        .lineLimit(1)
                }
                Spacer()
                if isCurrent {
                    Label("Current", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(SignalTheme.lime)
                } else {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(SignalTheme.muted)
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 48)
            .background(SignalTheme.raised, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(HoverButtonStyle())
        .focusEffectDisabled()
        .disabled(model.isCloudBusy || isCurrent)
    }

    private var selectedGitHubRepositoryCard: some View {
        let repository = model.selectedGitHubRepository
        return VStack(alignment: .leading, spacing: 9) {
            Text("CONNECTED REPOSITORY").sectionLabel()
            HStack(spacing: 11) {
                Image(systemName: repository?.isPrivate == true ? "lock.fill" : "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SignalTheme.text)
                    .frame(width: 32, height: 32)
                    .background(SignalTheme.text.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    Text(repository?.fullName ?? "GitHub repository")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text("Failed Actions runs are included when logs sync")
                        .font(.system(size: 8.5))
                        .foregroundStyle(SignalTheme.muted)
                }
                Spacer()
                if let url = repository?.htmlUrl {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.up.right")
                    }
                    .buttonStyle(QuietButtonStyle())
                }
            }
        }
        .padding(12)
        .background(SignalTheme.raised, in: RoundedRectangle(cornerRadius: 10))
    }

    private func supabaseProjectButton(_ project: SupabaseProjectOption) -> some View {
        let isCurrent = model.selectedSupabaseProject?.ref == project.ref
        return Button {
            Task { await model.chooseSupabaseProject(project) }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "cylinder.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SignalTheme.lime)
                    .frame(width: 28, height: 28)
                    .background(SignalTheme.lime.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.name)
                        .font(.system(size: 11, weight: .semibold))
                    Text([project.organizationSlug, project.region]
                        .compactMap { $0 }
                        .joined(separator: " · "))
                        .font(.system(size: 8.5))
                        .foregroundStyle(SignalTheme.muted)
                }
                Spacer()
                if isCurrent {
                    Label("Current", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(SignalTheme.lime)
                } else {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(SignalTheme.muted)
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 48)
            .background(SignalTheme.raised, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(HoverButtonStyle())
        .focusEffectDisabled()
        .disabled(model.isCloudBusy || isCurrent)
    }

    private var selectedSupabaseProjectCard: some View {
        let project = model.selectedSupabaseProject
        let projectRef = project?.ref ?? model.configuration.supabaseProjectRef
        let projectName = project?.name ?? projectRef
        let details = [project?.organizationSlug, project?.region]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        return VStack(alignment: .leading, spacing: 9) {
            Text("CONNECTED PROJECT").sectionLabel()
            HStack(spacing: 11) {
                Image(systemName: "cylinder.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SignalTheme.lime)
                    .frame(width: 32, height: 32)
                    .background(SignalTheme.lime.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    Text(projectName.isEmpty ? "Supabase project" : projectName)
                        .font(.system(size: 11.5, weight: .semibold))
                    Text(details.isEmpty ? projectRef : details)
                        .font(.system(size: 8.5))
                        .foregroundStyle(SignalTheme.muted)
                        .lineLimit(1)
                    if !projectRef.isEmpty, projectRef != projectName {
                        Text(projectRef)
                            .font(.system(size: 7.5, design: .monospaced))
                            .foregroundStyle(SignalTheme.muted.opacity(0.75))
                            .lineLimit(1)
                    }
                }
                Spacer()
                Button("Change") {
                    Task { await model.changeSupabaseProject() }
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(model.isCloudBusy)
            }
        }
        .padding(12)
        .background(SignalTheme.raised, in: RoundedRectangle(cornerRadius: 10))
    }

    private func setupResult(_ text: String, icon: String, tint: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 9.25))
            .foregroundStyle(SignalTheme.muted)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private func copyCard(_ label: String, _ value: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            model.showToast("Copied to clipboard")
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(label).sectionLabel()
                    Spacer()
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(SignalTheme.blue)
                }
                Text(value)
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(SignalTheme.text.opacity(0.78))
                    .multilineTextAlignment(.leading)
                    .lineLimit(6)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SignalTheme.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(SignalTheme.border))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(HoverButtonStyle())
        .focusEffectDisabled()
    }

    private var applicationEndpoint: String {
        model.productionApplicationEndpoint.isEmpty
            ? "Create the endpoint to reveal its URL"
            : model.productionApplicationEndpoint
    }

    private var localApplicationEndpoint: String {
        "http://127.0.0.1:\(model.configuration.revenueCatPort)/events"
    }

    private var applicationAuthorization: String {
        model.productionApplicationAuthorization.isEmpty
            ? "Bearer YOUR_GENERATED_SECRET"
            : model.productionApplicationAuthorization
    }

    private var applicationEnvironment: String {
        "SIGNALCASE_EVENTS_URL=\(applicationEndpoint)\nSIGNALCASE_AUTHORIZATION=\(applicationAuthorization)"
    }

    private var applicationExample: String {
        """
        await fetch(process.env.SIGNALCASE_EVENTS_URL, {
          method: "POST",
          headers: { "Content-Type": "application/json",
            "Authorization": process.env.SIGNALCASE_AUTHORIZATION },
          body: JSON.stringify({ level: "error", title: error.name,
            message: error.message, request_id: requestId,
            user_id: userId, route: request.url,
            timestamp: new Date().toISOString() })
        });
        """
    }

    private func integration(for source: LogSource) -> Integration? {
        model.integrations.first { $0.source == source }
    }

    private func stateLabel(_ integration: Integration) -> String {
        if integration.source == .supabase, !model.supabaseProjects.isEmpty {
            return "CHOOSE A PROJECT"
        }
        if integration.source == .github, !model.githubRepositories.isEmpty {
            return "CHOOSE A REPOSITORY"
        }
        if integration.source == .render, model.isRenderDiscoveryActive {
            return "CHOOSE SERVICES"
        }
        return switch integration.state {
        case .connected: integration.eventCount > 0 ? "CONNECTED · \(integration.eventCount) EVENTS" : "CONNECTED"
        case .waitingForEvent: "WAITING FOR WEBHOOK"
        case .syncing: "CHECKING…"
        case .failed: "NEEDS ATTENTION"
        case .disconnected, .available: "NOT SET UP"
        }
    }

    private func stateColor(_ state: IntegrationState) -> Color {
        switch state {
        case .connected: SignalTheme.lime
        case .syncing, .waitingForEvent, .available: SignalTheme.blue
        case .failed: SignalTheme.orange
        default: SignalTheme.muted
        }
    }
}

private struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 28))
                .foregroundStyle(SignalTheme.muted)
            Text("Select a case")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text("Related logs and proven findings will appear here.")
                .font(.system(size: 10))
                .foregroundStyle(SignalTheme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SignalTheme.background)
    }
}

private struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(SignalTheme.lime).frame(width: 7, height: 7)
            Text(message)
                .font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 15)
        .frame(height: 42)
        .background(SignalTheme.raised, in: Capsule())
        .overlay { Capsule().stroke(SignalTheme.border) }
        .shadow(color: .black.opacity(0.3), radius: 14, y: 8)
    }
}

private struct SourceStack: View {
    let sources: [LogSource]
    let size: CGFloat

    var body: some View {
        HStack(spacing: -5) {
            ForEach(sources.prefix(5)) { source in
                ZStack {
                    Circle().fill(SignalTheme.raised)
                    Circle().stroke(SignalTheme.background, lineWidth: 2)
                    Text(source.shortTitle)
                        .font(.system(size: size * 0.27, weight: .black, design: .monospaced))
                        .foregroundStyle(sourceColor(source))
                }
                .frame(width: size, height: size)
            }
        }
    }
}

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct HoverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverButtonBody(configuration: configuration)
    }

    private struct HoverButtonBody: View {
        let configuration: ButtonStyle.Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .brightness(hovering ? 0.025 : 0)
                .opacity(configuration.isPressed ? 0.72 : 1)
                .animation(.easeOut(duration: 0.12), value: hovering)
                .onHover { value in
                    hovering = value
                    value ? NSCursor.pointingHand.set() : NSCursor.arrow.set()
                }
        }
    }
}

private struct CircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(SignalTheme.muted)
            .frame(width: 28, height: 28)
            .background(configuration.isPressed ? SignalTheme.raised : SignalTheme.surface, in: Circle())
            .contentShape(Circle())
            .focusEffectDisabled()
    }
}

private struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(SignalTheme.text.opacity(0.76))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(configuration.isPressed ? SignalTheme.raisedHover : SignalTheme.surface, in: RoundedRectangle(cornerRadius: 9))
            .focusEffectDisabled()
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 15)
            .frame(height: 34)
            .background(SignalTheme.lime.opacity(configuration.isPressed ? 0.78 : 1), in: RoundedRectangle(cornerRadius: 9))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .focusEffectDisabled()
    }
}

private extension View {
    func sectionLabel() -> some View {
        font(.system(size: 8, weight: .black, design: .monospaced))
            .foregroundStyle(SignalTheme.muted)
            .tracking(1.1)
    }

    func compactAction() -> some View {
        font(.system(size: 9, weight: .semibold))
            .foregroundStyle(SignalTheme.text)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    func settingsSurface() -> some View {
        background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(SignalTheme.border) }
    }
}

private func color(for status: CaseStatus) -> Color {
    switch status {
    case .new: SignalTheme.orange
    case .active: SignalTheme.blue
    case .resolved: SignalTheme.lime
    }
}

private func severityColor(_ severity: CaseSeverity) -> Color {
    switch severity {
    case .critical: SignalTheme.orange
    case .high: SignalTheme.yellow
    case .normal: SignalTheme.muted
    }
}

private func sourceColor(_ source: LogSource) -> Color {
    switch source {
    case .supabase: SignalTheme.lime
    case .github: SignalTheme.text
    case .stripe: SignalTheme.purple
    case .render: SignalTheme.blue
    case .revenueCat: SignalTheme.yellow
    case .sentry: SignalTheme.orange
    case .application: SignalTheme.text
    }
}

private func relativeDate(_ date: Date) -> String {
    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    if seconds < 60 { return "now" }
    if seconds < 3_600 { return "\(seconds / 60)m ago" }
    if seconds < 86_400 { return "\(seconds / 3_600)h ago" }
    return "\(seconds / 86_400)d ago"
}

private func timeOnly(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: date)
}

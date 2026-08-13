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

            Text("INBOX")
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
        case .inbox: "tray.fill"
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
    @State private var selectedSources: Set<LogSource> = [.supabase, .render, .application]

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
                    ForEach([LogSource.supabase, .render, .application]) { source in
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
                .padding(.bottom, 24)

                VStack(spacing: 5) {
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
            .frame(height: 38)
            .background(selected ? SignalTheme.surface : Color.clear, in: RoundedRectangle(cornerRadius: 10))
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("GENERAL").sectionLabel()
                    Text("Settings")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("Workspace and app preferences")
                        .font(.system(size: 10.5))
                        .foregroundStyle(SignalTheme.muted)
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("WORKSPACE").sectionLabel()
                    VStack(spacing: 0) {
                        settingsRow(
                            icon: model.isSignedIn ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle",
                            tint: model.isSignedIn ? SignalTheme.lime : SignalTheme.muted,
                            title: model.cloudEmail ?? "Signalcase account",
                            detail: model.isSignedIn ? "Signed in · team connections are available" : "Sign in to connect team services securely",
                            actionTitle: model.isCloudBusy ? "Cancel" : (model.isSignedIn ? "Sign out" : "Sign in")
                        ) {
                            Task {
                                if model.isCloudBusy { model.cancelCloudAuthentication() }
                                else if model.isSignedIn { await model.signOutOfSignalcase() }
                                else { await model.signInToSignalcase() }
                            }
                        }
                        rowDivider
                        projectManager
                        rowDivider
                        settingsRow(
                            icon: "point.3.connected.trianglepath.dotted",
                            tint: SignalTheme.blue,
                            title: model.connectedCount == 1 ? "1 connection" : "\(model.connectedCount) connections",
                            detail: "Supabase, Render, and Application Logs",
                            actionTitle: "Manage"
                        ) { model.settingsSection = .connections }
                        rowDivider
                        settingsRow(
                            icon: "list.bullet.rectangle",
                            tint: SignalTheme.purple,
                            title: "Activity & data",
                            detail: model.lastSyncReport?.summary ?? "No sync activity yet",
                            actionTitle: "Open"
                        ) { model.settingsSection = .activity }
                    }
                    .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("AUTOMATIC SYNC").sectionLabel()
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
                    .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("HELP").sectionLabel()
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
                    .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(26)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SignalTheme.background)
    }

    private var projectManager: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 13) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SignalTheme.lime)
                    .frame(width: 28, height: 28)
                    .background(SignalTheme.lime.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Projects")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text("Each project keeps separate cases, connections, and history")
                        .font(.system(size: 9.5))
                        .foregroundStyle(SignalTheme.muted)
                }
            }

            if model.isSignedIn {
                HStack(spacing: 7) {
                    ForEach(model.cloudProjects) { project in
                        Button {
                            model.selectProject(project)
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(model.cloudProjectID == project.id ? SignalTheme.lime : SignalTheme.muted.opacity(0.45))
                                    .frame(width: 6, height: 6)
                                Text(project.name)
                                    .lineLimit(1)
                            }
                            .font(.system(size: 9.5, weight: .semibold))
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(model.cloudProjectID == project.id ? SignalTheme.raised : SignalTheme.background, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(HoverButtonStyle())
                    }
                }

                HStack(spacing: 8) {
                    TextField("New project name", text: $newProjectName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10.5))
                        .padding(.horizontal, 11)
                        .frame(height: 36)
                        .background(SignalTheme.background, in: RoundedRectangle(cornerRadius: 9))
                    Button("Create") {
                        Task {
                            if await model.createProject(named: newProjectName) {
                                newProjectName = ""
                            }
                        }
                    }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isCloudBusy)
                }
            } else {
                Text("Sign in above to create and switch projects.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(SignalTheme.muted)
            }
        }
        .padding(14)
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

private struct ConnectionsSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedSource: LogSource = .supabase
    @State private var token = ""
    @State private var authorizationHeader = ""
    @State private var signingSecret = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("CONNECTIONS").sectionLabel()
                Text("Evidence sources")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Choose a source and follow its setup guide.")
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
                }
                .frame(width: 184)
                .frame(maxHeight: .infinity)

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
                Button("Cancel project selection") { model.cancelSupabaseProjectSelection() }
                    .buttonStyle(QuietButtonStyle())
            }
            if let state = integration(for: selectedSource)?.state,
               [.connected, .waitingForEvent].contains(state) {
                Button("Disconnect") { model.disconnect(selectedSource) }
                    .buttonStyle(QuietButtonStyle())
            }
            Spacer()
            if selectedSource == .supabase, model.supabaseProjects.isEmpty {
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
                    Text(selectedSource == .application ? "Start listening" : "Save & test")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selectedSource == .application && authorizationHeader.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @ViewBuilder
    private var configurationFields: some View {
        switch selectedSource {
        case .supabase:
            sourceExplanation(
                "What this adds",
                "Database errors, authentication failures, RLS denials, and Edge Function logs. Signalcase reads logs only after you approve access in Supabase."
            )
            if model.supabaseProjects.isEmpty {
                setupStep(1, "Authorize in your browser", "Connect opens Supabase in your default browser. Sign in and approve read-only access to projects and logs; no key or project ID is pasted into Signalcase.") {
                    setupResult("Signalcase receives a short-lived OAuth token and keeps it encrypted on the server.", icon: "checkmark.shield.fill", tint: SignalTheme.lime)
                }
                setupStep(2, "Choose a project", "After approval, Signalcase retrieves the projects your Supabase account can access. One project is selected automatically; otherwise you choose it here.") {
                    setupResult("Only the selected project's logs will be read.", icon: "rectangle.stack.fill", tint: SignalTheme.blue)
                }
            } else {
                setupStep(2, "Choose a Supabase project", "Your account can access more than one project. Select the one that belongs to this Signalcase project.") {
                    VStack(spacing: 7) {
                        ForEach(model.supabaseProjects) { project in
                            supabaseProjectButton(project)
                        }
                    }
                }
            }
        case .render:
            sourceExplanation(
                "What this adds",
                "Runtime errors, failed requests, deploys, restarts, and release timing from the Render services you choose."
            )
            setupStep(1, "Create a Render API key", "In Render, open Account Settings → API Keys. Create a key and copy it now—Render only shows it once.") {
                VStack(alignment: .leading, spacing: 9) {
                    externalLink("Open Render API keys", "https://dashboard.render.com/u/settings#api-keys")
                    secretField("API KEY", "rnd_…", text: $token)
                }
            }
            setupStep(2, "Choose what Signalcase reads", "The owner ID identifies your workspace. Add one or more service IDs separated by commas; service IDs begin with srv-.") {
                VStack(alignment: .leading, spacing: 9) {
                    setupField("WORKSPACE OWNER ID", "tea-…", text: $model.configuration.renderOwnerID)
                    setupField("SERVICE IDS", "srv-abc…, srv-def…", text: $model.configuration.renderResourceIDs)
                }
            }
            setupStep(3, "Test the connection", "Save & test checks the last five minutes. Signalcase stores the API key in your Mac's Keychain.") {
                setupResult("Only the selected services are included when you sync.", icon: "server.rack", tint: SignalTheme.purple)
            }
        case .application:
            sourceExplanation(
                "What this adds",
                "The error name, message, route, user, release, and request ID from your own code. These details help connect a generic Render 500 to the exact Supabase failure."
            )
            setupStep(1, "Start a protected receiver", "Signalcase listens on this Mac while the app is open. Choose a port and generate a secret that your application will send with every event.") {
                VStack(alignment: .leading, spacing: 9) {
                    setupNumberField("RECEIVER PORT", value: $model.configuration.revenueCatPort)
                    copyCard("EVENT ENDPOINT", applicationEndpoint)
                    HStack(alignment: .bottom, spacing: 8) {
                        secretField("AUTHORIZATION HEADER", "Bearer sc_local_…", text: $authorizationHeader)
                        Button("Generate") { generateApplicationSecret() }
                            .buttonStyle(QuietButtonStyle())
                    }
                }
            }
            setupStep(2, "Add it to your application", "Copy these values into your local development environment. Do not commit the authorization value to Git.") {
                copyCard("ENVIRONMENT VARIABLES", applicationEnvironment)
            }
            setupStep(3, "Send errors with useful context", "Post an event when your app catches an error. A shared request_id is the strongest way to connect it to Render and Supabase.") {
                copyCard("JAVASCRIPT EXAMPLE", applicationExample)
            }
        case .stripe, .revenueCat, .sentry:
            sourceExplanation("Not currently available", "This connection is hidden from the current Signalcase release.")
        }
    }

    private func setupField(_ label: String, _ placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).sectionLabel()
            TextField(placeholder, text: text).textFieldStyle(.plain)
                .padding(.horizontal, 10).frame(height: 34)
                .background(SignalTheme.raised, in: RoundedRectangle(cornerRadius: 8))
        }
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

    private func sourceExplanation(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased()).sectionLabel()
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(SignalTheme.muted)
                .lineSpacing(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SignalTheme.raised, in: RoundedRectangle(cornerRadius: 10))
    }

    private func setupStep<Content: View>(
        _ number: Int,
        _ title: String,
        _ detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.black)
                .frame(width: 22, height: 22)
                .background(SignalTheme.lime, in: Circle())
            VStack(alignment: .leading, spacing: 9) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                    Text(detail)
                        .font(.system(size: 9.25))
                        .foregroundStyle(SignalTheme.muted)
                        .lineSpacing(2)
                }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private func supabaseProjectButton(_ project: SupabaseProjectOption) -> some View {
        Button {
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
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(SignalTheme.muted)
            }
            .padding(.horizontal, 11)
            .frame(height: 48)
            .background(SignalTheme.raised, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(HoverButtonStyle())
        .focusEffectDisabled()
        .disabled(model.isCloudBusy)
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
        "http://127.0.0.1:\(model.configuration.revenueCatPort)/events"
    }

    private var applicationAuthorization: String {
        let clean = authorizationHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "Bearer YOUR_GENERATED_SECRET" : clean
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

    private func generateApplicationSecret() {
        let value = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        authorizationHeader = "Bearer sc_local_\(value)"
    }

    private func integration(for source: LogSource) -> Integration? {
        model.integrations.first { $0.source == source }
    }

    private func stateLabel(_ integration: Integration) -> String {
        if integration.source == .supabase, !model.supabaseProjects.isEmpty {
            return "CHOOSE A PROJECT"
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
        case .syncing, .waitingForEvent: SignalTheme.blue
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

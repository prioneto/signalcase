import SwiftUI

enum SignalTheme {
    static let background = Color(red: 0.055, green: 0.059, blue: 0.063)
    static let sidebar = Color(red: 0.070, green: 0.074, blue: 0.078)
    static let surface = Color(red: 0.095, green: 0.101, blue: 0.106)
    static let raised = Color(red: 0.125, green: 0.132, blue: 0.138)
    static let border = Color.white.opacity(0.10)
    static let text = Color(red: 0.92, green: 0.93, blue: 0.91)
    static let muted = Color(red: 0.55, green: 0.57, blue: 0.56)
    static let lime = Color(red: 0.72, green: 1.00, blue: 0.25)
    static let blue = Color(red: 0.34, green: 0.68, blue: 1.00)
    static let orange = Color(red: 1.00, green: 0.42, blue: 0.22)
    static let purple = Color(red: 0.70, green: 0.54, blue: 1.00)
    static let yellow = Color(red: 1.00, green: 0.78, blue: 0.24)
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 250)

            Rectangle().fill(SignalTheme.border).frame(width: 1)

            CaseListView()
                .frame(width: 390)

            Rectangle().fill(SignalTheme.border).frame(width: 1)

            if let item = model.selectedCase {
                CaseDetailView(item: item)
                    .id(item.id)
            } else {
                EmptyDetailView()
            }
        }
        .background(SignalTheme.background)
        .foregroundStyle(SignalTheme.text)
        .overlay(alignment: .bottomTrailing) {
            if let toast = model.toastMessage {
                ToastView(message: toast)
                    .padding(20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.toastMessage)
        .sheet(isPresented: $model.isCapturePresented) {
            CaptureSheet()
                .environmentObject(model)
        }
        .sheet(isPresented: $model.isIntegrationsPresented) {
            IntegrationsSheet()
                .environmentObject(model)
        }
    }
}

private struct SidebarView: View {
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
                    Text("Capture recent logs")
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

                Button { model.chooseProject() } label: {
                    HStack(spacing: 11) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(SignalTheme.lime.opacity(0.12))
                                .frame(width: 36, height: 36)
                            Image(systemName: "folder.fill")
                                .foregroundStyle(SignalTheme.lime)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.projectName)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            Text(model.linkedProjectURL == nil ? "Link source" : "Source matching enabled")
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

                Button { model.isIntegrationsPresented = true } label: {
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
                            Text("3 demo sources · 2 available")
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
        case .all: "square.stack.3d.up.fill"
        case .new: "circle"
        case .triaged: "scope"
        case .fixing: "hammer.fill"
        case .verified: "checkmark.seal.fill"
        }
    }
}

private struct CaseListView: View {
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
                VStack(spacing: 10) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 24))
                        .foregroundStyle(SignalTheme.muted)
                    Text("No matching cases")
                        .font(.system(size: 12, weight: .semibold))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.filteredCases) { item in
                            CaseRow(item: item, isSelected: model.selectedCaseID == item.id) {
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

private struct CaseRow: View {
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
            .padding(.horizontal, 34)
            .padding(.bottom, 44)
        }
        .background(SignalTheme.background)
    }

    private var detailHeader: some View {
        HStack(spacing: 12) {
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

            Spacer()

            Button { model.copySelectedCase() } label: {
                Label("Copy packet", systemImage: "doc.on.doc")
                    .compactAction()
            }
            .buttonStyle(HoverButtonStyle())

            if let next = item.status.next {
                Button { model.advanceSelectedCase() } label: {
                    HStack(spacing: 8) {
                        Text("Move to \(next.title)")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 15)
                    .frame(height: 38)
                    .background(SignalTheme.lime, in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(.top, 22)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(item.severity.title)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(severityColor(item.severity))
                Text(item.environment.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(SignalTheme.muted)
            }

            Text(item.title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .tracking(-0.6)
                .lineLimit(3)

            Text(item.summary)
                .font(.system(size: 13))
                .foregroundStyle(SignalTheme.muted)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 34)
        .padding(.bottom, 26)
    }

    private var impactStrip: some View {
        HStack(spacing: 0) {
            metric("OCCURRENCES", value: "\(item.occurrenceCount)")
            metricDivider
            metric("AFFECTED USERS", value: "\(item.affectedUsers)")
            metricDivider
            metric("FIRST SEEN", value: relativeDate(item.firstSeen))
            metricDivider
            VStack(alignment: .leading, spacing: 7) {
                Text("SOURCES").sectionLabel()
                SourceStack(sources: item.sources, size: 27)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
        }
        .padding(.vertical, 17)
        .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 17))
        .overlay { RoundedRectangle(cornerRadius: 17).stroke(SignalTheme.border) }
    }

    private var findingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PROVEN FROM THE LOGS").sectionLabel()
                    Text("No guesses. Every finding links back to an event.")
                        .font(.system(size: 10))
                        .foregroundStyle(SignalTheme.muted)
                }
                Spacer()
                Text("RULE-BASED")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(SignalTheme.lime)
                    .padding(.horizontal, 9)
                    .frame(height: 25)
                    .background(SignalTheme.lime.opacity(0.08), in: Capsule())
            }

            VStack(spacing: 0) {
                ForEach(Array(item.findings.enumerated()), id: \.element.id) { index, finding in
                    FindingRow(index: index + 1, finding: finding)
                    if index < item.findings.count - 1 {
                        Rectangle().fill(SignalTheme.border).frame(height: 1).padding(.leading, 43)
                    }
                }
            }
            .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 17))
            .overlay { RoundedRectangle(cornerRadius: 17).stroke(SignalTheme.border) }
        }
        .padding(.top, 34)
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Text("UNIFIED TIMELINE").sectionLabel()
                Spacer()
                Text("\(item.events.count) RELATED EVENTS")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(SignalTheme.muted)
            }

            VStack(spacing: 0) {
                ForEach(Array(item.events.sorted { $0.timestamp < $1.timestamp }.enumerated()), id: \.element.id) { index, event in
                    EventRow(event: event, showConnector: index < item.events.count - 1)
                }
            }
        }
        .padding(.top, 36)
    }

    private var lowerSection: some View {
        HStack(alignment: .top, spacing: 34) {
            VStack(alignment: .leading, spacing: 14) {
                Text("RELEVANT CODE").sectionLabel()
                if item.codeReferences.isEmpty {
                    Text("No source path matched yet.")
                        .font(.system(size: 11))
                        .foregroundStyle(SignalTheme.muted)
                } else {
                    ForEach(item.codeReferences) { reference in
                        Button { model.openCode(reference) } label: {
                            HStack(spacing: 11) {
                                Image(systemName: "chevron.left.forwardslash.chevron.right")
                                    .foregroundStyle(SignalTheme.blue)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(reference.path):\(reference.line)")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .lineLimit(1)
                                    Text(reference.reason)
                                        .font(.system(size: 9))
                                        .foregroundStyle(SignalTheme.muted)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(SignalTheme.muted)
                            }
                            .padding(.vertical, 11)
                            .padding(.horizontal, 12)
                            .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(HoverButtonStyle())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 14) {
                Text("REPRODUCE IT").sectionLabel()
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 38)
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).sectionLabel()
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
    }

    private var metricDivider: some View {
        Rectangle().fill(SignalTheme.border).frame(width: 1, height: 35)
    }
}

private struct FindingRow: View {
    let index: Int
    let finding: CaseFinding

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            ZStack {
                Circle().fill(toneColor.opacity(0.11)).frame(width: 28, height: 28)
                Text(String(format: "%02d", index))
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(toneColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(finding.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text(finding.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(SignalTheme.muted)
                    .lineSpacing(2)
            }
            Spacer()
            Image(systemName: toneIcon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(toneColor)
        }
        .padding(15)
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
    @State private var selectedSources: Set<LogSource> = [.supabase, .stripe, .render]
    @State private var note = ""

    private let windows = [5, 15, 30, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 13).fill(SignalTheme.lime).frame(width: 42, height: 42)
                    Image(systemName: "viewfinder").font(.system(size: 18, weight: .bold)).foregroundStyle(.black)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(CircleButtonStyle())
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("CAPTURE RECENT ACTIVITY").sectionLabel()
                Text("Turn the last few minutes into a case")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text("Signalcase groups related events by request ID, stack fingerprint, user, release, and time. Demo sources are used in this prototype.")
                    .font(.system(size: 11))
                    .foregroundStyle(SignalTheme.muted)
                    .lineSpacing(3)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("TIME WINDOW").sectionLabel()
                HStack(spacing: 8) {
                    ForEach(windows, id: \.self) { window in
                        Button { minutes = window } label: {
                            Text(window == 60 ? "1 hour" : "\(window) min")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(minutes == window ? .black : SignalTheme.text)
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .background(minutes == window ? SignalTheme.lime : SignalTheme.surface, in: RoundedRectangle(cornerRadius: 11))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(HoverButtonStyle())
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("SOURCES").sectionLabel()
                HStack(spacing: 8) {
                    ForEach([LogSource.supabase, .stripe, .render, .revenueCat, .sentry]) { source in
                        Button {
                            if selectedSources.contains(source) { selectedSources.remove(source) }
                            else { selectedSources.insert(source) }
                        } label: {
                            VStack(spacing: 7) {
                                Image(systemName: source.systemImage)
                                    .font(.system(size: 15, weight: .semibold))
                                Text(source.title)
                                    .font(.system(size: 8, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(selectedSources.contains(source) ? sourceColor(source) : SignalTheme.muted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(selectedSources.contains(source) ? sourceColor(source).opacity(0.09) : SignalTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selectedSources.contains(source) ? sourceColor(source).opacity(0.35) : SignalTheme.border)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(HoverButtonStyle())
                    }
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("WHAT DID YOU NOTICE? · OPTIONAL").sectionLabel()
                TextField("Example: I clicked Export and nothing downloaded", text: $note, axis: .vertical)
                    .lineLimit(2...4)
                    .font(.system(size: 11))
                    .textFieldStyle(.plain)
                    .padding(13)
                    .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 13))
                    .overlay { RoundedRectangle(cornerRadius: 13).stroke(SignalTheme.border) }
            }

            HStack {
                HStack(spacing: 7) {
                    Image(systemName: "shield.lefthalf.filled")
                    Text("READ-ONLY DEMO")
                }
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(SignalTheme.muted)

                Spacer()

                Button("Cancel") { dismiss() }
                    .buttonStyle(QuietButtonStyle())

                Button {
                    Task { await model.captureRecentLogs(minutes: minutes, sources: selectedSources, note: note) }
                } label: {
                    HStack(spacing: 9) {
                        if model.isCapturing {
                            ProgressView().controlSize(.small).tint(.black)
                        } else {
                            Image(systemName: "waveform.path.ecg")
                        }
                        Text(model.isCapturing ? "Building case…" : "Capture and build case")
                    }
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 17)
                    .frame(height: 42)
                    .background(SignalTheme.lime, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(model.isCapturing)
            }
        }
        .padding(28)
        .frame(width: 650)
        .background(SignalTheme.background)
    }
}

private struct IntegrationsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 13).fill(SignalTheme.blue.opacity(0.13)).frame(width: 42, height: 42)
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SignalTheme.blue)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(CircleButtonStyle())
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("EVIDENCE SOURCES").sectionLabel()
                Text("Connect the places bugs leave traces")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text("Connections are read-only. The prototype toggles realistic demo sources; production OAuth and restricted-key setup comes later.")
                    .font(.system(size: 11))
                    .foregroundStyle(SignalTheme.muted)
            }

            VStack(spacing: 8) {
                ForEach(model.integrations) { integration in
                    Button {
                        model.setIntegration(integration.source, connected: integration.state == .available)
                    } label: {
                        HStack(spacing: 13) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(sourceColor(integration.source).opacity(0.10))
                                    .frame(width: 42, height: 42)
                                Image(systemName: integration.source.systemImage)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(sourceColor(integration.source))
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(integration.source.title)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(integration.detail)
                                    .font(.system(size: 9))
                                    .foregroundStyle(SignalTheme.muted)
                            }
                            Spacer()
                            Text(stateLabel(integration.state))
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(integration.state == .available ? SignalTheme.muted : SignalTheme.lime)
                            Image(systemName: integration.state == .available ? "plus" : "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(integration.state == .available ? SignalTheme.muted : SignalTheme.lime)
                                .frame(width: 26, height: 26)
                                .background(SignalTheme.raised, in: Circle())
                        }
                        .padding(11)
                        .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 15))
                        .overlay { RoundedRectangle(cornerRadius: 15).stroke(SignalTheme.border) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(HoverButtonStyle())
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "cpu")
                    .foregroundStyle(SignalTheme.lime)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Optional on-device log cleanup")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Planned: extract fields locally on supported Macs. Grouping works without it.")
                        .font(.system(size: 9))
                        .foregroundStyle(SignalTheme.muted)
                }
                Spacer()
                Text("PLANNED")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(SignalTheme.muted)
            }
            .padding(13)
            .background(SignalTheme.lime.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(28)
        .frame(width: 620)
        .background(SignalTheme.background)
    }

    private func stateLabel(_ state: IntegrationState) -> String {
        switch state {
        case .connected: "CONNECTED"
        case .demo: "DEMO ON"
        case .available: "ADD DEMO"
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
                .background(hovering ? Color.white.opacity(0.025) : Color.clear)
                .opacity(configuration.isPressed ? 0.72 : 1)
                .animation(.easeOut(duration: 0.12), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

private struct CircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(SignalTheme.muted)
            .frame(width: 32, height: 32)
            .background(configuration.isPressed ? SignalTheme.raised : SignalTheme.surface, in: Circle())
            .contentShape(Circle())
    }
}

private struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(SignalTheme.muted)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(configuration.isPressed ? SignalTheme.raised : SignalTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            .frame(height: 40)
            .background(SignalTheme.lime, in: RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
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
            .frame(height: 36)
            .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 11))
            .overlay { RoundedRectangle(cornerRadius: 11).stroke(SignalTheme.border) }
            .contentShape(Rectangle())
    }
}

private func color(for status: CaseStatus) -> Color {
    switch status {
    case .new: SignalTheme.orange
    case .triaged: SignalTheme.yellow
    case .fixing: SignalTheme.blue
    case .verified: SignalTheme.lime
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
    case .revenueCat: SignalTheme.orange
    case .sentry: SignalTheme.yellow
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


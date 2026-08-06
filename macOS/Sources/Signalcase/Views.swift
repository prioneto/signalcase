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
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 232)

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
        .sheet(isPresented: $model.isSettingsPresented) {
            SettingsSheet()
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
        case .all: "square.stack.3d.up.fill"
        case .new: "circle"
        case .triaged: "checkmark.circle"
        case .fixing: "hammer.fill"
        case .verified: "checkmark.seal.fill"
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 34)
            .padding(.bottom, 44)
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

            Rectangle().fill(SignalTheme.border).frame(width: 1, height: 22)

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

            if let next = item.status.next {
                Button { model.advanceSelectedCase() } label: {
                    HStack(spacing: 8) {
                        Text(item.status.advanceActionTitle ?? next.title)
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
                    Text("WHAT THE EVIDENCE SHOWS").sectionLabel()
                    Text(item.detectionNote.isEmpty ? "Exact matches and time-based context are labeled separately." : item.detectionNote)
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
    @State private var selectedSources: Set<LogSource> = [.supabase, .stripe, .render]

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
                Text("SYNC RECENT ACTIVITY").sectionLabel()
                Text("Find problems in real logs")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text("Choose connected sources and a time window. Signalcase imports the events, redacts secrets, and creates cases only for failures or unusual warnings.")
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
                        let isConnected = model.availableSyncSources.contains(source)
                        Button {
                            guard isConnected else { model.openSettings(.connections); return }
                            if selectedSources.contains(source) { selectedSources.remove(source) }
                            else { selectedSources.insert(source) }
                        } label: {
                            VStack(spacing: 7) {
                                Image(systemName: source.systemImage)
                                    .font(.system(size: 15, weight: .semibold))
                                Text(source.title)
                                    .font(.system(size: 8, weight: .semibold))
                                    .lineLimit(1)
                                Text(isConnected ? "READY" : "SET UP")
                                    .font(.system(size: 6, weight: .bold, design: .monospaced))
                            }
                            .foregroundStyle(selectedSources.contains(source) && isConnected ? sourceColor(source) : SignalTheme.muted)
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

            HStack {
                Button { model.importLogs() } label: {
                    Label("Import log file", systemImage: "doc.badge.plus")
                }
                .buttonStyle(QuietButtonStyle())

                Spacer()

                Button("Cancel") { dismiss() }
                    .buttonStyle(QuietButtonStyle())

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
                        Text(model.isCapturing ? "Checking providers…" : "Sync and detect cases")
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
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("GENERAL").sectionLabel()
                    Text("Workspace")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                    Text("Manage the project Signalcase searches and understand the case workflow.")
                        .font(.system(size: 11))
                        .foregroundStyle(SignalTheme.muted)
                }

                settingsSection(title: "PROJECT", subtitle: "Used only to locate relevant source files.") {
                    HStack(spacing: 13) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(SignalTheme.lime)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.projectName)
                                .font(.system(size: 12, weight: .semibold))
                            Text(model.linkedProjectURL?.path ?? "No folder selected")
                                .font(.system(size: 9))
                                .foregroundStyle(SignalTheme.muted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button(model.linkedProjectURL == nil ? "Choose folder" : "Change") { model.chooseProject() }
                            .buttonStyle(QuietButtonStyle())
                    }
                }

                settingsSection(title: "CONNECTIONS", subtitle: "Services Signalcase can read evidence from.") {
                    HStack(spacing: 13) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 15))
                            .foregroundStyle(SignalTheme.blue)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.connectedCount == 1 ? "1 source connected" : "\(model.connectedCount) sources connected")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Supabase, Render, Stripe, RevenueCat, Sentry, and application logs")
                                .font(.system(size: 9))
                                .foregroundStyle(SignalTheme.muted)
                        }
                        Spacer()
                        Button("Manage") { model.settingsSection = .connections }
                            .buttonStyle(QuietButtonStyle())
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("CASE WORKFLOW").sectionLabel()
                    Text("Each status answers a simple question. You can move a case forward from its case page.")
                        .font(.system(size: 10))
                        .foregroundStyle(SignalTheme.muted)

                    VStack(spacing: 0) {
                        ForEach(Array(CaseStatus.allCases.enumerated()), id: \.element.id) { index, status in
                            HStack(alignment: .top, spacing: 12) {
                                Circle()
                                    .fill(color(for: status))
                                    .frame(width: 7, height: 7)
                                    .padding(.top, 4)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(status.title)
                                        .font(.system(size: 11.5, weight: .semibold))
                                    Text(status.explanation)
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(SignalTheme.muted)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)

                            if index < CaseStatus.allCases.count - 1 {
                                Rectangle().fill(SignalTheme.border).frame(height: 1).padding(.leading, 33)
                            }
                        }
                    }
                    .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(SignalTheme.border))
                }

                settingsSection(title: "ACTIVITY & DATA", subtitle: "Review ignored events, muted errors, deleted cases, or clear local history.") {
                    HStack {
                        Text(model.lastSyncReport?.summary ?? "No sync activity yet")
                            .font(.system(size: 10))
                            .foregroundStyle(SignalTheme.muted)
                            .lineLimit(2)
                        Spacer()
                        Button("Open") { model.settingsSection = .activity }
                            .buttonStyle(QuietButtonStyle())
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SignalTheme.background)
    }

    private func settingsSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).sectionLabel()
            Text(subtitle)
                .font(.system(size: 9.5))
                .foregroundStyle(SignalTheme.muted)
            content()
                .padding(14)
                .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(SignalTheme.border))
        }
    }
}

private struct ConnectionsSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedSource: LogSource = .supabase
    @State private var token = ""
    @State private var authorizationHeader = ""
    @State private var signingSecret = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Text("CONNECTIONS").sectionLabel()
                Text("Evidence sources")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                Text("Choose a source, enter its credentials, then test it against real recent activity. Signalcase makes read requests only, and secrets are stored in your Mac Keychain.")
                    .font(.system(size: 11))
                    .foregroundStyle(SignalTheme.muted)
            }

            HStack(alignment: .top, spacing: 16) {
                ScrollView {
                    VStack(spacing: 6) {
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
                                .frame(height: 48)
                                .background(selectedSource == integration.source ? SignalTheme.raised : Color.clear, in: RoundedRectangle(cornerRadius: 13))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(HoverButtonStyle())
                        }
                    }
                }
                .frame(width: 190, height: 365)

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(selectedSource.title)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                            Text(integration(for: selectedSource)?.detail ?? "")
                                .font(.system(size: 9))
                                .foregroundStyle(SignalTheme.muted)
                        }
                        Spacer()
                    }

                    configurationFields

                    if let error = integration(for: selectedSource)?.errorMessage, !error.isEmpty {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(SignalTheme.orange)
                            .lineLimit(3)
                    }

                    Spacer()

                    HStack {
                        if let state = integration(for: selectedSource)?.state,
                           [.connected, .waitingForEvent].contains(state) {
                            Button("Disconnect") { model.disconnect(selectedSource) }
                                .buttonStyle(QuietButtonStyle())
                        }
                        Spacer()
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
                            Text(selectedSource == .revenueCat || selectedSource == .application ? "Start receiver" : "Save & test")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, minHeight: 365, alignment: .topLeading)
                .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 17))
                .overlay { RoundedRectangle(cornerRadius: 17).stroke(SignalTheme.border) }
            }

            HStack {
                Text(model.receiverStatus)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(SignalTheme.muted)
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SignalTheme.background)
        .onChange(of: selectedSource) {
            token = ""
            authorizationHeader = ""
            signingSecret = ""
        }
    }

    @ViewBuilder
    private var configurationFields: some View {
        switch selectedSource {
        case .supabase:
            setupField("PROJECT REFERENCE", "abcdefghijklmno", text: $model.configuration.supabaseProjectRef)
            secretField("PERSONAL ACCESS TOKEN", "sbp_…", text: $token)
            help("Create a Personal Access Token in Supabase account settings. It is used only with the Management API logs endpoint.")
        case .sentry:
            setupField("ORGANIZATION SLUG", "my-team", text: $model.configuration.sentryOrganization)
            setupField("PROJECT SLUG", "my-app", text: $model.configuration.sentryProject)
            setupField("BASE URL", "https://sentry.io", text: $model.configuration.sentryBaseURL)
            secretField("TOKEN · EVENT:READ", "sntrys_…", text: $token)
        case .stripe:
            secretField("RESTRICTED KEY · EVENTS READ", "rk_live_…", text: $token)
            help("Use a restricted key that can read Events. Signalcase never creates, refunds, or changes payments.")
        case .render:
            setupField("WORKSPACE OWNER ID", "tea-…", text: $model.configuration.renderOwnerID)
            setupField("SERVICE IDS · COMMA SEPARATED", "srv-…, srv-…", text: $model.configuration.renderResourceIDs)
            secretField("API KEY", "rnd_…", text: $token)
        case .revenueCat:
            endpointCard("POST http://localhost:\(model.configuration.revenueCatPort)/revenuecat")
            setupNumberField("RECEIVER PORT", value: $model.configuration.revenueCatPort)
            secretField("OPTIONAL AUTHORIZATION HEADER", "Bearer …", text: $authorizationHeader)
            secretField("OPTIONAL SIGNING SECRET", "Webhook HMAC secret", text: $signingSecret)
            help("RevenueCat must reach this Mac. For remote webhooks, expose the local endpoint with a secure tunnel. Historical RevenueCat logs are not fetched automatically.")
        case .application:
            endpointCard("POST http://localhost:\(model.configuration.revenueCatPort)/events")
            secretField("OPTIONAL AUTHORIZATION HEADER", "Bearer …", text: $authorizationHeader)
            help("Send structured JSON with timestamp, level, title, message, request_id, user_id, release, and route. The request ID is what connects services exactly.")
        }
    }

    private func setupField(_ label: String, _ placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).sectionLabel()
            TextField(placeholder, text: text).textFieldStyle(.plain)
                .padding(.horizontal, 11).frame(height: 36)
                .background(SignalTheme.raised, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func setupNumberField(_ label: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).sectionLabel()
            TextField("9782", value: value, format: .number).textFieldStyle(.plain)
                .padding(.horizontal, 11).frame(height: 36)
                .background(SignalTheme.raised, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func secretField(_ label: String, _ placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).sectionLabel()
            SecureField(placeholder, text: text).textFieldStyle(.plain)
                .padding(.horizontal, 11).frame(height: 36)
                .background(SignalTheme.raised, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func endpointCard(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(SignalTheme.blue)
            .padding(.horizontal, 11).frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .background(SignalTheme.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private func help(_ value: String) -> some View {
        Text(value).font(.system(size: 9)).foregroundStyle(SignalTheme.muted).lineSpacing(2)
    }

    private func integration(for source: LogSource) -> Integration? {
        model.integrations.first { $0.source == source }
    }

    private func stateLabel(_ integration: Integration) -> String {
        switch integration.state {
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

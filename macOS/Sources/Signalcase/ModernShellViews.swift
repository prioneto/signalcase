import AppKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand.padding(.bottom, 28)

            sectionLabel("PROJECT")
            Button { model.chooseProject() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "folder")
                        .foregroundStyle(SignalTheme.lime)
                        .frame(width: 16)
                    Text(model.projectName).lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(SignalTheme.muted)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SignalTheme.text)
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(ModernPressableButtonStyle(scale: 0.985))

            sectionLabel("VIEWS").padding(.top, 22)
            VStack(spacing: 3) {
                ForEach(CaseFilter.allCases) { filter in
                    filterButton(filter)
                }
            }

            Spacer()

            sectionLabel("WORKSPACE")
            ModernSidebarActionRow(
                title: "Connections",
                subtitle: model.connectedCount == 1 ? "1 source connected" : "\(model.connectedCount) sources connected",
                systemImage: "point.3.connected.trianglepath.dotted",
                tint: SignalTheme.blue
            ) { model.isIntegrationsPresented = true }

            ModernSidebarActionRow(
                title: "Event diagnostics",
                subtitle: diagnosticsSubtitle,
                systemImage: "checklist.unchecked",
                tint: SignalTheme.lime
            ) { model.isDiagnosticsPresented = true }
            .padding(.top, 7)
        }
        .padding(.top, 22)
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .background(SignalTheme.sidebar)
    }

    private var brand: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(SignalTheme.lime).frame(width: 31, height: 31)
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(.black)
            }
            Text("SIGNALCASE")
                .font(.system(size: 14, weight: .black, design: .monospaced))
                .tracking(1.2)
        }
    }

    private func sectionLabel(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .tracking(1.35)
            .foregroundStyle(SignalTheme.muted)
            .padding(.bottom, 9)
    }

    private var diagnosticsSubtitle: String {
        guard let report = model.lastSyncReport else { return "No sync result yet" }
        return "\(report.checkedCount) checked · \(report.failureCount) failures"
    }

    private func filterButton(_ filter: CaseFilter) -> some View {
        let selected = model.filter == filter
        return Button {
            model.filter = filter
            model.showCaseList()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: modernFilterIcon(filter))
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 16)
                Text(filter.title)
                Spacer()
                Text("\(model.count(for: filter))")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(selected ? SignalTheme.lime : SignalTheme.muted)
            }
            .font(.system(size: 12, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? SignalTheme.text : SignalTheme.muted)
            .padding(.horizontal, 10)
            .frame(height: 35)
            .background(selected ? SignalTheme.surface : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(ModernPressableButtonStyle(scale: 0.985))
    }
}

private struct ModernSidebarActionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 10.5, weight: .semibold))
                    Text(subtitle).font(.system(size: 8.5)).foregroundStyle(SignalTheme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(SignalTheme.muted)
            }
            .padding(.horizontal, 11)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(SignalTheme.border))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(ModernPressableButtonStyle(scale: 0.985))
    }
}

struct CaseListView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if !model.cases.isEmpty {
                    searchAndFilter
                }

                if model.filteredCases.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 9) {
                        ForEach(model.filteredCases) { item in
                            Button { model.select(item) } label: {
                                CaseRow(item: item)
                            }
                            .buttonStyle(ModernPressableButtonStyle(scale: 0.995))
                        }
                    }
                }
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(.horizontal, 44)
            .padding(.vertical, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SignalTheme.background)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.filter.title)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .tracking(-0.5)
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(SignalTheme.muted)
            }
            Spacer()
            Button { model.importLogs() } label: {
                Label("Import logs", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(ModernQuietButtonStyle())

            Button { model.isCapturePresented = true } label: {
                Label("Sync logs", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .background(SignalTheme.lime, in: RoundedRectangle(cornerRadius: 11))
                    .contentShape(RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(ModernPressableButtonStyle())
            .keyboardShortcut("n", modifiers: .command)
        }
    }

    private var searchAndFilter: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(SignalTheme.muted)
                TextField("Search cases, errors, or files", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(SignalTheme.border))

            Picker("Status", selection: $model.filter) {
                ForEach(CaseFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 150)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 13) {
            ZStack {
                Circle().fill(SignalTheme.lime.opacity(0.08)).frame(width: 52, height: 52)
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(SignalTheme.lime)
            }
            Text(model.cases.isEmpty ? "No cases yet" : "No matching cases")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            Text(model.cases.isEmpty
                 ? "Connect a source and sync recent activity. Only meaningful failures become cases."
                 : "Change the search or status filter.")
                .font(.system(size: 11))
                .foregroundStyle(SignalTheme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 390)
            if model.cases.isEmpty {
                Button("Connect sources") { model.isIntegrationsPresented = true }
                    .buttonStyle(ModernQuietButtonStyle())
            }
        }
        .padding(.top, 80)
        .frame(maxWidth: .infinity)
    }

    private var summary: String {
        let count = model.filteredCases.count
        return "\(count) \(count == 1 ? "case" : "cases") · Live evidence"
    }
}

struct CaseRow: View {
    let item: SignalCase

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Circle().fill(modernStatusColor(item.status)).frame(width: 6, height: 6)
                Text(item.status.title.uppercased())
                Text("·")
                Text(item.reference)
                Spacer()
                Text(modernRelativeDate(item.lastSeen))
            }
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(SignalTheme.muted)

            Text(item.title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(SignalTheme.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(item.summary.replacingOccurrences(of: "\n", with: " "))
                .font(.system(size: 10))
                .foregroundStyle(SignalTheme.muted)
                .lineLimit(1)

            HStack(spacing: 12) {
                Label("\(item.occurrenceCount)", systemImage: "repeat")
                if item.affectedUsers > 0 {
                    Label("\(item.affectedUsers)", systemImage: "person.2")
                }
                Text(item.severity.title)
                    .foregroundStyle(modernSeverityColor(item.severity))
                Spacer()
                ModernSourceStack(sources: item.sources)
            }
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .foregroundStyle(SignalTheme.muted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(SignalTheme.border))
        .contentShape(RoundedRectangle(cornerRadius: 13))
    }
}

private struct ModernSourceStack: View {
    let sources: [LogSource]

    var body: some View {
        HStack(spacing: -5) {
            ForEach(sources.prefix(4)) { source in
                Text(source.shortTitle)
                    .font(.system(size: 6.5, weight: .black, design: .monospaced))
                    .foregroundStyle(modernSourceColor(source))
                    .frame(width: 23, height: 23)
                    .background(SignalTheme.background, in: Circle())
                    .overlay(Circle().stroke(SignalTheme.border))
            }
        }
    }
}

private struct ModernPressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        ModernInteractiveButton(configuration: configuration, scale: scale)
    }
}

private struct ModernInteractiveButton: View {
    let configuration: ButtonStyle.Configuration
    let scale: CGFloat
    @State private var hovering = false

    var body: some View {
        configuration.label
            .brightness(hovering ? 0.035 : 0)
            .shadow(color: .black.opacity(hovering ? 0.16 : 0), radius: 8, y: 3)
            .scaleEffect(configuration.isPressed ? scale : hovering ? 1.006 : 1)
            .opacity(configuration.isPressed ? 0.80 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.16), value: hovering)
            .onHover { value in
                hovering = value
                value ? NSCursor.pointingHand.set() : NSCursor.arrow.set()
            }
    }
}

private struct ModernQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(SignalTheme.text.opacity(configuration.isPressed ? 0.6 : 0.78))
            .padding(.horizontal, 12)
            .frame(minHeight: 38)
            .background(configuration.isPressed ? SignalTheme.raisedHover : SignalTheme.surface, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(SignalTheme.border))
            .contentShape(RoundedRectangle(cornerRadius: 11))
    }
}

private func modernFilterIcon(_ filter: CaseFilter) -> String {
    switch filter {
    case .all: "square.grid.2x2"
    case .new: "circle"
    case .triaged: "scope"
    case .fixing: "hammer"
    case .verified: "checkmark.seal"
    }
}

private func modernStatusColor(_ status: CaseStatus) -> Color {
    switch status {
    case .new: SignalTheme.orange
    case .triaged: SignalTheme.lime
    case .fixing: SignalTheme.blue
    case .verified: SignalTheme.muted
    }
}

private func modernSeverityColor(_ severity: CaseSeverity) -> Color {
    switch severity {
    case .critical: SignalTheme.orange
    case .high: SignalTheme.yellow
    case .normal: SignalTheme.muted
    }
}

private func modernSourceColor(_ source: LogSource) -> Color {
    switch source {
    case .supabase: SignalTheme.lime
    case .stripe: SignalTheme.purple
    case .render: SignalTheme.blue
    case .revenueCat: SignalTheme.yellow
    case .sentry: SignalTheme.orange
    case .application: SignalTheme.text
    }
}

private func modernRelativeDate(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
}

struct DiagnosticsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDisposition: EventDisposition?
    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("EVENT DIAGNOSTICS")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .tracking(1.3)
                        .foregroundStyle(SignalTheme.muted)
                    Text("What Signalcase checked")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                }
                Spacer()
                Button("Clear test data", role: .destructive) { confirmClear = true }
                    .buttonStyle(ModernQuietButtonStyle())
                Button("Done") { dismiss() }
                    .buttonStyle(ModernQuietButtonStyle())
            }
            .padding(26)

            Rectangle().fill(SignalTheme.border).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let report = model.lastSyncReport {
                        reportSummary(report)
                        diagnostics(report)
                    } else {
                        emptyReport
                    }

                    if !model.ignoredFingerprints.isEmpty { ignoredSection }
                    if !model.deletedCases.isEmpty { deletedSection }
                }
                .padding(26)
            }
        }
        .frame(width: 780, height: 660)
        .background(SignalTheme.background)
        .alert("Clear all test data?", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear cases and events", role: .destructive) { model.clearTestData() }
        } message: {
            Text("This clears local cases, events, muted error types, deleted cases, and sync diagnostics. Connections and the linked project stay configured.")
        }
    }

    private func reportSummary(_ report: SyncReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(report.summary)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            HStack(spacing: 8) {
                diagnosticMetric("CHECKED", report.checkedCount, SignalTheme.text)
                diagnosticMetric("FAILURES", report.failureCount, SignalTheme.orange)
                diagnosticMetric("ROUTINE", report.routineCount, SignalTheme.muted)
                diagnosticMetric("UNSUPPORTED", report.unsupportedCount, SignalTheme.yellow)
            }
            ForEach(report.sourceErrors, id: \.self) { error in
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(SignalTheme.orange)
            }
        }
    }

    private func diagnosticMetric(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .foregroundStyle(SignalTheme.muted)
            Text("\(value)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(SignalTheme.border))
    }

    private func diagnostics(_ report: SyncReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("INSPECT EVENTS")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(SignalTheme.muted)
                Spacer()
                diagnosticFilter("All", nil, count: report.checkedCount)
                ForEach(EventDisposition.allCases) { disposition in
                    diagnosticFilter(
                        disposition.title,
                        disposition,
                        count: report.diagnostics.filter { $0.disposition == disposition }.count
                    )
                }
            }

            LazyVStack(spacing: 7) {
                ForEach(filteredDiagnostics(report)) { diagnostic in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 8) {
                            Image(systemName: diagnostic.source.systemImage)
                                .foregroundStyle(modernSourceColor(diagnostic.source))
                            Text(diagnostic.title)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            Spacer()
                            Text(diagnostic.disposition.title.uppercased())
                                .font(.system(size: 7, weight: .black, design: .monospaced))
                                .foregroundStyle(dispositionColor(diagnostic.disposition))
                        }
                        Text(diagnostic.reason)
                            .font(.system(size: 10))
                            .foregroundStyle(SignalTheme.text.opacity(0.76))
                        Text(diagnostic.detail)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(SignalTheme.muted)
                            .lineLimit(2)
                    }
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(SignalTheme.border))
                }
            }
        }
    }

    private func diagnosticFilter(_ title: String, _ disposition: EventDisposition?, count: Int) -> some View {
        let selected = selectedDisposition == disposition
        return Button { selectedDisposition = disposition } label: {
            Text("\(title) \(count)")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(selected ? .black : SignalTheme.muted)
                .padding(.horizontal, 9)
                .frame(height: 27)
                .background(selected ? SignalTheme.lime : SignalTheme.surface, in: Capsule())
        }
        .buttonStyle(ModernPressableButtonStyle(scale: 0.97))
    }

    private func filteredDiagnostics(_ report: SyncReport) -> [EventDiagnostic] {
        guard let selectedDisposition else { return report.diagnostics }
        return report.diagnostics.filter { $0.disposition == selectedDisposition }
    }

    private var ignoredSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            diagnosticsLabel("MUTED ERROR TYPES")
            Text("Signalcase will not create cases for these error patterns, even when they happen again.")
                .font(.system(size: 9.5))
                .foregroundStyle(SignalTheme.muted)
            ForEach(model.ignoredFingerprints) { ignored in
                HStack(spacing: 12) {
                    Image(systemName: "speaker.slash").foregroundStyle(SignalTheme.yellow)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ignored.title).font(.system(size: 11, weight: .semibold))
                        Text(ignored.fingerprint)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(SignalTheme.muted)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Unmute") { model.restoreFingerprint(ignored.fingerprint) }
                        .buttonStyle(ModernQuietButtonStyle())
                }
                .padding(12)
                .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var deletedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            diagnosticsLabel("DELETED CASES")
            Text("These exact cases are hidden. A new occurrence of the same error can still create a new case.")
                .font(.system(size: 9.5))
                .foregroundStyle(SignalTheme.muted)
            ForEach(model.deletedCases) { item in
                HStack(spacing: 12) {
                    Image(systemName: "trash").foregroundStyle(SignalTheme.muted)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(item.reference) · \(item.title)").font(.system(size: 11, weight: .semibold))
                        Text("\(item.occurrenceCount) occurrences")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(SignalTheme.muted)
                    }
                    Spacer()
                    Button("Restore") { model.restoreDeletedCase(item.id) }
                        .buttonStyle(ModernQuietButtonStyle())
                }
                .padding(12)
                .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func diagnosticsLabel(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(SignalTheme.muted)
    }

    private var emptyReport: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist.unchecked")
                .font(.system(size: 24))
                .foregroundStyle(SignalTheme.lime)
            Text("No sync result yet").font(.system(size: 17, weight: .semibold, design: .rounded))
            Text("Sync recent logs to see what became a failure and why other events were ignored.")
                .font(.system(size: 10))
                .foregroundStyle(SignalTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func dispositionColor(_ disposition: EventDisposition) -> Color {
        switch disposition {
        case .failure: SignalTheme.orange
        case .routine: SignalTheme.muted
        case .unsupported: SignalTheme.yellow
        }
    }
}

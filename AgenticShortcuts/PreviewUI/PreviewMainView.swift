import SwiftUI

struct PreviewMainView: View {
    @State private var vm = PreviewViewModel()
    @State private var showSettingsSheet = false

    var body: some View {
        HSplitView {
            PreviewSidebar(vm: vm)
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 300)

            VSplitView {
                workArea
                    .frame(minHeight: 320)

                PreviewLogsPane(vm: vm)
                    .frame(minHeight: 120, idealHeight: 180, maxHeight: 320)
            }
            .frame(minWidth: 540)

            PreviewInspector(vm: vm)
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
        }
        .frame(minWidth: 1100, minHeight: 700)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars").foregroundStyle(.tint)
                    Text("Agentic Shortcuts").font(.headline)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showSettingsSheet = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    vm.selectedProjectID = nil
                    vm.resetStages()
                    vm.navSelection = .create
                } label: {
                    Label("New", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsView()
                .frame(width: 480, height: 340)
                .padding()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showSettingsSheet = false }
                    }
                }
        }
        .task { await vm.checkOllamaHealth() }
    }

    // MARK: - Main work area

    @ViewBuilder
    private var workArea: some View {
        switch vm.navSelection {
        case .create:    createView
        case .history:   historyPanel
        case .schedules: SchedulesView()
        case .settings:  SettingsView().frame(maxWidth: 540).padding()
        }
    }

    private var createView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Composer + detected schedule row
                HStack(alignment: .top, spacing: 14) {
                    PreviewPromptCard(vm: vm)
                        .frame(maxWidth: .infinity)

                    if let project = vm.selectedProject, let sched = project.schedule {
                        PreviewDetectedScheduleCard(schedule: sched)
                            .frame(width: 240)
                    }
                }

                PreviewPipelineStepper(stageStates: vm.stageStates)
                    .padding(.vertical, 4)

                // Code + results row
                if let project = vm.selectedProject, !project.cherriCode.isEmpty {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            PreviewExamplesDisclosure(count: 3)
                            PreviewCodeBlock(
                                filename: filename(for: project),
                                code: project.cherriCode,
                                onCopy: { copyCode(project.cherriCode) },
                                onEdit: { },
                                onExpand: { }
                            )
                            .frame(minHeight: 320)
                        }
                        .frame(maxWidth: .infinity)

                        VStack(spacing: 14) {
                            PreviewCompileResultCard(
                                project: project,
                                durationSeconds: vm.compileDuration,
                                isSigning: vm.isSigning,
                                signMessage: vm.signMessage,
                                onSignAndOpen: { Task { await vm.signAndOpen() } },
                                onSignAndSaveAs: { Task { await vm.signAndSaveAs() } },
                                onReveal: { vm.revealInFinder() }
                            )
                            if let sched = project.schedule {
                                PreviewScheduleCard(
                                    schedule: sched,
                                    isInstalled: project.isScheduleInstalled,
                                    onManage: { vm.navSelection = .schedules }
                                )
                            }
                        }
                        .frame(width: 280)
                    }
                } else if vm.generator.isGenerating {
                    placeholderCard
                } else {
                    emptyHint
                }
            }
            .padding(16)
        }
        .background(.background.secondary)
    }

    private var placeholderCard: some View {
        PreviewCard(title: nil, systemImage: nil) {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading) {
                    Text(vm.generator.currentStatus.isEmpty ? "Working…" : vm.generator.currentStatus)
                        .font(.callout.weight(.medium))
                    Text("The pipeline above shows live progress.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var emptyHint: some View {
        PreviewCard(title: nil, systemImage: nil) {
            VStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title)
                    .foregroundStyle(.tint)
                Text("Describe a shortcut and press Generate")
                    .font(.callout)
                Text("Example: \"Fetch the weather for San Francisco and show me the temperature.\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        }
    }

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("History").font(.title3.weight(.semibold))
                Spacer()
                Text("\(vm.projects.count) shortcut\(vm.projects.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding()
            Divider()
            List(selection: $vm.selectedProjectID) {
                ForEach(vm.projects) { project in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name.isEmpty ? project.prompt : project.name)
                                .font(.callout)
                            Text(project.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        statusChip(project.status)
                    }
                    .tag(project.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        vm.selectedProjectID = project.id
                        vm.navSelection = .create
                    }
                }
            }
            .listStyle(.inset)
        }
        .background(.background)
    }

    @ViewBuilder
    private func statusChip(_ status: ShortcutProject.Status) -> some View {
        switch status {
        case .compiled:
            Text("Compiled").font(.caption2)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(.green.opacity(0.15)).foregroundStyle(.green).clipShape(Capsule())
        case .failed:
            Text("Failed").font(.caption2)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(.red.opacity(0.15)).foregroundStyle(.red).clipShape(Capsule())
        case .generating:
            Text("Working").font(.caption2)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(.orange.opacity(0.15)).foregroundStyle(.orange).clipShape(Capsule())
        }
    }

    private func filename(for project: ShortcutProject) -> String {
        let base = (project.name.isEmpty ? project.prompt : project.name)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        return "\(base).cherri"
    }

    private func copyCode(_ code: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        #endif
    }
}

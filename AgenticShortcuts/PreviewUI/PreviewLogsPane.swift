import SwiftUI

struct PreviewLogsPane: View {
    @Bindable var vm: PreviewViewModel
    @State private var selectedTab: Tab = .messages

    enum Tab { case messages, raw }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                tabButton("Messages", .messages)
                tabButton("Raw Model Response", .raw)
                Spacer()
                Button {
                    // expand to a separate window placeholder
                } label: {
                    Text("Show Full Log")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .padding(.trailing, 12)
            }
            .padding(.top, 6)
            .background(.background.secondary)
            Divider()

            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    if selectedTab == .messages {
                        messagesView
                    } else {
                        rawResponseView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if vm.firstAttemptError != nil && selectedTab == .messages {
                    errorCallout
                        .frame(width: 320)
                        .padding(10)
                }
            }
        }
        .background(.background.secondary)
    }

    private func tabButton(_ title: String, _ tab: Tab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                .background(
                    Rectangle()
                        .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                        .frame(height: 2)
                        .padding(.top, 24)
                        .padding(.horizontal, 6),
                    alignment: .bottom
                )
        }
        .buttonStyle(.plain)
    }

    private var messagesView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if vm.logs.isEmpty {
                Text("Generate a shortcut to see pipeline messages here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 16)
            } else {
                ForEach(vm.logs) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        icon(for: entry.kind)
                            .frame(width: 14)
                        Text(timestamp(entry.timestamp))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(entry.message)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var rawResponseView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if vm.rawModelResponse.isEmpty {
                Text("No model response yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 16)
            } else {
                Text(vm.rawModelResponse)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
    }

    @ViewBuilder
    private func icon(for kind: PreviewLogEntry.Kind) -> some View {
        switch kind {
        case .info:    Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(.secondary)
        case .success: Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
        case .warning: Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
        case .error:   Image(systemName: "xmark.octagon.fill").font(.caption).foregroundStyle(.red)
        case .retry:   Image(systemName: "arrow.clockwise.circle.fill").font(.caption).foregroundStyle(.orange)
        }
    }

    private func timestamp(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: date)
    }

    private var errorCallout: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                Text("First attempt error")
                    .font(.caption.weight(.semibold))
            }
            if let err = vm.firstAttemptError ?? vm.selectedProject?.compilationError {
                Text(err)
                    .font(.system(.caption2, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .background(.red.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.red.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

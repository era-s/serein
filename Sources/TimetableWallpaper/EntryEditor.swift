import SwiftUI

struct EntryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var entry: ScheduleEntry
    var otherEntries: [ScheduleEntry]
    var onSave: (ScheduleEntry) -> Void
    var onDelete: (() -> Void)? = nil
    @State private var start = ""
    @State private var end = ""

    private var proposed: ScheduleEntry? {
        guard let startTime = Self.parseTime(start), let endTime = Self.parseTime(end) else { return nil }
        var value = entry
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.location = value.location.trimmingCharacters(in: .whitespacesAndNewlines)
        value.startMinutes = startTime
        value.endMinutes = endTime
        return value
    }
    private var validation: String? {
        guard let proposed else { return "시간은 09:00처럼 입력해주세요. (00:00–24:00)" }
        return proposed.validationError
    }
    private var overlapping: Bool {
        guard let proposed else { return false }
        return otherEntries.contains { proposed.overlaps($0) }
    }
    static func parseTime(_ text: String) -> Int? {
        let components = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 2, let h = Int(components[0]), let m = Int(components[1]),
              (0...24).contains(h), (0...59).contains(m), h != 24 || m == 0 else { return nil }
        return h * 60 + m
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("A PLACE IN YOUR WEEK").font(.system(size: 9, design: .monospaced)).tracking(1.5).foregroundStyle(StudioStyle.accent)
                    Text(entry.name.isEmpty ? "새로운 일정" : "일정 다듬기").font(.system(size: 25, weight: .medium))
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 12)) }.buttonStyle(.plain).foregroundStyle(StudioStyle.muted)
            }
            VStack(alignment: .leading, spacing: 9) {
                Text("과목 또는 일정").font(.system(size: 11, weight: .medium))
                TextField("예: 시각디자인 스튜디오", text: $entry.name).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("entry-name")
                    .onChange(of: entry.name) { _, value in if value.count > 100 { entry.name = String(value.prefix(100)) } }
            }
            VStack(alignment: .leading, spacing: 9) {
                Text("요일").font(.system(size: 11, weight: .medium))
                Picker("요일", selection: $entry.day) {
                    ForEach(0..<7, id: \.self) { day in Text(ScheduleEntry.dayNames[day]).tag(day) }
                }.pickerStyle(.segmented).labelsHidden()
            }
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("시작 시간").font(.system(size: 11, weight: .medium))
                    TextField("09:00", text: $start).textFieldStyle(.roundedBorder).accessibilityLabel("시작 시간")
                }
                Text("—").foregroundStyle(StudioStyle.muted).padding(.top, 20)
                VStack(alignment: .leading, spacing: 9) {
                    Text("종료 시간").font(.system(size: 11, weight: .medium))
                    TextField("10:30", text: $end).textFieldStyle(.roundedBorder).accessibilityLabel("종료 시간")
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                Text("장소 또는 메모 · 선택").font(.system(size: 11, weight: .medium))
                TextField("예: 디자인관 302호", text: $entry.location).textFieldStyle(.roundedBorder)
                    .onChange(of: entry.location) { _, value in if value.count > 100 { entry.location = String(value.prefix(100)) } }
            }
            if let validation {
                Label(validation, systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(StudioStyle.accent)
            } else if overlapping {
                Label("같은 시간의 일정이 있습니다. 나란히 표시됩니다.", systemImage: "rectangle.split.2x1").font(.system(size: 11)).foregroundStyle(StudioStyle.accent)
            }
            HStack {
                if let onDelete {
                    Button("삭제", role: .destructive) { onDelete(); dismiss() }.buttonStyle(.plain).foregroundStyle(StudioStyle.accent)
                }
                Spacer()
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(StudioButtonStyle(primary: false))
                Button("일정 저장") {
                    guard let proposed, proposed.validationError == nil else { return }
                    onSave(proposed)
                    dismiss()
                }.keyboardShortcut(.defaultAction).buttonStyle(StudioButtonStyle(primary: true)).disabled(validation != nil)
            }
        }
        .padding(30).frame(width: 430).background(StudioStyle.sidebar).foregroundStyle(StudioStyle.ink)
        .onAppear { start = ScheduleEntry.time(entry.startMinutes); end = ScheduleEntry.time(entry.endMinutes) }
    }
}

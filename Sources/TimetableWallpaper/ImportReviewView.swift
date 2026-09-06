import AppKit
import SwiftUI

struct ImportReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let result: OCRImportResult
    let sourceImage: NSImage?
    let onImport: ([ScheduleEntry], Bool) -> Void
    @State private var entries: [ScheduleEntry]
    @State private var selected: Set<UUID>
    @State private var editingEntry: ScheduleEntry?
    @State private var replace = true
    @State private var confirmed = false

    init(result: OCRImportResult, sourceImage: NSImage?, onImport: @escaping ([ScheduleEntry], Bool) -> Void) {
        self.result = result
        self.sourceImage = sourceImage
        self.onImport = onImport
        _entries = State(initialValue: result.entries)
        _selected = State(initialValue: Set(result.entries.map(\.id)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("READ. REVIEW. MAKE IT YOURS.").font(.system(size: 9, design: .monospaced)).tracking(1.4).foregroundStyle(StudioStyle.accent)
                    Text("인식한 시간표를 확인해주세요").font(.system(size: 24, weight: .medium))
                    Text("요일, 시작·종료 시간을 원본과 비교하고 수정할 수 있어요.").font(.system(size: 12)).foregroundStyle(StudioStyle.muted)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("원본 이미지").font(.system(size: 11, weight: .medium))
                    if let sourceImage {
                        ScrollView([.horizontal, .vertical]) {
                            Image(nsImage: sourceImage).resizable().scaledToFit().frame(width: 330)
                        }.frame(width: 350, height: 370).background(.white, in: RoundedRectangle(cornerRadius: 8))
                    }
                    DisclosureGroup("인식한 텍스트 보기") {
                        ScrollView { Text(result.recognizedText.isEmpty ? "인식한 텍스트가 없습니다." : result.recognizedText).font(.system(size: 10)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 110)
                    }.font(.system(size: 11)).frame(width: 350)
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("일정 \(entries.count)개").font(.system(size: 12, weight: .medium))
                        Spacer()
                        Button { editingEntry = .init(name: "", day: 0, startMinutes: 540, endMinutes: 600) } label: { Label("추가", systemImage: "plus") }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(StudioStyle.accent)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if entries.isEmpty {
                                Text("요일과 시간 구조를 확실히 찾지 못했습니다. 원본 또는 인식한 텍스트를 참고해 일정을 추가해주세요.")
                                    .font(.system(size: 12)).foregroundStyle(StudioStyle.muted).lineSpacing(5).padding(.vertical, 16)
                            }
                            ForEach(entries) { entry in
                                HStack(alignment: .top, spacing: 9) {
                                    Toggle("포함", isOn: Binding(get: { selected.contains(entry.id) }, set: {
                                        if $0 { selected.insert(entry.id) } else { selected.remove(entry.id) }
                                        confirmed = false
                                    })).labelsHidden().toggleStyle(.checkbox).padding(.top, 2)
                                        .accessibilityLabel("\(entry.name), \(ScheduleEntry.dayNames[entry.day])요일 \(entry.timeLabel), 포함")
                                    Button { editingEntry = entry } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(entry.name).font(.system(size: 12, weight: .medium))
                                            Text("\(ScheduleEntry.dayNames[entry.day]) · \(entry.timeLabel)").font(.system(size: 10, design: .monospaced)).foregroundStyle(StudioStyle.accent)
                                            if !entry.location.isEmpty { Text(entry.location).font(.system(size: 10)).foregroundStyle(StudioStyle.muted) }
                                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                    Image(systemName: "pencil").font(.system(size: 10)).foregroundStyle(StudioStyle.muted)
                                }.padding(12).background(StudioStyle.paper, in: RoundedRectangle(cornerRadius: 7))
                            }
                            ForEach(result.warnings, id: \.self) { warning in
                                Label(warning, systemImage: "info.circle").font(.system(size: 10)).foregroundStyle(StudioStyle.accent).lineSpacing(3)
                            }
                        }
                    }.frame(height: 385)
                }.frame(width: 350)
            }
            Divider()
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("기존 시간표를 이 일정으로 교체", isOn: $replace)
                    Toggle("선택한 일정의 요일과 시간을 확인했습니다", isOn: $confirmed)
                }.toggleStyle(.checkbox).font(.system(size: 11))
                Spacer()
                Button("취소") { dismiss() }.buttonStyle(StudioButtonStyle(primary: false)).keyboardShortcut(.cancelAction)
                Button("\(selected.count)개 일정 반영") {
                    onImport(entries.filter { selected.contains($0.id) }, replace)
                    dismiss()
                }.buttonStyle(StudioButtonStyle(primary: true)).disabled(!confirmed || selected.isEmpty)
            }
        }.padding(28).frame(width: 800).background(StudioStyle.sidebar).foregroundStyle(StudioStyle.ink)
            .sheet(item: $editingEntry) { entry in
                EntryEditor(entry: entry, otherEntries: entries) { updated in
                    if let index = entries.firstIndex(where: { $0.id == updated.id }) { entries[index] = updated }
                    else { entries.append(updated); selected.insert(updated.id) }
                    confirmed = false
                }
            }
    }
}

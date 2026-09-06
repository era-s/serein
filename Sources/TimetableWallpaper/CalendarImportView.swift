import SwiftUI
import EventKit

struct CalendarImportView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: CalendarImportModel
    let existingEntries: [ScheduleEntry]
    let onImport: ([ScheduleEntry], Bool, String?) -> Void
    @State private var editingEntry: ScheduleEntry?
    @State private var replace = true
    @State private var includeWeekTitle = true
    @State private var showGoogleHelp = false

    init(model: CalendarImportModel, existingEntries: [ScheduleEntry],
         onImport: @escaping ([ScheduleEntry], Bool, String?) -> Void) {
        _model = StateObject(wrappedValue: model)
        self.existingEntries = existingEntries
        self.onImport = onImport
    }

    private var selectedEntries: [ScheduleEntry] {
        model.reviewEntries.filter { model.selectedEntryIDs.contains($0.id) }
    }

    private var canImport: Bool {
        model.canImport && selectedEntries.allSatisfy { $0.validationError == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.bottom, 22)
            HStack(alignment: .top, spacing: 22) {
                sourcePanel.frame(width: 270)
                Rectangle().fill(StudioStyle.line).frame(width: 1)
                reviewPanel.frame(maxWidth: .infinity)
            }.frame(maxHeight: .infinity)
            Rectangle().fill(StudioStyle.line).frame(height: 1).padding(.top, 19).padding(.bottom, 17)
            footer
        }
        .padding(28).frame(width: 850, height: 700)
        .background(StudioStyle.sidebar).foregroundStyle(StudioStyle.ink).tint(StudioStyle.accent)
        .task { await model.loadIfAuthorized() }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            guard !model.isDemo else { return }
            model.invalidateResult()
            Task { await model.refreshCalendars() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshAfterExternalChange()
        }
        .onDisappear { model.invalidateResult() }
        .sheet(item: $editingEntry) { entry in
            EntryEditor(entry: entry, otherEntries: model.reviewEntries + (replace ? [] : existingEntries)) {
                model.updateEntry($0)
            }
        }
        .onChange(of: replace) { _, _ in model.confirmed = false }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("FROM YOUR CALENDAR, INTO YOUR SPACE.")
                    .font(.system(size: 9, design: .monospaced)).tracking(1.4).foregroundStyle(StudioStyle.accent)
                Text("캘린더에서 가져오기").font(.system(size: 25, weight: .medium))
                Text("Apple Calendar와 Mac에 연결한 Google Calendar를 배경화면으로.")
                    .font(.system(size: 12)).foregroundStyle(StudioStyle.muted)
                if model.isDemo {
                    Label("연동 화면 예시 · 실제 계정 아님", systemImage: "info.circle")
                        .font(.system(size: 10)).foregroundStyle(StudioStyle.accent)
                }
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 12)).foregroundStyle(StudioStyle.muted)
            }.buttonStyle(.plain).accessibilityLabel("캘린더 가져오기 닫기")
        }
    }

    private var sourcePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                HStack {
                    sectionLabel("01", "가져올 캘린더")
                    Spacer()
                    if model.access == .authorized {
                        Button { Task { await model.refreshCalendars() } } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 11))
                        }.buttonStyle(.plain).foregroundStyle(StudioStyle.accent)
                            .disabled(model.isLoading).help("캘린더 목록 새로고침")
                            .accessibilityLabel("캘린더 목록 새로고침")
                    }
                }
                if model.access == .authorized { calendarList }
                else { permissionPanel }
                googleHelp
                Rectangle().fill(StudioStyle.line).frame(height: 1)
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("02", "한 주 선택")
                    DatePicker("기준 날짜", selection: $model.selectedDate, displayedComponents: .date)
                        .datePickerStyle(.field).font(.system(size: 11))
                        .environment(\.locale, Locale(identifier: "ko_KR"))
                        .environment(\.timeZone, model.week.timeZone)
                        .disabled(model.isLoading)
                        .accessibilityIdentifier("calendar-week-date")
                    VStack(alignment: .leading, spacing: 7) {
                        Text(model.week.label).font(.system(size: 11, weight: .medium, design: .monospaced))
                        Text("월요일부터 일요일까지 · \(model.week.timeZone.identifier)")
                            .font(.system(size: 9)).foregroundStyle(StudioStyle.muted).fixedSize(horizontal: false, vertical: true)
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(StudioStyle.paper, in: RoundedRectangle(cornerRadius: 7))
                    Button { Task { await model.fetchEvents() } } label: {
                        Label(model.result == nil ? "이 주의 일정 가져오기" : "이 주의 일정 새로고침", systemImage: "arrow.down.to.line")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(StudioButtonStyle(primary: true))
                        .disabled(model.access != .authorized || model.selectedCalendarIDs.isEmpty || model.isLoading)
                        .accessibilityIdentifier("fetch-calendar-events")
                }
            }.padding(.trailing, 2)
        }
    }

    private var calendarList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.calendars.isEmpty {
                Text("연결된 캘린더가 없습니다. Mac의 캘린더 앱에서 계정을 추가한 뒤 목록을 새로고침해주세요.")
                    .font(.system(size: 11)).foregroundStyle(StudioStyle.muted).lineSpacing(4)
                    .padding(13).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(model.calendars) { calendar in
                    HStack(alignment: .top, spacing: 10) {
                        Toggle("포함", isOn: Binding(
                            get: { model.selectedCalendarIDs.contains(calendar.id) },
                            set: { selected in
                                if selected { model.selectedCalendarIDs.insert(calendar.id) }
                                else { model.selectedCalendarIDs.remove(calendar.id) }
                            }
                        )).labelsHidden().toggleStyle(.checkbox).padding(.top, 1)
                            .accessibilityLabel("\(calendar.account), \(calendar.title), 캘린더 선택")
                        Circle().fill(Color(hex: calendar.colorHex)).frame(width: 7, height: 7).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(calendar.title).font(.system(size: 11, weight: .medium)).lineLimit(2)
                            Text(calendar.account).font(.system(size: 9)).foregroundStyle(StudioStyle.muted).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }.padding(12)
                    if calendar.id != model.calendars.last?.id {
                        Rectangle().fill(StudioStyle.line).frame(height: 1).padding(.horizontal, 12)
                    }
                }
            }
        }.background(StudioStyle.paper, in: RoundedRectangle(cornerRadius: 8)).disabled(model.isLoading)
    }

    private var permissionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "calendar.badge.clock").font(.system(size: 25, weight: .ultraLight)).foregroundStyle(StudioStyle.accent)
            Text(permissionTitle).font(.system(size: 12, weight: .medium))
            Text(permissionExplanation).font(.system(size: 11)).foregroundStyle(StudioStyle.muted).lineSpacing(4)
            if model.access == .notDetermined {
                Button("캘린더 연결") { Task { await model.connect() } }
                    .buttonStyle(StudioButtonStyle(primary: true)).disabled(model.isLoading)
                    .accessibilityIdentifier("connect-calendar")
            } else {
                Button("캘린더 접근 설정 열기", action: model.openPrivacySettings)
                    .buttonStyle(StudioButtonStyle(primary: false))
                Button("권한 상태 다시 확인") { Task { await model.loadIfAuthorized() } }
                    .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(StudioStyle.accent).disabled(model.isLoading)
            }
        }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
            .background(StudioStyle.paper, in: RoundedRectangle(cornerRadius: 8))
    }

    private var permissionTitle: String {
        switch model.access {
        case .notDetermined: "내 캘린더와 연결하기"
        case .denied: "캘린더 접근이 꺼져 있어요"
        case .restricted: "캘린더 접근이 제한되어 있어요"
        case .authorized: "캘린더가 연결되었어요"
        }
    }

    private var permissionExplanation: String {
        switch model.access {
        case .notDetermined:
            "macOS는 일정을 읽을 때 ‘전체 접근’(읽기·쓰기) 권한을 요청합니다. Serein은 일정을 읽기만 하며 원본을 수정하지 않습니다."
        case .denied:
            "시스템 설정 → 개인정보 보호 및 보안 → 캘린더에서 Serein의 전체 접근을 허용해주세요."
        case .restricted:
            "기기 관리 또는 보호 설정으로 접근이 제한되었습니다. 설정을 확인하고, 관리되는 Mac이라면 관리자에게 문의해주세요."
        case .authorized:
            "가져올 캘린더를 선택해주세요."
        }
    }

    private var googleHelp: some View {
        DisclosureGroup(isExpanded: $showGoogleHelp) {
            VStack(alignment: .leading, spacing: 10) {
                Text("시스템 설정 → 인터넷 계정 → Google에서 로그인한 뒤 ‘캘린더’를 켜주세요. Apple Calendar에 일정이 나타나면 여기서 목록을 새로고침하세요.")
                    .font(.system(size: 10)).lineSpacing(4).foregroundStyle(StudioStyle.muted)
                Button("인터넷 계정 설정 열기", action: model.openAccountsSettings)
                    .buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundStyle(StudioStyle.accent)
                    .accessibilityIdentifier("open-calendar-accounts")
            }.padding(.top, 8)
        } label: {
            Text("Google Calendar 연결 방법").font(.system(size: 11))
        }
    }

    private var reviewPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionLabel("03", "일정 확인")
                Spacer()
                if model.result != nil {
                    Text("\(selectedEntries.count) / \(model.reviewEntries.count)개 선택")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(StudioStyle.muted)
                }
            }
            Text("가져온 일정의 이름·요일·시간을 눌러 다듬을 수 있어요.")
                .font(.system(size: 10)).foregroundStyle(StudioStyle.muted)
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(StudioStyle.accent).lineSpacing(3)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(StudioStyle.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            }
            if model.isLoading {
                VStack(spacing: 14) {
                    ProgressView().controlSize(.small)
                    Text("캘린더를 불러오고 있어요…").font(.system(size: 12)).foregroundStyle(StudioStyle.muted)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result = model.result {
                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        if model.reviewEntries.isEmpty {
                            emptyReview(symbol: "calendar", title: "이 주에는 가져올 일정이 없어요",
                                        detail: "선택한 캘린더에 시간이 지정된 일정이 없습니다. 다른 캘린더나 주를 선택해보세요.")
                        } else {
                            HStack(spacing: 10) {
                                Button("모두 선택") { model.selectedEntryIDs = Set(model.reviewEntries.map(\.id)); model.confirmed = false }
                                Button("선택 해제") { model.selectedEntryIDs = []; model.confirmed = false }
                            }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(StudioStyle.accent).padding(.bottom, 3)
                            ForEach(model.reviewEntries) { entry in entryRow(entry) }
                        }
                        if result.allDayCount > 0 {
                            notice("종일 일정 \(result.allDayCount)개는 시간 블록에서 제외했습니다.", symbol: "sun.max")
                        }
                        if result.excludedCount > 0 {
                            notice("취소·거절되었거나 가져올 수 없는 일정 \(result.excludedCount)개를 제외했습니다.", symbol: "minus.circle")
                        }
                        ForEach(Array(result.warnings.enumerated()), id: \.offset) { _, warning in
                            notice(warning, symbol: "info.circle")
                        }
                    }.padding(.trailing, 2)
                }
            } else {
                emptyReview(symbol: "calendar.badge.plus", title: "한 주의 리듬을 가져오세요",
                            detail: "왼쪽에서 캘린더와 날짜를 선택한 뒤\n‘이 주의 일정 가져오기’를 눌러주세요.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func entryRow(_ entry: ScheduleEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("포함", isOn: Binding(
                get: { model.selectedEntryIDs.contains(entry.id) },
                set: { selected in
                    if selected { model.selectedEntryIDs.insert(entry.id) }
                    else { model.selectedEntryIDs.remove(entry.id) }
                    model.confirmed = false
                }
            )).labelsHidden().toggleStyle(.checkbox).padding(.top, 2)
                .accessibilityLabel("\(entry.name), \(ScheduleEntry.dayNames[entry.day])요일 \(entry.timeLabel), 포함")
            Button { editingEntry = entry } label: {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.name).font(.system(size: 12, weight: .medium)).lineLimit(2)
                        Text("\(ScheduleEntry.dayNames[entry.day]) · \(entry.timeLabel)")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(StudioStyle.accent)
                        if !entry.location.isEmpty {
                            Text(entry.location).font(.system(size: 10)).foregroundStyle(StudioStyle.muted).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 5)
                    Image(systemName: "pencil").font(.system(size: 10)).foregroundStyle(StudioStyle.muted).padding(.top, 2)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(entry.name) 일정 수정")
        }.padding(12).background(StudioStyle.paper, in: RoundedRectangle(cornerRadius: 7))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 15) {
                VStack(alignment: .leading, spacing: 9) {
                    Toggle("기존 시간표를 이 일정으로 교체", isOn: $replace)
                    Toggle("선택한 주를 제목에 표시", isOn: $includeWeekTitle)
                    Toggle("선택한 일정의 요일과 시간을 확인했습니다", isOn: $model.confirmed)
                        .disabled(model.result == nil || model.isLoading || selectedEntries.isEmpty)
                        .accessibilityIdentifier("confirm-calendar-review")
                }.toggleStyle(.checkbox).font(.system(size: 11))
                Spacer(minLength: 0)
                Button("취소") { dismiss() }.buttonStyle(StudioButtonStyle(primary: false)).keyboardShortcut(.cancelAction)
                Button("\(selectedEntries.count)개 일정 반영") {
                    guard model.validateForImport() else { return }
                    onImport(selectedEntries, replace, includeWeekTitle ? model.week.label : nil)
                    dismiss()
                }.buttonStyle(StudioButtonStyle(primary: true)).disabled(!canImport)
                    .accessibilityIdentifier("apply-calendar-events")
            }
            Text("선택한 주의 일정을 복사합니다. 캘린더 변경 사항은 다시 가져온 뒤 반영해주세요.")
                .font(.system(size: 10)).foregroundStyle(StudioStyle.muted)
        }
    }

    private func sectionLabel(_ number: String, _ title: String) -> some View {
        HStack(spacing: 8) {
            Text(number).font(.system(size: 9, design: .monospaced)).foregroundStyle(StudioStyle.accent)
            Text(title).font(.system(size: 12, weight: .medium))
        }
    }

    private func notice(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 10)).foregroundStyle(StudioStyle.accent)
            .lineSpacing(3).padding(.top, 4).fixedSize(horizontal: false, vertical: true)
    }

    private func emptyReview(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 13) {
            Image(systemName: symbol).font(.system(size: 33, weight: .ultraLight)).foregroundStyle(StudioStyle.accent.opacity(0.7))
            Text(title).font(.system(size: 13, weight: .medium))
            Text(detail).font(.system(size: 11)).foregroundStyle(StudioStyle.muted).lineSpacing(5).multilineTextAlignment(.center)
        }.padding(.horizontal, 20).padding(.vertical, 35).frame(maxWidth: .infinity)
    }
}

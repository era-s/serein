import SwiftUI

struct HiddenCalendarEntriesView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A LITTLE LESS, A LITTLE CLEARER.")
                        .font(.system(size: 9, design: .monospaced)).tracking(1.4).foregroundStyle(StudioStyle.accent)
                    Text("숨긴 일정").font(.system(size: 27, weight: .medium))
                    Text("캘린더에는 그대로, 배경화면에서는 잠시 빼두세요.")
                        .font(.system(size: 12)).foregroundStyle(StudioStyle.muted)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("숨긴 일정 닫기")
            }
            if store.isDemo {
                Label("예시 일정 · 실제 캘린더와 저장된 작업은 변경하지 않습니다.", systemImage: "info.circle")
                    .font(.system(size: 11)).foregroundStyle(StudioStyle.accent)
            }
            ScrollView {
                LazyVStack(spacing: 10) {
                    if store.calendarVisibility.exclusions.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "eye").font(.system(size: 30, weight: .ultraLight))
                            Text("숨긴 일정이 없습니다.").font(.system(size: 14, weight: .medium))
                            Text("시간표에서 캘린더 일정을 열어 ‘배경화면에서 숨기기’를 누르면\n동기화 뒤에도 나타나지 않습니다.")
                                .font(.system(size: 11)).multilineTextAlignment(.center).lineSpacing(4)
                        }.foregroundStyle(StudioStyle.muted).frame(maxWidth: .infinity).padding(.vertical, 64)
                    } else {
                        ForEach(store.calendarVisibility.exclusions) { hidden in
                            HStack(alignment: .center, spacing: 14) {
                                Image(systemName: "eye.slash").foregroundStyle(StudioStyle.accent)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(hidden.entry.name).font(.system(size: 13, weight: .medium)).lineLimit(2)
                                    Text(hidden.scope == .event ? "이후 반복 일정도 계속 숨김" : "이번 회차만 숨김")
                                        .font(.system(size: 10)).foregroundStyle(StudioStyle.accent)
                                    Text("마지막 확인 · \(ScheduleEntry.dayNames[hidden.entry.day]) \(hidden.entry.timeLabel)")
                                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(StudioStyle.muted)
                                }
                                Spacer(minLength: 8)
                                Button("다시 표시") { store.restoreHiddenCalendarEntry(hidden.id) }
                                    .buttonStyle(StudioButtonStyle(primary: false))
                                    .accessibilityLabel("\(hidden.entry.name) 다시 표시")
                            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                .background(StudioStyle.paper, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }.frame(maxHeight: .infinity)
            Text(store.automationSettings.hasCalendarAutomation
                 ? "다시 표시하면 현재 연결한 캘린더의 최신 일정을 확인합니다. 현재 주에 없거나 연결하지 않은 캘린더의 일정은 다음에 해당 주와 캘린더를 가져올 때 표시됩니다."
                 : "자동 교체가 꺼져 있습니다. 숨김을 해제한 뒤 캘린더에서 다시 가져오면 표시됩니다.")
                .font(.system(size: 10)).foregroundStyle(StudioStyle.muted).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("원본 Apple·Google 캘린더의 일정은 변경하지 않습니다.")
                    .font(.system(size: 10)).foregroundStyle(StudioStyle.muted)
                Spacer()
                Button("완료") { dismiss() }.buttonStyle(StudioButtonStyle(primary: true)).keyboardShortcut(.cancelAction)
            }
        }.padding(28).frame(width: 640, height: 570)
            .background(StudioStyle.sidebar).foregroundStyle(StudioStyle.ink).tint(StudioStyle.accent)
    }
}

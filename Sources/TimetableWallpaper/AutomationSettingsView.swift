import SwiftUI

struct AutomationSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A FRESH WEEK. WITHOUT A SECOND THOUGHT.")
                        .font(.system(size: 9, design: .monospaced)).tracking(1.4).foregroundStyle(StudioStyle.accent)
                    Text("늘, 지금의 시간표").font(.system(size: 27, weight: .medium))
                    Text("일정은 바뀌어도, 내 배경화면은 자연스럽게 따라오도록.")
                        .font(.system(size: 12)).foregroundStyle(StudioStyle.muted)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("자동화 설정 닫기")
            }
            if store.isDemo {
                Label("자동화 예시 · 실제 캘린더, 배경화면, 로그인 항목은 변경하지 않습니다.", systemImage: "info.circle")
                    .font(.system(size: 11)).foregroundStyle(StudioStyle.accent)
            }
            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 12) {
                    option("arrow.triangle.2.circlepath", title: "일정이 바뀌면 자동 교체", detail: "선택한 캘린더의 이번 주 일정이 바뀌었을 때만 배경화면을 갱신합니다.",
                           value: $store.automationSettings.refreshOnCalendarChange, id: "auto-calendar-change", needsCalendar: true)
                    option("calendar", title: "매주 새로운 배경화면", detail: "월요일이 되면 새 주의 일정을 가져옵니다. 잠자기 중이었다면 깨어난 뒤 반영합니다.",
                           value: $store.automationSettings.refreshWeekly, id: "auto-weekly", needsCalendar: true)
                    option("rectangle.inset.filled", title: "오늘을 은은하게 표시", detail: "오늘 열에 얇은 테두리를 더합니다. 한 번 적용한 뒤에는 날짜에 맞춰 매일 이동합니다.",
                           value: $store.automationSettings.showToday, id: "auto-today", needsCalendar: false)
                    Text("자동 교체를 켜면 선택한 캘린더의 이번 주 시간 지정 일정을 모두 반영하고 바로 적용합니다. 수동으로 추가한 일정은 유지합니다.")
                        .font(.system(size: 10)).foregroundStyle(StudioStyle.muted).lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 2)
                }.frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 19) {
                    VStack(alignment: .leading, spacing: 10) {
                        caption("CONNECTED CALENDARS")
                        if let connection = store.calendarConnection {
                            Text(connection.calendarNames.joined(separator: " · ")).font(.system(size: 12, weight: .medium))
                            Text(CalendarWeek(containing: connection.weekStart, timeZone: TimeZone(identifier: connection.timeZoneID) ?? .current).label)
                                .font(.system(size: 10, design: .monospaced)).foregroundStyle(StudioStyle.muted)
                            Text("자동 갱신 기준: Mac의 현재 시간대").font(.system(size: 9)).foregroundStyle(StudioStyle.muted)
                        } else {
                            Text("먼저 캘린더를 연결해주세요").font(.system(size: 12, weight: .medium))
                            Text("Apple Calendar · Google Calendar").font(.system(size: 10)).foregroundStyle(StudioStyle.muted)
                        }
                        Button(store.calendarConnection == nil ? "캘린더 연결하기 ↗" : "캘린더 다시 선택 ↗") {
                            dismiss()
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(300))
                                store.showCalendarImport = true
                            }
                        }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(StudioStyle.accent)
                        if store.calendarRecovery.access != .authorized || store.automation.needsCalendarReconnect {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("권한 연결을 다시 확인해주세요")
                                    .font(.system(size: 11, weight: .medium)).foregroundStyle(StudioStyle.accent)
                                Text("설정에서 전체 접근이 켜져 있어도 앱 업데이트 후 다시 연결해야 할 수 있어요.")
                                    .font(.system(size: 10)).foregroundStyle(StudioStyle.muted).lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button(action: store.reconnectCalendar) {
                                    HStack(spacing: 7) {
                                        if store.calendarRecovery.isConnecting { ProgressView().controlSize(.mini) }
                                        Text("권한 연결 다시 확인")
                                    }
                                }.buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(StudioStyle.accent)
                                    .disabled(store.calendarRecovery.isConnecting)
                                    .accessibilityIdentifier("reconnect-calendar-access")
                                if let error = store.calendarRecovery.errorMessage {
                                    Text(error).font(.system(size: 10)).foregroundStyle(StudioStyle.accent)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }.padding(.top, 5)
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        caption("APPLY TO")
                        Text("배경화면 적용 범위").font(.system(size: 11, weight: .medium))
                        Picker("배경화면 적용 범위", selection: Binding(
                            get: { store.automationSettings.targetDisplayID ?? WallpaperDisplay.allSpacesID }, set: { store.selectDisplay($0) })) {
                            ForEach(store.displays) { display in
                                Text(display.id == WallpaperDisplay.allSpacesID ? display.name : "\(display.name) · 현재 데스크탑만")
                                    .tag(display.id)
                            }
                            if let id = store.automationSettings.targetDisplayID, !store.displays.contains(where: { $0.id == id }) {
                                Text("\(store.automationSettings.targetDisplayName ?? "저장한 디스플레이") · 연결 끊김").tag(id)
                            }
                        }.labelsHidden().accessibilityLabel("배경화면 적용 범위")
                        Text(store.automationSettings.targetDisplayID == WallpaperDisplay.allSpacesID
                             ? "데스크탑 1·2를 포함한 모든 Spaces와 디스플레이에 같은 배경화면을 적용합니다."
                             : "선택한 디스플레이의 현재 데스크탑만 변경합니다. 연결이 끊기면 해당 화면이 돌아올 때까지 기다립니다.")
                            .font(.system(size: 10)).foregroundStyle(StudioStyle.muted).lineSpacing(3)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 9) {
                        Toggle("로그인할 때 Serein 실행", isOn: Binding(get: { store.loginEnabled }, set: { store.setLoginEnabled($0) }))
                            .font(.system(size: 11)).toggleStyle(.switch).controlSize(.small)
                        Text("창을 닫아도 메뉴 막대에서 작동합니다. 앱을 종료한 동안에는 갱신하지 않습니다.")
                            .font(.system(size: 10)).foregroundStyle(StudioStyle.muted).lineSpacing(3)
                        if store.loginNeedsApproval {
                            Button("시스템 설정에서 로그인 항목 허용", action: store.openLoginSettings)
                                .font(.system(size: 10)).foregroundStyle(StudioStyle.accent)
                        }
                    }
                }.padding(19).frame(width: 263).background(StudioStyle.paper, in: RoundedRectangle(cornerRadius: 12))
            }
            HStack(alignment: .center, spacing: 12) {
                if store.automation.isChecking { ProgressView().controlSize(.small) }
                else { Image(systemName: store.automationSettings.hasAutomation ? "clock.badge.checkmark" : "pause.circle").foregroundStyle(StudioStyle.accent) }
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.automation.status).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                    if let last = store.automation.lastAppliedAt {
                        Text("마지막 적용 \(last.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 9)).foregroundStyle(StudioStyle.muted)
                    }
                }
                Spacer(minLength: 10)
                Button("지금 확인", action: store.checkNow).buttonStyle(StudioButtonStyle(primary: false))
                    .disabled(!store.automationSettings.hasAutomation || store.automation.isChecking)
            }.padding(16).background(StudioStyle.paper, in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Text("옵션을 끄면 자동 갱신이 멈춥니다. 현재 배경화면은 유지됩니다.")
                    .font(.system(size: 10)).foregroundStyle(StudioStyle.muted)
                Spacer()
                Button("완료") { dismiss() }.buttonStyle(StudioButtonStyle(primary: true)).keyboardShortcut(.cancelAction)
            }
        }.padding(28).frame(width: 860)
            .background(StudioStyle.sidebar).foregroundStyle(StudioStyle.ink).tint(StudioStyle.accent)
            .onAppear { store.refreshDisplays(); store.refreshLoginStatus(); store.refreshCalendarAccess() }
    }

    private func caption(_ title: String) -> some View {
        Text(title).font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1.5).foregroundStyle(StudioStyle.muted)
    }
    private func option(_ symbol: String, title: String, detail: String, value: Binding<Bool>, id: String, needsCalendar: Bool) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: symbol).font(.system(size: 19, weight: .light)).foregroundStyle(StudioStyle.accent)
                .frame(width: 25).padding(.top, 2)
            VStack(alignment: .leading, spacing: 8) {
                Toggle(title, isOn: value).font(.system(size: 13, weight: .medium)).toggleStyle(.switch).controlSize(.small)
                    .disabled(needsCalendar && store.calendarConnection == nil).accessibilityIdentifier(id)
                Text(detail).font(.system(size: 11)).foregroundStyle(StudioStyle.muted).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(StudioStyle.paper.opacity(0.6), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(StudioStyle.line, lineWidth: 1))
    }
}

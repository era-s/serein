import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum StudioStyle {
    static let paper = Color(hex: 0xF5F3ED)
    static let sidebar = Color(hex: 0xFCFBF7)
    static let ink = Color(hex: 0x292B25)
    static let muted = Color(hex: 0x828378)
    static let line = Color(hex: 0xE3E2D9)
    static let accent = Color(hex: 0xC45C36)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

struct StudioView: View {
    @EnvironmentObject private var store: AppStore
    @State private var tab = 0
    @State private var editingEntry: ScheduleEntry?
    @State private var showDesktop = false
    @State private var isDropTarget = false
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(StudioStyle.line).frame(height: 1)
            HStack(spacing: 0) {
                sidebar.frame(width: 310)
                Rectangle().fill(StudioStyle.line).frame(width: 1)
                workspace
            }
        }
        .background(StudioStyle.paper)
        .foregroundStyle(StudioStyle.ink)
        .tint(StudioStyle.accent)
        .sheet(item: $editingEntry) { entry in
            EntryEditor(entry: entry, otherEntries: store.entries, onSave: { store.save($0) },
                onDelete: store.entries.contains(where: { $0.id == entry.id }) ? { store.remove(entry.id) } : nil,
                deleteTitle: entry.calendarSourceKey == nil ? "삭제" : "배경화면에서 숨기기",
                deleteDetail: entry.calendarSourceKey == nil ? nil : "숨기면 이후 반복 일정도 제외됩니다. 원본 캘린더는 유지하며, ‘숨긴 일정’에서 되돌릴 수 있습니다.")
        }
        .sheet(isPresented: Binding(get: { store.importResult != nil }, set: { if !$0 { store.importResult = nil } })) {
            if let result = store.importResult {
                ImportReviewView(result: result, sourceImage: store.importImage) { entries, replace in
                    if replace { store.entries = entries } else { store.entries.append(contentsOf: entries) }
                    store.importResult = nil
                    store.message = "\(entries.count)개 일정을 시간표에 반영했습니다."
                }
            }
        }
        .sheet(isPresented: $store.showCalendarImport) {
            let isDemo = store.isDemo
            let model = isDemo
                ? CalendarImportModel(provider: DemoCalendarProvider(), date: DemoCalendarProvider.anchor,
                                      isDemo: true, timeZone: TimeZone(identifier: "Asia/Seoul")!)
                : CalendarImportModel()
            CalendarImportView(model: model, existingEntries: store.entries, calendarVisibility: store.calendarVisibility) { incoming, replace, subtitle, connection, excluded in
                store.importCalendarEntries(incoming, replace: replace, subtitle: subtitle, connection: connection, excluded: excluded)
            }
        }
        .sheet(isPresented: $store.showAutomation) {
            AutomationSettingsView().environmentObject(store)
        }
        .sheet(isPresented: $store.showHiddenCalendarEntries) {
            HiddenCalendarEntriesView().environmentObject(store)
        }
        .alert("작업을 완료하지 못했습니다", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("확인", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
        .confirmationDialog("시간표를 모두 비울까요?", isPresented: $showClearConfirmation, titleVisibility: .visible) {
            Button("모두 비우기", role: .destructive) { store.clearEntries() }
            Button("취소", role: .cancel) {}
        } message: { Text("직접 입력한 일정은 삭제합니다. 캘린더 일정은 이후 반복 일정까지 배경화면에서 숨기며, 원본 캘린더는 유지합니다.") }
        .overlay(alignment: .bottom) {
            if let message = store.message {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(hex: 0xA0BC83))
                    Text(message).font(.system(size: 12))
                    Button { store.message = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }
                .foregroundStyle(.white).padding(.horizontal, 18).padding(.vertical, 13)
                .background(StudioStyle.ink, in: Capsule()).shadow(color: .black.opacity(0.12), radius: 14, y: 5)
                .padding(.bottom, 22)
                .task(id: message) {
                    try? await Task.sleep(for: .seconds(5))
                    if !Task.isCancelled && store.message == message { store.message = nil }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(StudioStyle.accent).frame(width: 36, height: 36)
                Image(systemName: "sun.max").font(.system(size: 23, weight: .ultraLight)).foregroundStyle(StudioStyle.sidebar)
            }
            Text("serein").font(.custom("Georgia", size: 31)).tracking(-1.8)
            Rectangle().fill(StudioStyle.line).frame(width: 1, height: 20).padding(.horizontal, 9)
            Text("A LITTLE SPACE FOR YOUR TIME").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.8).foregroundStyle(StudioStyle.muted)
            Spacer()
            Button { store.showAutomation = true } label: {
                Label("자동화", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .medium)).padding(.horizontal, 13).padding(.vertical, 9)
                    .background(StudioStyle.paper, in: Capsule())
            }.buttonStyle(.plain).foregroundStyle(StudioStyle.accent).accessibilityIdentifier("open-automation")
            Rectangle().fill(StudioStyle.line).frame(width: 1, height: 20).padding(.horizontal, 6)
            Image(systemName: "lock.shield").font(.system(size: 11))
            Text("온전히, 내 Mac 안에서").font(.system(size: 11))
        }
        .foregroundStyle(StudioStyle.muted)
        .padding(.horizontal, 30).padding(.top, 18).padding(.bottom, 18)
        .background(StudioStyle.sidebar)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                tabButton("01", "시간표", index: 0)
                tabButton("02", "디자인", index: 1)
            }.padding(5).background(StudioStyle.paper, in: RoundedRectangle(cornerRadius: 9)).padding(22)
            if tab == 0 { schedulePanel } else { designPanel }
            Spacer(minLength: 0)
            HStack(spacing: 7) {
                Circle().fill(Color(hex: 0x78916D)).frame(width: 5, height: 5)
                Text(store.isDemo ? "예시 모드 · 저장되지 않습니다" : "기기에 자동 저장됩니다").font(.system(size: 10))
                Spacer()
                Text("V.03").font(.system(size: 9, design: .monospaced))
            }.foregroundStyle(StudioStyle.muted).padding(22)
        }.background(StudioStyle.sidebar)
    }

    private func tabButton(_ number: String, _ title: String, index: Int) -> some View {
        Button { tab = index } label: {
            HStack(spacing: 7) {
                Text(number).font(.system(size: 9, design: .monospaced)).opacity(0.65)
                Text(title).font(.system(size: 12, weight: .medium))
            }.frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(tab == index ? StudioStyle.sidebar : .clear, in: RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(tab == index ? 0.04 : 0), radius: 3, y: 1)
        }.buttonStyle(.plain).foregroundStyle(tab == index ? StudioStyle.ink : StudioStyle.muted)
    }

    private var schedulePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: store.chooseImage) {
                VStack(spacing: 9) {
                    Image(systemName: store.isRecognizing ? "viewfinder" : "photo.badge.plus")
                        .font(.system(size: 23, weight: .ultraLight)).foregroundStyle(StudioStyle.accent)
                    Text(store.isRecognizing ? "시간표를 읽고 있어요…" : "시간표 이미지 가져오기")
                        .font(.system(size: 12, weight: .medium))
                    Text("클릭하거나 이미지를 끌어다 놓으세요")
                        .font(.system(size: 10)).foregroundStyle(StudioStyle.muted)
                    if store.isRecognizing { ProgressView().controlSize(.small) }
                    else { Text("PNG · JPG · HEIC").font(.system(size: 8, design: .monospaced)).tracking(1).foregroundStyle(StudioStyle.muted) }
                }.frame(maxWidth: .infinity).padding(.vertical, 22)
                    .background(isDropTarget ? StudioStyle.accent.opacity(0.07) : StudioStyle.paper.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isDropTarget ? StudioStyle.accent : StudioStyle.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            }.buttonStyle(.plain).disabled(store.isRecognizing).padding(.horizontal, 22)
            .onDrop(of: [UTType.fileURL], isTargeted: $isDropTarget) { providers in
                guard let first = providers.first, !store.isRecognizing else { return false }
                _ = first.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in store.recognize(url: url) }
                }
                return true
            }
            Button { store.showCalendarImport = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.clock").font(.system(size: 19, weight: .light))
                        .foregroundStyle(StudioStyle.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("캘린더에서 가져오기").font(.system(size: 11, weight: .medium))
                        Text("Apple Calendar · Google Calendar").font(.system(size: 9)).foregroundStyle(StudioStyle.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(StudioStyle.muted)
                }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
                    .background(StudioStyle.paper, in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).disabled(store.isRecognizing)
                .padding(.horizontal, 22).padding(.top, 12).accessibilityIdentifier("import-calendar")
            HStack {
                Text("주간 일정").font(.system(size: 12, weight: .semibold))
                Text(String(store.entries.count)).font(.system(size: 10, design: .monospaced)).foregroundStyle(StudioStyle.muted)
                Spacer()
                Button { editingEntry = .init(name: "", day: 0, startMinutes: 540, endMinutes: 600) } label: {
                    Label("추가", systemImage: "plus").font(.system(size: 11, weight: .medium))
                }.buttonStyle(.plain).foregroundStyle(StudioStyle.accent).accessibilityIdentifier("add-entry")
            }.padding(.horizontal, 22).padding(.top, 26).padding(.bottom, 12)
            ScrollView {
                LazyVStack(spacing: 0) {
                    if store.entries.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "calendar").font(.system(size: 26, weight: .ultraLight))
                            Text("비어 있는 시간도 좋아요.").font(.system(size: 12))
                            Text("이미지를 가져오거나 일정을 추가해보세요.").font(.system(size: 10))
                            Button("예시 시간표 불러오기") { store.entries = ScheduleEntry.sample }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(StudioStyle.accent)
                        }.foregroundStyle(StudioStyle.muted).frame(maxWidth: .infinity).padding(.vertical, 34)
                    } else {
                        ForEach(store.sortedEntries) { entry in
                            Button { editingEntry = entry } label: { courseRow(entry) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("수정") { editingEntry = entry }
                                    if entry.calendarSourceKey != nil {
                                        Button("배경화면에서 숨기기 · 반복 포함") { store.remove(entry.id) }
                                        Button("이번 회차만 숨기기") { store.remove(entry.id, scope: .occurrence) }
                                    } else {
                                        Button("삭제", role: .destructive) { store.remove(entry.id) }
                                    }
                                }
                        }
                    }
                }.padding(.horizontal, 22)
            }
            if !store.calendarVisibility.exclusions.isEmpty {
                Button { store.showHiddenCalendarEntries = true } label: {
                    Label("숨긴 일정 \(store.calendarVisibility.exclusions.count)", systemImage: "eye.slash")
                        .font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).foregroundStyle(StudioStyle.accent)
                    .padding(.horizontal, 22).padding(.top, 10)
                    .accessibilityIdentifier("open-hidden-calendar-entries")
            }
            HStack {
                Text("주 \(store.weeklyHours)시간").font(.system(size: 10))
                Spacer()
                Button("모두 비우기") { showClearConfirmation = true }.buttonStyle(.plain).font(.system(size: 10)).disabled(store.entries.isEmpty)
            }.foregroundStyle(StudioStyle.muted).padding(.horizontal, 22).padding(.top, 12)
        }
    }

    private func courseRow(_ entry: ScheduleEntry) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Text(ScheduleEntry.dayNames[entry.day])
                .font(.system(size: 10, weight: .medium)).foregroundStyle(StudioStyle.accent)
                .frame(width: 29, height: 30).background(StudioStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(entry.timeLabel).font(.system(size: 9, design: .monospaced)).foregroundStyle(StudioStyle.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "pencil").font(.system(size: 9)).foregroundStyle(StudioStyle.muted.opacity(0.7)).padding(.top, 3)
        }.padding(.vertical, 13).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(StudioStyle.line.opacity(0.7)).frame(height: 1) }
            .contentShape(Rectangle())
    }

    private var designPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("COLOR STORY", "컬러 테마")
                    ForEach(WallpaperTheme.allCases) { theme in
                        Button { store.configuration.theme = theme } label: {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 5).fill(themeGradient(theme)).frame(width: 43, height: 35)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(theme.label).font(.custom("Georgia", size: 14))
                                    Text(theme.subtitle).font(.system(size: 9)).foregroundStyle(StudioStyle.muted)
                                }
                                Spacer()
                                Image(systemName: store.configuration.theme == theme ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(store.configuration.theme == theme ? StudioStyle.accent : StudioStyle.line).font(.system(size: 16))
                            }.padding(10).background(store.configuration.theme == theme ? StudioStyle.paper : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }
                VStack(alignment: .leading, spacing: 9) {
                    fieldLabel("WORDS TO LIVE BY", "나만의 문구")
                    TextEditor(text: $store.configuration.title)
                        .font(.custom("Georgia", size: 16)).scrollContentBackground(.hidden)
                        .padding(8).frame(height: 79).background(StudioStyle.paper, in: RoundedRectangle(cornerRadius: 7))
                        .onChange(of: store.configuration.title) { _, value in if value.count > 100 { store.configuration.title = String(value.prefix(100)) } }
                    Text("최대 100자 · 줄바꿈 가능").font(.system(size: 9)).foregroundStyle(StudioStyle.muted)
                }
                VStack(alignment: .leading, spacing: 9) {
                    fieldLabel("EDITION", "시간표 제목")
                    TextField("2026 — FALL SEMESTER", text: $store.configuration.subtitle)
                        .textFieldStyle(.plain).font(.system(size: 11)).padding(11)
                        .background(StudioStyle.paper, in: RoundedRectangle(cornerRadius: 6))
                        .onChange(of: store.configuration.subtitle) { _, value in if value.count > 60 { store.configuration.subtitle = String(value.prefix(60)) } }
                }
                VStack(spacing: 15) {
                    Toggle("장소 표시", isOn: $store.configuration.showLocations)
                    Toggle("주말 포함", isOn: $store.configuration.showWeekends)
                    Toggle("페이퍼 텍스처", isOn: $store.configuration.showTexture)
                }.toggleStyle(.switch).controlSize(.mini).font(.system(size: 11))
                Text("주말 일정이 있으면 해당 요일은 자동으로 표시됩니다.").font(.system(size: 10)).foregroundStyle(StudioStyle.muted).lineSpacing(3)
            }.padding(.horizontal, 22).padding(.bottom, 16)
        }
    }

    private var workspace: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("THE WALLPAPER STUDIO").font(.system(size: 9, design: .monospaced)).tracking(2.2).foregroundStyle(StudioStyle.accent)
                Spacer()
                Text("DESIGNED BY RULES. MADE FOR YOU.").font(.system(size: 8, design: .monospaced)).tracking(1).foregroundStyle(StudioStyle.muted)
            }.padding(.bottom, 12)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Your week, in a new light.").font(.custom("Georgia", size: 32)).tracking(-1.25)
                    Text("매일 보는 화면에, 나만의 리듬을 담아보세요.").font(.system(size: 12)).foregroundStyle(StudioStyle.muted)
                }
                Spacer()
            }.padding(.bottom, 27)
            GeometryReader { geometry in
                let ratio = store.configuration.resolution.size.width / store.configuration.resolution.size.height
                let width = min(geometry.size.width, geometry.size.height * ratio)
                ZStack(alignment: .top) {
                    if let preview = store.preview {
                        Image(nsImage: preview).resizable().aspectRatio(contentMode: .fit)
                    } else { Rectangle().fill(StudioStyle.accent).overlay(ProgressView()) }
                    if showDesktop { desktopOverlay }
                }
                .frame(width: width, height: width / ratio)
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.black.opacity(0.09), lineWidth: 1))
                .shadow(color: Color(hex: 0x57321E).opacity(0.14), radius: 22, y: 13)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minHeight: 300)
            HStack(spacing: 6) {
                Circle().fill(Color(hex: 0x849573)).frame(width: 5, height: 5)
                Text("LIVE PREVIEW").font(.system(size: 8, design: .monospaced)).tracking(1.3)
                Text("/ \(store.configuration.theme.label)").font(.system(size: 10)).padding(.leading, 5)
                Spacer()
                Button { showDesktop.toggle() } label: {
                    Label(showDesktop ? "배경화면만 보기" : "데스크탑 미리보기", systemImage: "menubar.dock.rectangle")
                        .font(.system(size: 10))
                }.buttonStyle(.plain)
            }.foregroundStyle(StudioStyle.muted).padding(.top, 19).padding(.bottom, 25)
            Rectangle().fill(StudioStyle.line).frame(height: 1)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("MADE TO FIT").font(.system(size: 8, design: .monospaced)).tracking(1.3).foregroundStyle(StudioStyle.muted)
                    Menu {
                        ForEach(WallpaperResolution.allCases) { resolution in
                            Button("\(resolution.label) · \(resolution.dimensions)") { store.configuration.resolution = resolution }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "laptopcomputer")
                            Text(store.configuration.resolution.label).fontWeight(.medium)
                            Image(systemName: "chevron.down").font(.system(size: 8))
                        }.font(.system(size: 12))
                    }.menuStyle(.borderlessButton).fixedSize()
                    Text("\(store.configuration.resolution.dimensions) px · PNG").font(.system(size: 9, design: .monospaced)).foregroundStyle(StudioStyle.muted)
                }
                Spacer(minLength: 8)
                Button(action: store.exportPNG) { Label("PNG 저장", systemImage: "arrow.down.to.line").frame(height: 19) }
                    .buttonStyle(StudioButtonStyle(primary: false))
                Button(action: store.applyWallpaper) { Label("배경화면으로 설정", systemImage: "arrow.up.right").frame(height: 19) }
                    .buttonStyle(StudioButtonStyle(primary: true))
            }.disabled(store.isExporting).padding(.top, 24)
            HStack(spacing: 4) {
                Image(systemName: "sparkle").font(.system(size: 9))
                Text("생성형 AI 없이, 정교하게 그려낸 나만의 배경화면.").font(.system(size: 10))
                Spacer()
                Text("SEREIN © 2026").font(.system(size: 8, design: .monospaced)).tracking(1)
            }.foregroundStyle(StudioStyle.muted).padding(.top, 30)
        }.padding(.horizontal, 35).padding(.top, 31).padding(.bottom, 26)
    }

    private var desktopOverlay: some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: "apple.logo")
                Text("Finder").bold()
                Text("파일   편집   보기   이동   윈도우   도움말")
                Spacer()
                Image(systemName: "wifi")
                Image(systemName: "battery.100percent")
                Text("월요일 9:41")
            }.font(.system(size: 8)).foregroundStyle(.white.opacity(0.9)).padding(.horizontal, 13).padding(.vertical, 6).background(.black.opacity(0.12))
            Spacer()
            HStack(spacing: 6) {
                ForEach(["face.smiling", "safari", "message", "envelope", "calendar", "photo", "music.note", "gearshape"], id: \.self) { icon in
                    Image(systemName: icon).font(.system(size: 15)).foregroundStyle(.white.opacity(0.9))
                        .frame(width: 27, height: 27).background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 7))
                }
            }.padding(7).background(.ultraThinMaterial.opacity(0.7), in: RoundedRectangle(cornerRadius: 13)).padding(.bottom, 6)
        }.allowsHitTesting(false)
    }

    private func fieldLabel(_ eyebrow: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow).font(.system(size: 8, design: .monospaced)).tracking(1.2).foregroundStyle(StudioStyle.muted)
            Text(title).font(.system(size: 12, weight: .medium))
        }
    }
    private func themeGradient(_ theme: WallpaperTheme) -> LinearGradient {
        let colors: [Color] = switch theme {
        case .ember: [Color(hex: 0xF39244), Color(hex: 0xAE270F), Color(hex: 0xDD6A20)]
        case .moss: [Color(hex: 0xB0AD77), Color(hex: 0x414F32), Color(hex: 0x7A8252)]
        case .midnight: [Color(hex: 0x637CAB), Color(hex: 0x152958), Color(hex: 0x3E5091)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct StudioButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var primary: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 17).padding(.vertical, 12)
            .foregroundStyle(primary ? StudioStyle.sidebar : StudioStyle.ink)
            .background(primary ? StudioStyle.ink.opacity(configuration.isPressed ? 0.8 : 1) : StudioStyle.sidebar, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(primary ? .clear : StudioStyle.line, lineWidth: 1))
            .opacity(!isEnabled ? 0.38 : (configuration.isPressed ? 0.85 : 1))
    }
}

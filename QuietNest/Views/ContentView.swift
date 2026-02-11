import SwiftUI

private enum SoundCategory: String, CaseIterable, Identifiable {
    case nature = "🌿 自然"
    case city = "🏙️ 城市"
    case noise = "🎵 噪音"
    case brain = "🧠 频率"

    var id: String { rawValue }
}

private struct SoundItem: Identifiable, Hashable {
    let id = UUID()
    let emoji: String
    let name: String
}

private struct Track: Identifiable, Codable, Hashable {
    var id = UUID()
    let emoji: String
    let name: String
    var volume: Double
}

private struct Preset: Identifiable, Codable, Hashable {
    var id = UUID()
    let name: String
    let scene: String
    let group: PresetGroup
    let icon: String
    let desc: String
    let tracks: [Track]
    var isFavorite: Bool = false
}

private enum PresetGroup: String, CaseIterable, Codable {
    case officialSleep
    case officialFocus
    case officialRelax
    case mine

    var title: String {
        switch self {
        case .officialSleep: return "官方预设 · 助眠"
        case .officialFocus: return "官方预设 · 专注"
        case .officialRelax: return "官方预设 · 放松"
        case .mine: return "我的预设"
        }
    }
}

private enum BottomPanel {
    case preset
    case timer
}

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("favoritePresetNamesData") private var favoritePresetNamesData = "[]"
    @AppStorage("customPresetsData") private var customPresetsData = "[]"
    @State private var selectedCategory: SoundCategory = .nature
    @State private var isPlaying = true
    @State private var showSettings = false
    @State private var activePanel: BottomPanel?
    @State private var selectedPreset = "雨夜书房"
    @State private var selectedTimer = 45
    @State private var timerActive = false
    @State private var remainingSeconds = 0
    @State private var showOnboarding = false
    @State private var onboardingStep = 1
    @State private var selectedScene = "😴 助眠 · 安心入睡"
    @State private var toastMessage: String?
    @State private var favoritePresetNames: Set<String> = []
    @State private var customPresets: [Preset] = []
    @State private var presetSearchText = ""
    @State private var showSavePresetAlert = false
    @State private var newPresetName = ""
    @State private var showAddTrackPage = false
    @State private var addTrackSearchText = ""
    @State private var tracks: [Track] = [
        Track(emoji: "🌧️", name: "雨声", volume: 0.72),
        Track(emoji: "⛈️", name: "远处雷声", volume: 0.30),
        Track(emoji: "🔥", name: "篝火", volume: 0.50)
    ]

    private let soundsData: [SoundCategory: [SoundItem]] = [
        .nature: [
            SoundItem(emoji: "🌧️", name: "雨声"), SoundItem(emoji: "🌊", name: "海浪"),
            SoundItem(emoji: "💧", name: "溪流"), SoundItem(emoji: "🌬️", name: "微风"),
            SoundItem(emoji: "⛈️", name: "雷声"), SoundItem(emoji: "🐦", name: "鸟鸣"),
            SoundItem(emoji: "🐸", name: "蛙鸣"), SoundItem(emoji: "🦗", name: "蟋蟀"),
            SoundItem(emoji: "🔥", name: "篝火"), SoundItem(emoji: "🍃", name: "落叶"),
            SoundItem(emoji: "🌲", name: "松林风"), SoundItem(emoji: "💦", name: "瀑布")
        ],
        .city: [
            SoundItem(emoji: "☕", name: "咖啡馆"), SoundItem(emoji: "📚", name: "图书馆"),
            SoundItem(emoji: "🕰️", name: "钟摆"), SoundItem(emoji: "❄️", name: "空调"),
            SoundItem(emoji: "🌀", name: "风扇"), SoundItem(emoji: "🚂", name: "火车"),
            SoundItem(emoji: "✈️", name: "机舱"), SoundItem(emoji: "🚗", name: "行驶"),
            SoundItem(emoji: "🌃", name: "夜街"), SoundItem(emoji: "🪟", name: "雨窗")
        ],
        .noise: [
            SoundItem(emoji: "⬜", name: "白噪音"), SoundItem(emoji: "🩷", name: "粉噪音"),
            SoundItem(emoji: "🟤", name: "棕噪音"), SoundItem(emoji: "⬛", name: "灰噪音"),
            SoundItem(emoji: "🔵", name: "蓝噪音")
        ],
        .brain: [
            SoundItem(emoji: "🌑", name: "Delta波"), SoundItem(emoji: "🌘", name: "Theta波"),
            SoundItem(emoji: "🌗", name: "Alpha波"), SoundItem(emoji: "🌕", name: "Beta波")
        ]
    ]

    private let defaultPresets: [Preset] = [
        Preset(name: "雨夜书房", scene: "助眠", group: .officialSleep, icon: "🌧️", desc: "雨声 + 篝火 + 钟摆", tracks: [
            Track(emoji: "🌧️", name: "雨声", volume: 0.70),
            Track(emoji: "🔥", name: "篝火", volume: 0.40),
            Track(emoji: "🕰️", name: "钟摆", volume: 0.26)
        ]),
        Preset(name: "海边小屋", scene: "助眠", group: .officialSleep, icon: "🌊", desc: "海浪 + 海鸥 + 微风", tracks: [
            Track(emoji: "🌊", name: "海浪", volume: 0.72),
            Track(emoji: "🐦", name: "海鸥", volume: 0.20),
            Track(emoji: "🌬️", name: "微风", volume: 0.33)
        ]),
        Preset(name: "深夜咖啡馆", scene: "专注", group: .officialFocus, icon: "☕", desc: "咖啡馆 + 雨声 + 爵士", tracks: [
            Track(emoji: "☕", name: "咖啡馆", volume: 0.65),
            Track(emoji: "🌧️", name: "雨声", volume: 0.36),
            Track(emoji: "🎷", name: "爵士", volume: 0.22)
        ]),
        Preset(name: "森林书桌", scene: "专注", group: .officialFocus, icon: "🌲", desc: "鸟鸣 + 溪流 + 微风", tracks: [
            Track(emoji: "🐦", name: "鸟鸣", volume: 0.64),
            Track(emoji: "💧", name: "溪流", volume: 0.38),
            Track(emoji: "🌬️", name: "微风", volume: 0.26)
        ]),
        Preset(name: "夏夜虫鸣", scene: "放松", group: .officialRelax, icon: "🦗", desc: "蟋蟀 + 蛙鸣 + 微风", tracks: [
            Track(emoji: "🦗", name: "蟋蟀", volume: 0.66),
            Track(emoji: "🐸", name: "蛙鸣", volume: 0.34),
            Track(emoji: "🌬️", name: "微风", volume: 0.24)
        ]),
        Preset(name: "冬日壁炉", scene: "放松", group: .officialRelax, icon: "🔥", desc: "篝火 + 风雪 + 猫咪", tracks: [
            Track(emoji: "🔥", name: "篝火", volume: 0.68),
            Track(emoji: "🌬️", name: "风雪", volume: 0.30),
            Track(emoji: "🐱", name: "猫咪", volume: 0.20)
        ]),
        Preset(name: "我的最爱", scene: "我的预设", group: .mine, icon: "💜", desc: "粉噪音 + 小溪 + 鸟鸣", tracks: [
            Track(emoji: "🩷", name: "粉噪音", volume: 0.55),
            Track(emoji: "💧", name: "溪流", volume: 0.44),
            Track(emoji: "🐦", name: "鸟鸣", volume: 0.22)
        ])
    ]

    private var displayedSounds: [SoundItem] {
        soundsData[selectedCategory] ?? []
    }

    private var mergedPresets: [Preset] {
        (defaultPresets + customPresets).map { preset in
            var p = preset
            p.isFavorite = favoritePresetNames.contains(p.name)
            return p
        }
    }

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.04, green: 0.07, blue: 0.12), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                header
                visualCard
                categoryTabs
                soundsGrid
                trackArea
                bottomBar
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)

            if let toastMessage {
                VStack {
                    Spacer()
                    Text(toastMessage)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(red: 0.10, green: 0.13, blue: 0.20))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
                        .padding(.bottom, 120)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if let panel = activePanel {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { activePanel = nil } }

                VStack {
                    Spacer()
                    if panel == .preset {
                        PresetPanelView(
                            presets: mergedPresets,
                            selectedPresetName: selectedPreset,
                            searchText: $presetSearchText,
                            onSaveCurrent: {
                                newPresetName = "我的预设 \(customPresets.count + 1)"
                                showSavePresetAlert = true
                            },
                            onToggleFavorite: { preset in
                                toggleFavorite(preset)
                            },
                            onSelect: { preset in
                                selectedPreset = preset.name
                                tracks = preset.tracks
                                withAnimation(.easeOut(duration: 0.2)) { activePanel = nil }
                            }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        TimerPanelView(
                            selectedTimer: $selectedTimer,
                            onStart: {
                                startTimer()
                                withAnimation(.easeOut(duration: 0.2)) { activePanel = nil }
                            },
                            onClear: {
                                clearTimer()
                                withAnimation(.easeOut(duration: 0.2)) { activePanel = nil }
                            }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .ignoresSafeArea(edges: .bottom)
                .animation(.easeOut(duration: 0.2), value: activePanel)
            }

            if showOnboarding {
                onboardingOverlay
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showAddTrackPage) {
            AddTrackPageView(
                selectedCategory: $selectedCategory,
                searchText: $addTrackSearchText,
                soundsData: soundsData,
                existingTrackNames: Set(tracks.map(\.name)),
                trackCount: tracks.count,
                onPreview: { sound in
                    showToast("预览：\(sound.name)")
                },
                onAdd: { sound in
                    _ = addTrackFromLibrary(sound)
                }
            )
        }
        .alert("保存当前预设", isPresented: $showSavePresetAlert) {
            TextField("预设名称", text: $newPresetName)
            Button("取消", role: .cancel) {}
            Button("保存") {
                saveCurrentPreset()
            }
        } message: {
            Text("将当前轨道保存到“我的预设”")
        }
        .animation(.easeInOut(duration: 0.2), value: toastMessage)
        .onAppear {
            loadPersistedData()
            if !hasCompletedOnboarding {
                showOnboarding = true
            }
        }
        .onReceive(ticker) { _ in
            guard timerActive else { return }
            guard remainingSeconds > 0 else {
                timerActive = false
                return
            }
            remainingSeconds -= 1
            if remainingSeconds <= 0 {
                timerActive = false
                isPlaying = false
                showToast("定时结束")
            }
        }
    }

    private var onboardingOverlay: some View {
        ZStack {
            Color.black.opacity(0.86).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach(1...3, id: \.self) { idx in
                        RoundedRectangle(cornerRadius: 10)
                            .fill(idx <= onboardingStep ? Color(red: 0.91, green: 0.66, blue: 0.22) : Color.white.opacity(0.22))
                            .frame(width: idx <= onboardingStep ? 18 : 9, height: 9)
                    }
                }
                .padding(.top, 20)

                Group {
                    if onboardingStep == 1 {
                        onboardingStepOne
                    } else if onboardingStep == 2 {
                        onboardingStepTwo
                    } else {
                        onboardingStepThree
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack {
                    Button("跳过") {
                        hasCompletedOnboarding = true
                        showOnboarding = false
                    }
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(onboardingStep == 3 ? "开始使用" : "继续") {
                        if onboardingStep < 3 {
                            onboardingStep += 1
                        } else {
                            hasCompletedOnboarding = true
                            showOnboarding = false
                            showToast("欢迎使用 SoundScape")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.91, green: 0.66, blue: 0.22))
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color.white.opacity(0.03))
                .overlay(Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1), alignment: .top)
            }
            .frame(width: 350, height: 620)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.08, green: 0.11, blue: 0.17), Color(red: 0.05, green: 0.06, blue: 0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.10), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 30, x: 0, y: 12)
        }
        .transition(.opacity)
    }

    private var onboardingStepOne: some View {
        VStack(spacing: 14) {
            Text("🌙").font(.system(size: 52))
            Text("选择你的\n主要场景")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            Text("我们会根据你的选择推荐最合适的声音预设")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                sceneButton("😴 助眠 · 安心入睡")
                sceneButton("🎯 专注 · 深度工作")
                sceneButton("🧘 放松 · 舒缓解压")
            }
        }
    }

    private var onboardingStepTwo: some View {
        VStack(spacing: 14) {
            Text("🎧").font(.system(size: 52))
            Text("试试调节\n你的音景")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            Text("拖动滑块调节音量，感受属于你的声音组合")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                onboardingTrack("🌧️ 雨声", value: 0.70)
                onboardingTrack("🔥 篝火", value: 0.40)
                onboardingTrack("🦗 蟋蟀", value: 0.25)
            }
        }
    }

    private var onboardingStepThree: some View {
        VStack(spacing: 14) {
            Text("✨").font(.system(size: 52))
            Text("一切就绪\n好梦开始")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            Text("超过 50 种声音等你探索。核心功能离线可用。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            featureChip("📡 完全离线")
            featureChip("🔇 零打扰")
            featureChip("💰 一次买断")
        }
    }

    private var header: some View {
        HStack {
            Text("SoundScape")
                .font(.title2.weight(.bold))
                .foregroundStyle(
                    LinearGradient(colors: [.white, Color(red: 0.91, green: 0.66, blue: 0.22)], startPoint: .leading, endPoint: .trailing)
                )

            Spacer()

            HStack(spacing: 12) {
                iconButton(system: "shuffle") { randomizeTracks() }
                iconButton(system: "gearshape") { showSettings = true }
            }
        }
    }

    private var visualCard: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.05, green: 0.10, blue: 0.17), Color(red: 0.03, green: 0.04, blue: 0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.05), lineWidth: 1))

            WaveVisualView(isPlaying: isPlaying)
                .clipShape(RoundedRectangle(cornerRadius: 18))

            if timerActive {
                Text(formatSeconds(remainingSeconds))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.91, green: 0.66, blue: 0.22))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.45))
                    .clipShape(Capsule())
                    .padding(12)
            }

            VStack(alignment: .leading) {
                Spacer()
                Text("当前预设：")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text(selectedPreset)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .frame(height: 180)
    }

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SoundCategory.allCases) { category in
                    let active = selectedCategory == category
                    Text(category.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(active ? Color(red: 0.91, green: 0.66, blue: 0.22).opacity(0.18) : .clear)
                        .foregroundStyle(active ? Color(red: 0.91, green: 0.66, blue: 0.22) : Color.secondary)
                        .clipShape(Capsule())
                        .onTapGesture { selectedCategory = category }
                }
            }
        }
    }

    private var soundsGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(displayedSounds) { sound in
                    let active = tracks.contains { $0.name == sound.name }
                    VStack(spacing: 8) {
                        Text(sound.emoji)
                            .font(.title2)
                            .frame(width: 56, height: 56)
                            .background(active ? Color(red: 0.91, green: 0.66, blue: 0.22).opacity(0.18) : Color.white.opacity(0.05))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(active ? Color(red: 0.91, green: 0.66, blue: 0.22) : Color.white.opacity(0.08), lineWidth: 1))
                        Text(sound.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(width: 64)
                    .contentShape(Rectangle())
                    .gesture(
                        TapGesture(count: 2)
                            .onEnded { toggleSound(sound) }
                            .exclusively(
                                before: TapGesture(count: 1)
                                    .onEnded { showToast("预览：\(sound.name)") }
                            )
                    )
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
        .frame(height: 92)
    }

    private var trackArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("混音轨道")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach($tracks) { $track in
                        TrackRowView(track: $track) {
                            removeTrack(track)
                        }
                    }
                }
            }
            .frame(height: 165)

            Button {
                addTrackSearchText = ""
                showAddTrackPage = true
            } label: {
                Text("+ 添加轨道")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.91, green: 0.66, blue: 0.22))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            smallControlButton(title: "预设", system: "line.3.horizontal.decrease") {
                withAnimation(.easeOut(duration: 0.2)) { activePanel = .preset }
            }

            Button {
                isPlaying.toggle()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(width: 62, height: 62)
                    .background(Color(red: 0.91, green: 0.66, blue: 0.22))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            smallControlButton(title: timerActive ? formatSeconds(remainingSeconds) : "定时", system: "timer") {
                withAnimation(.easeOut(duration: 0.2)) { activePanel = .timer }
            }
        }
    }

    private func iconButton(system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.subheadline.weight(.semibold))
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func smallControlButton(title: String, system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: system)
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func sceneButton(_ title: String) -> some View {
        let active = selectedScene == title
        return Button {
            selectedScene = title
        } label: {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                Spacer()
                if active {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(red: 0.91, green: 0.66, blue: 0.22))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color.white.opacity(active ? 0.14 : 0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(active ? Color(red: 0.91, green: 0.66, blue: 0.22) : Color.white.opacity(0.07), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func onboardingTrack(_ title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(value * 100))%").font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: value)
                .tint(Color(red: 0.91, green: 0.66, blue: 0.22))
        }
        .padding(10)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func featureChip(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.medium))
            Spacer()
        }
        .padding(12)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func toggleSound(_ sound: SoundItem) {
        if let existing = tracks.firstIndex(where: { $0.name == sound.name }) {
            tracks.remove(at: existing)
            return
        }
        guard tracks.count < 8 else {
            showToast("最多 8 个轨道")
            return
        }
        tracks.append(Track(emoji: sound.emoji, name: sound.name, volume: 0.5))
    }

    private func removeTrack(_ track: Track) {
        tracks.removeAll { $0.id == track.id }
    }

    @discardableResult
    private func addTrackFromLibrary(_ sound: SoundItem) -> Bool {
        if tracks.count >= 8 {
            showToast("最多 8 个轨道")
            return false
        }
        if tracks.contains(where: { $0.name == sound.name }) {
            showToast("已添加：\(sound.name)")
            return false
        }
        tracks.append(Track(emoji: sound.emoji, name: sound.name, volume: 0.5))
        return true
    }

    private func randomizeTracks() {
        let allSounds = soundsData.values.flatMap { $0 }.shuffled()
        let pickCount = Int.random(in: 2...4)
        tracks = Array(allSounds.prefix(pickCount)).map {
            Track(emoji: $0.emoji, name: $0.name, volume: Double.random(in: 0.2...0.8))
        }
        selectedPreset = "随机音景"
    }

    private func loadPersistedData() {
        if let data = favoritePresetNamesData.data(using: .utf8),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            favoritePresetNames = Set(arr)
        }
        if let data = customPresetsData.data(using: .utf8),
           let list = try? JSONDecoder().decode([Preset].self, from: data) {
            customPresets = list
        }
    }

    private func persistFavoriteNames() {
        let arr = Array(favoritePresetNames).sorted()
        if let data = try? JSONEncoder().encode(arr),
           let str = String(data: data, encoding: .utf8) {
            favoritePresetNamesData = str
        }
    }

    private func persistCustomPresets() {
        if let data = try? JSONEncoder().encode(customPresets),
           let str = String(data: data, encoding: .utf8) {
            customPresetsData = str
        }
    }

    private func toggleFavorite(_ preset: Preset) {
        if favoritePresetNames.contains(preset.name) {
            favoritePresetNames.remove(preset.name)
        } else {
            favoritePresetNames.insert(preset.name)
        }
        persistFavoriteNames()
    }

    private func saveCurrentPreset() {
        let trimmed = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tracks.isEmpty else {
            showToast("当前没有可保存的轨道")
            return
        }
        let baseName = trimmed.isEmpty ? "我的预设" : trimmed
        let finalName = uniquePresetName(baseName)
        let desc = tracks.prefix(3).map(\.name).joined(separator: " + ")
        let icon = tracks.first?.emoji ?? "💜"
        let preset = Preset(
            name: finalName,
            scene: "我的预设",
            group: .mine,
            icon: icon,
            desc: desc.isEmpty ? "自定义音景" : desc,
            tracks: tracks
        )
        customPresets.insert(preset, at: 0)
        persistCustomPresets()
        selectedPreset = finalName
        showToast("已保存：\(finalName)")
    }

    private func uniquePresetName(_ name: String) -> String {
        let existing = Set((defaultPresets + customPresets).map(\.name))
        if !existing.contains(name) { return name }
        var idx = 2
        while existing.contains("\(name) \(idx)") {
            idx += 1
        }
        return "\(name) \(idx)"
    }

    private func startTimer() {
        timerActive = true
        remainingSeconds = selectedTimer * 60
    }

    private func clearTimer() {
        timerActive = false
        remainingSeconds = 0
    }

    private func formatSeconds(_ total: Int) -> String {
        let safe = max(0, total)
        let m = safe / 60
        let s = safe % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }
}

private struct AddTrackPageView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedCategory: SoundCategory
    @Binding var searchText: String
    let soundsData: [SoundCategory: [SoundItem]]
    let existingTrackNames: Set<String>
    let trackCount: Int
    let onPreview: (SoundItem) -> Void
    let onAdd: (SoundItem) -> Void

    private var displayedSounds: [SoundItem] {
        let base = soundsData[selectedCategory] ?? []
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return base }
        return base.filter { sound in
            sound.name.lowercased().contains(query)
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.04, green: 0.07, blue: 0.12), Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("搜索声音", text: $searchText)
                            .textInputAutocapitalization(.never)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(SoundCategory.allCases) { category in
                                let active = selectedCategory == category
                                Text(category.rawValue)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(active ? Color(red: 0.91, green: 0.66, blue: 0.22).opacity(0.18) : .clear)
                                    .foregroundStyle(active ? Color(red: 0.91, green: 0.66, blue: 0.22) : Color.secondary)
                                    .clipShape(Capsule())
                                    .onTapGesture { selectedCategory = category }
                            }
                        }
                    }

                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(displayedSounds) { sound in
                                let isAdded = existingTrackNames.contains(sound.name)
                                VStack(spacing: 8) {
                                    Text(sound.emoji)
                                        .font(.title2)
                                        .frame(width: 56, height: 56)
                                        .background(isAdded ? Color(red: 0.91, green: 0.66, blue: 0.22).opacity(0.18) : Color.white.opacity(0.05))
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle().stroke(
                                                isAdded ? Color(red: 0.91, green: 0.66, blue: 0.22) : Color.white.opacity(0.08),
                                                lineWidth: 1
                                            )
                                        )
                                    Text(sound.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Button(isAdded ? "已添加" : "添加") {
                                        onAdd(sound)
                                    }
                                    .buttonStyle(.plain)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(isAdded ? .secondary : Color(red: 0.91, green: 0.66, blue: 0.22))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color.white.opacity(0.05))
                                    .clipShape(Capsule())
                                    .disabled(isAdded)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.02))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                                .onTapGesture {
                                    onPreview(sound)
                                }
                            }
                        }
                        .padding(.bottom, 16)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .navigationTitle("添加轨道")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(trackCount)/8")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(trackCount >= 8 ? Color.red : Color(red: 0.91, green: 0.66, blue: 0.22))
                }
            }
        }
    }
}

private struct WaveVisualView: View {
    let isPlaying: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !isPlaying)) { context in
            Canvas { ctx, size in
                let t = context.date.timeIntervalSinceReferenceDate
                var path = Path()
                path.move(to: .init(x: 0, y: size.height))
                for x in stride(from: 0, through: size.width, by: 2) {
                    let y = size.height * 0.55
                    + sin(x * 0.015 + t * 2.0) * 12
                    + sin(x * 0.009 + t * 1.4) * 8
                    path.addLine(to: .init(x: x, y: y))
                }
                path.addLine(to: .init(x: size.width, y: size.height))
                path.closeSubpath()
                ctx.fill(path, with: .linearGradient(
                    .init(colors: [
                        Color(red: 0.91, green: 0.66, blue: 0.22).opacity(0.25),
                        Color(red: 0.91, green: 0.66, blue: 0.22).opacity(0.02)
                    ]),
                    startPoint: .init(x: 0, y: size.height * 0.35),
                    endPoint: .init(x: 0, y: size.height)
                ))
            }
        }
    }
}

private struct TrackRowView: View {
    @Binding var track: Track
    let onDelete: () -> Void

    var body: some View {
        content
            .frame(height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("删除", systemImage: "trash.fill")
                }
            }
    }

    private var content: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(track.emoji) \(track.name)")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(track.volume * 100))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Slider(value: $track.volume, in: 0...1)
                .tint(Color(red: 0.91, green: 0.66, blue: 0.22))
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
    }
}

private struct PresetPanelView: View {
    let presets: [Preset]
    let selectedPresetName: String
    @Binding var searchText: String
    let onSaveCurrent: () -> Void
    let onToggleFavorite: (Preset) -> Void
    let onSelect: (Preset) -> Void

    private var groupedPresets: [(PresetGroup, [Preset])] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = presets.filter { preset in
            guard !query.isEmpty else { return true }
            return preset.name.lowercased().contains(query) || preset.desc.lowercased().contains(query)
        }
        return PresetGroup.allCases.compactMap { group in
            let items = filtered
                .filter { $0.group == group }
                .sorted { ($0.isFavorite ? 0 : 1, $0.name) < ($1.isFavorite ? 0 : 1, $1.name) }
            return items.isEmpty ? nil : (group, items)
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 38, height: 5)
                .padding(.top, 8)
            HStack {
                Text("音景预设").font(.headline)
                Spacer()
                Button("+ 保存当前") {
                    onSaveCurrent()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(red: 0.91, green: 0.66, blue: 0.22))
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索预设", text: $searchText)
                    .textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(groupedPresets, id: \.0) { entry in
                        let group = entry.0
                        let items = entry.1
                        Text(group.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(items) { preset in
                            let isSelected = selectedPresetName == preset.name
                            HStack(spacing: 10) {
                                Text(preset.icon)
                                    .font(.title3)
                                    .frame(width: 34, height: 34)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(preset.name)
                                        .foregroundStyle(.white)
                                        .font(.subheadline.weight(.semibold))
                                    Text(preset.desc)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()

                                Button {
                                    onToggleFavorite(preset)
                                } label: {
                                    Image(systemName: preset.isFavorite ? "star.fill" : "star")
                                        .foregroundStyle(preset.isFavorite ? Color.yellow : .secondary)
                                }
                                .buttonStyle(.plain)

                                if group != .mine {
                                    Text(preset.scene)
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(tagColor(preset.scene).opacity(0.18))
                                        .foregroundStyle(tagColor(preset.scene))
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(12)
                            .background(isSelected ? Color(red: 0.91, green: 0.66, blue: 0.22).opacity(0.18) : Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isSelected ? Color(red: 0.91, green: 0.66, blue: 0.22) : Color.white.opacity(0.06), lineWidth: 1)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                            .onTapGesture {
                                onSelect(preset)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 420)
        .background(Color(red: 0.05, green: 0.07, blue: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 8)
    }

    private func tagColor(_ scene: String) -> Color {
        switch scene {
        case "助眠": return Color(red: 0.51, green: 0.55, blue: 0.97)
        case "专注": return Color(red: 0.20, green: 0.83, blue: 0.60)
        case "放松": return Color(red: 0.96, green: 0.75, blue: 0.20)
        default: return Color.white
        }
    }
}

private struct TimerPanelView: View {
    @Binding var selectedTimer: Int
    let onStart: () -> Void
    let onClear: () -> Void

    private let options = [15, 30, 45, 60, 90]

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 38, height: 5)
                .padding(.top, 8)

            Text("定时关闭")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(options, id: \.self) { minutes in
                    Button {
                        selectedTimer = minutes
                    } label: {
                        Text("\(minutes)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedTimer == minutes ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(selectedTimer == minutes ? Color(red: 0.91, green: 0.66, blue: 0.22) : Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("最后 5 分钟渐弱淡出")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                onStart()
            } label: {
                Text("开始计时")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.91, green: 0.66, blue: 0.22))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            Button("清除定时") {
                onClear()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.05, green: 0.07, blue: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 8)
    }
}

private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mixWithOthers = true
    @State private var analytics = true

    var body: some View {
        NavigationStack {
            List {
                Section("音频") {
                    settingRow("音频输出", value: "系统默认")
                    Toggle("与其他 App 混音", isOn: $mixWithOthers)
                }
                Section("外观") {
                    settingRow("主题", value: "深色")
                }
                Section("数据") {
                    settingRow("导出数据", value: "JSON")
                    settingRow("导入数据", value: "")
                    Toggle("匿名数据采集", isOn: $analytics)
                }
                Section("关于") {
                    settingRow("升级至完整版", value: "¥38")
                    settingRow("扩展音景包", value: "4 个可用")
                    settingRow("隐私政策", value: "")
                    settingRow("关于 SoundScape", value: "v1.0.0")
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func settingRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            if !value.isEmpty {
                Text(value).foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ContentView()
}

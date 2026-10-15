import SwiftUI
import AppKit
import TranskriptHubCore

public struct FloatingSettingsSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedTab: SettingsTab = .general
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            // Left Navigation Sidebar
            sidebarPane
                .frame(width: 220)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.85))
            
            Divider()
            
            // Right Content Pane
            VStack(spacing: 0) {
                // Modal Top Bar with Close (X) button
                topBar
                
                Divider()
                
                // Tab Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch selectedTab {
                        case .general:
                            generalTab
                        case .models:
                            modelsTab
                        case .storage:
                            storageTab
                        case .automation:
                            automationTab
                        case .updates:
                            updatesTab
                        }
                    }
                    .padding(24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
        }
        .frame(width: 780, height: 560)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 12)
        .onAppear {
            selectedTab = viewModel.selectedSettingsTab
        }
    }
    
    // MARK: - Left Sidebar Pane
    private var sidebarPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.accentColor)
                Text(viewModel.t("section_settings"))
                    .font(.system(size: 15, weight: .bold))
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 12)
            
            // Tab Items
            VStack(spacing: 2) {
                tabButton(.general, title: "Genel", icon: "gearshape")
                tabButton(.models, title: "Yapay Zeka Modelleri", icon: "cpu")
                tabButton(.storage, title: "Depolama & Çıktı", icon: "folder")
                tabButton(.automation, title: "Otomasyon & Sesli Notlar", icon: "waveform.badge.magnifyingglass")
                tabButton(.updates, title: "Güncellemeler", icon: "arrow.triangle.2.circlepath")
            }
            .padding(.horizontal, 10)
            
            Spacer()
            
            // App Footer
            VStack(alignment: .leading, spacing: 3) {
                Text("Transkript Hub")
                    .font(.system(size: 12, weight: .semibold))
                Text("v\(UpdateChecker.currentVersion) • Apple Silicon Metal")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(16)
        }
    }
    
    private func tabButton(_ tab: SettingsTab, title: String, icon: String) -> some View {
        let isSelected = selectedTab == tab
        return Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                selectedTab = tab
                viewModel.selectedSettingsTab = tab
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 18)
                
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)
                
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Top Bar with Close Button
    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(tabTitle(selectedTab))
                    .font(.system(size: 16, weight: .bold))
                Text(tabSubtitle(selectedTab))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Modern Circular Close Button (X)
            Button(action: {
                viewModel.isSettingsPresented = false
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.secondary.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
    
    // MARK: - 1. General Tab
    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Language Selection
            cardSection(title: viewModel.t("settings_language"), icon: "globe") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(viewModel.t("settings_language_desc"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $viewModel.appLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            
            // Clipboard Automation
            cardSection(title: "Pano İzleme Otomasyonu", icon: "doc.on.clipboard") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Panoya kopyalanan YouTube video bağlantılarını otomatik yakala", isOn: $viewModel.isClipboardMonitoring)
                        .toggleStyle(.switch)
                    
                    Text("Etkinleştirildiğinde tarayıcınızda veya WhatsApp'ta kopyaladığınız YouTube linkleri sıfır tıklamayla kuyruğa eklenir.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            // Spoken Audio Default Language
            cardSection(title: "Varsayılan Konuşma Dili", icon: "waveform") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Videolarda konuşulan dili Whisper modeline bildirir. 'Otomatik Algıla' tüm diller için çalışır.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Picker("Dil:", selection: $viewModel.selectedLanguage) {
                        Text("🌐 Otomatik Algıla").tag("auto")
                        Text("🇹🇷 Türkçe").tag("tr")
                        Text("🇬🇧 İngilizce").tag("en")
                        Text("🇩🇪 Almanca").tag("de")
                        Text("🇫🇷 Fransızca").tag("fr")
                        Text("🇪🇸 İspanyolca").tag("es")
                    }
                    .frame(maxWidth: 240)
                }
            }
        }
    }
    
    // MARK: - 2. Models Tab & Online Catalog Search
    private var modelsTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Search and Online Check Bar
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    
                    TextField("Model ara (örn: turbo, large, türkçe, hızlı)...", text: $viewModel.modelSearchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    
                    if !viewModel.modelSearchQuery.isEmpty {
                        Button(action: { viewModel.modelSearchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Divider().frame(height: 16)
                    
                    Button(action: { viewModel.checkOnlineModels() }) {
                        HStack(spacing: 4) {
                            if viewModel.isCheckingOnlineModels {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text("Yeni Modelleri Tara")
                        }
                        .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isCheckingOnlineModels)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .liquidGlassCapsule(glowColor: .white.opacity(0.6), material: .ultraThinMaterial)
                
                if !viewModel.onlineModelStatusText.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                        Text(viewModel.onlineModelStatusText)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                }
            }
            
            // Filtered Models List
            let specs = WhisperModelCatalog.search(query: viewModel.modelSearchQuery)
            VStack(spacing: 12) {
                ForEach(specs) { spec in
                    catalogModelRow(spec: spec)
                    if spec != specs.last {
                        Divider()
                    }
                }
            }
            .padding(16)
            .liquidGlass(cornerRadius: 14, glowColor: .white.opacity(0.5), material: .ultraThinMaterial)
            
            // Hardware Acceleration Status Card
            cardSection(title: "Donanım Hızlandırması", icon: "cpu") {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Silicon Metal Hızlandırması: Aktif")
                            .font(.system(size: 12, weight: .semibold))
                        Text("whisper.cpp v1.9.2 GPU Unified Memory mimarisi doğrudan devrede.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("Metal GPU")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .liquidGlassCapsule(glowColor: .green, material: .ultraThinMaterial)
                }
            }
        }
    }
    
    private func catalogModelRow(spec: WhisperModelSpec) -> some View {
        let isDownloaded = viewModel.modelManager.isModelDownloaded(spec.model)
        let isActive = viewModel.selectedModel == spec.model
        
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(spec.displayName)
                            .font(.system(size: 13, weight: .bold))
                        
                        Text(spec.sizeDescription)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        if let b = spec.badge {
                            Text(b)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.purple)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.purple.opacity(0.12)))
                        }
                        
                        if isActive {
                            Text("Aktif")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .liquidGlassCapsule(glowColor: .accentColor, material: .ultraThinMaterial)
                        }
                    }
                    
                    Text(spec.summary)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // Action Buttons
                if isDownloaded {
                    HStack(spacing: 8) {
                        if !isActive {
                            Button("Aktif Yap") {
                                viewModel.selectedModel = spec.model
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        
                        Button(role: .destructive) {
                            viewModel.deleteModelInSettings(spec.model)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundColor(.red.opacity(0.8))
                                .padding(5)
                                .background(Color.red.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Modeli Sil")
                    }
                } else if viewModel.downloadingModel == spec.model {
                    VStack(alignment: .trailing, spacing: 4) {
                        ProgressView(value: viewModel.modelDownloadFraction)
                            .progressViewStyle(.linear)
                            .frame(width: 130)
                        Text(viewModel.modelDownloadStatusText.isEmpty ? "İndiriliyor..." : viewModel.modelDownloadStatusText)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Button("İndir") {
                        viewModel.downloadModelInSettings(spec.model)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 2)
    }
    
    // MARK: - 3. Storage Tab
    private var storageTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            cardSection(title: "Transkript Çıktı Dizini", icon: "folder") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Üretilen transkript .txt dosyalarının kaydedildiği hedef klasör:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text(viewModel.outputWriter.defaultOutputDirectory.path)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Button("Finder'da Göster") {
                            viewModel.openInFinder(path: viewModel.outputWriter.defaultOutputDirectory.path)
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(8)
                }
            }
            
            cardSection(title: "Toplu Oturumlarda Kayıt Formatı", icon: "doc.on.doc") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Kuyrukta birden fazla video tamamlandığında dosyalar nasıl kaydedilsin?")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $viewModel.sessionSaveMode) {
                        Text("Her İkisi (Ayrı Dosyalar + Birleşik Oturum Dosyası)").tag(SessionSaveMode.both)
                        Text("Yalnızca Ayrı Ayrı .txt Dosyaları").tag(SessionSaveMode.individual)
                        Text("Yalnızca Tek Birleşik .txt Dosyası").tag(SessionSaveMode.combined)
                    }
                    .pickerStyle(.radioGroup)
                }
            }
        }
    }
    
    // MARK: - 4. Automation & Voice Memos Tab
    private var automationTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Folder Watching Toggle
            cardSection(title: "Klasör ve Sesli Notlar Dinleyicisi", icon: "waveform.badge.magnifyingglass") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.isFolderWatching ? "Klasör İzleme Aktif (Arka Planda Dinleniyor)" : "Klasör İzleme Kapalı")
                                .font(.system(size: 13, weight: .semibold))
                            Text("iCloud Drive veya yerel klasöre yeni sesler düştüğünde sıfır temasla transkript edilir.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $viewModel.isFolderWatching)
                            .toggleStyle(.switch)
                    }
                    
                    Divider()
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("İzlenen Dizin:")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(viewModel.watchedDirectoryPath)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("Finder'da Göster") {
                            viewModel.openInFinder(path: viewModel.watchedDirectoryPath)
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            
            // WhatsApp & Cloud Integration Guide
            cardSection(title: "WhatsApp & Bulut Ses Kayıtları Entegrasyonu", icon: "message.fill") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("WhatsApp, Telegram veya herhangi bir uygulamadan gelen sesli mesajları transkript etmek için:")
                        .font(.system(size: 12, weight: .medium))
                    
                    Text("1. Ses kaydını WhatsApp'ta basılı tutup **Paylaş > Dosyalara Kaydet** seçeneğine basın.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("2. iCloud Drive altındaki **Transkript** klasörünü seçip kaydedin.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("3. Dosya Mac'e .icloud yer tutucu olarak gelse bile, Transkript Hub bunu otomatik olarak algılar ve arka planda derhal indirmeyi başlatır.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("4. İndirme bittiğinde ses kuyruğa alınır, Whisper AI ile yazıya dökülür ve çıktı aynı klasöre kaydedilir!")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            
            // Apple Watch & iPhone Voice Memos Guide
            cardSection(title: "Apple Watch & iPhone Sesli Notlar", icon: "applewatch") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Apple Watch veya iPhone'un yerel Sesli Notlar uygulamasıyla kayıt aldığınızda:")
                        .font(.system(size: 12, weight: .medium))
                    
                    Text("• **Yöntem A (En Kolay):** Ses kaydının yanındaki (...) menüsünden **Paylaş > Dosyalara Kaydet > iCloud Drive / Transkript** yolunu seçin.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text("• **Yöntem B (Apple Kestirmeler - Sıfır Tıklama):** iPhone'unuzdaki Kestirmeler uygulamasından 'Ses Kaydı Al' ve ardından 'iCloud Drive / Transkript Klasörüne Kaydet' kestirmesini kurabilirsiniz. Böylece saatinizden kaydettiğiniz ses Mac'inize otomatik düşer ve anında transkript edilir.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - 5. Updates Tab
    private var updatesTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            cardSection(title: "Sürüm Bilgisi ve Güncellemeler", icon: "arrow.triangle.2.circlepath") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Transkript Hub")
                                .font(.system(size: 15, weight: .bold))
                            Text("Mevcut Sürüm: v\(UpdateChecker.currentVersion) (Production Build)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: { viewModel.checkForUpdates() }) {
                            HStack(spacing: 5) {
                                if viewModel.isCheckingUpdates {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text("Güncellemeleri Şimdi Denetle")
                            }
                            .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(viewModel.isCheckingUpdates)
                    }
                    
                    Divider()
                    
                    // Update check status result box
                    if !viewModel.updateCheckStatusText.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: viewModel.updateInfo?.isNewerThanCurrent == true ? "sparkles" : "checkmark.seal.fill")
                                .font(.system(size: 16))
                                .foregroundColor(viewModel.updateInfo?.isNewerThanCurrent == true ? .purple : .green)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(viewModel.updateCheckStatusText)
                                    .font(.system(size: 12, weight: .semibold))
                                if let info = viewModel.updateInfo, info.isNewerThanCurrent {
                                    Text(info.releaseNotes)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(3)
                                }
                            }
                            
                            Spacer()
                            
                            if let info = viewModel.updateInfo, info.isNewerThanCurrent {
                                Button("GitHub'da İndir") {
                                    viewModel.openInBrowser(url: info.htmlURL)
                                }
                                .font(.system(size: 11, weight: .bold))
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(12)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(10)
                    }
                    
                    Toggle("Uygulama açılışında güncellemeleri otomatik denetle", isOn: $viewModel.autoCheckUpdates)
                        .toggleStyle(.switch)
                }
            }
            
            cardSection(title: "Açık Kaynak ve Depo", icon: "link") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GitHub Deposu")
                            .font(.system(size: 12, weight: .semibold))
                        Text("https://github.com/Akifulutas/Transkript-Hub")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Depoyu Aç") {
                        viewModel.openInBrowser(url: "https://github.com/Akifulutas/Transkript-Hub")
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
    
    // MARK: - Helper Views & Functions
    private func cardSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 13, weight: .bold))
            }
            
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlass(cornerRadius: 12, glowColor: .white.opacity(0.5), material: .ultraThinMaterial)
        }
    }
    
    private func tabTitle(_ tab: SettingsTab) -> String {
        switch tab {
        case .general: return "Genel Ayarlar"
        case .models: return "Yapay Zeka Modelleri & Model Kataloğu"
        case .storage: return "Depolama ve Çıktı Dizini"
        case .automation: return "Otomasyon & Sesli Notlar"
        case .updates: return "Uygulama Güncellemeleri"
        }
    }
    
    private func tabSubtitle(_ tab: SettingsTab) -> String {
        switch tab {
        case .general: return "Arayüz dili, pano izleme ve sistem tercihleri."
        case .models: return "Whisper.cpp modellerini arayın, indirin ve donanım durumunu denetleyin."
        case .storage: return "Transkript dosyalarının kaydedileceği konum ve format ayarları."
        case .automation: return "Apple Watch, iPhone ve WhatsApp ses kayıtlarının otomatik işlenmesi."
        case .updates: return "En son çıkan sürüm ve model yeniliklerini takip edin."
        }
    }
}

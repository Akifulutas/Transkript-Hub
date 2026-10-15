import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case turkish = "tr"
    case english = "en"
    case german = "de"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .turkish: return "🇹🇷 Türkçe"
        case .english: return "🇬🇧 English"
        case .german: return "🇩🇪 Deutsch"
        }
    }
}

public struct L10n {
    public static func tr(_ key: String, lang: AppLanguage, _ args: CVarArg...) -> String {
        let format = strings[lang]?[key] ?? strings[.turkish]?[key] ?? key
        if args.isEmpty {
            return format
        }
        return String(format: format, arguments: args)
    }
    
    private static let strings: [AppLanguage: [String: String]] = [
        .turkish: [
            // Menus & Sections
            "section_queue": "Kuyruk",
            "section_history": "Geçmiş",
            "section_watched_folder": "İzlenen Klasör",
            "section_settings": "Ayarlar",
            
            // Actions
            "action_transcribe_queue": "Transkripte Yolla",
            "action_start_now": "Şimdi Başlat",
            "action_select_all": "Tümünü Seç",
            "action_deselect": "Seçimi Kaldır",
            "action_clear_queue": "Kuyruğu Temizle",
            "action_paste_clipboard": "Panodan Bağlantı Ekle",
            "action_audio_file": "Ses Dosyası...",
            "action_clipboard_monitoring": "Pano İzleniyor",
            "action_clipboard_off": "Pano İzle: Kapalı",
            "action_copy": "Kopyala",
            "action_copied": "Kopyalandı!",
            "action_open_finder": "Finder'da Göster",
            "action_open_browser": "Tarayıcıda Aç",
            "action_remove_item": "Kuyruktan Çıkar",
            "action_retry": "Tekrar Dene",
            "action_retry_all": "Tümünü Yeniden Dene",
            "action_cancel": "Vazgeç",
            "action_recommended": "Önerilen",
            "action_words": "kelime",
            "action_chars": "karakter",
            "action_search_text": "Metinde ara...",
            
            // Statuses
            "status_attention_required": "MÜDAHALE GEREKİYOR",
            "status_processing_queue": "İŞLENİYOR & KUYRUK",
            "status_completed": "TAMAMLANANLAR",
            "status_queued": "Kuyrukta",
            "status_fetching": "İndiriliyor",
            "status_transcribing": "Transkript Ediliyor",
            "status_failed": "Hata",
            "status_ready": "Hazır",
            "status_live_transcribing": "CANLI TRANSKRİPT EDİLİYOR",
            "status_metal_active": "Apple Silicon GPU Metal ile transkript ediliyor...",
            "status_fetching_audio": "YouTube sesi indiriliyor (yt-dlp)...",
            
            // Sheets
            "sheet_playlist_detected": "Oynatma Listesi Algılandı",
            "sheet_channel_detected": "YouTube Kanalı Algılandı",
            "sheet_batch_question": "Kaç adet videonun kuyruğa eklenmesini istersiniz?",
            "sheet_download_all_playlist": "Tüm Videoları İndir (Tüm Liste)",
            "sheet_download_all_channel": "Tüm Kanal Videolarını İndir",
            "sheet_single_video_only": "Yalnızca Bu Tek Videoyu Ekle",
            "sheet_latest_videos": "En Yeni Videoları Al",
            "sheet_custom_count": "Özel Sayı Belirle",
            "sheet_save_mode_title": "Transkript Kayıt Formatı",
            "sheet_save_mode_desc": "Kuyrukta %d video bulunuyor. Dosyalar nasıl kaydedilsin?",
            "sheet_save_both": "Her İkisi (Ayrı + Birleşik)",
            "sheet_save_both_desc": "Hem her videonun kendi bağımsız dosyasını hem de tüm oturumu içeren tek birleşik dosyayı kaydeder.",
            "sheet_save_individual": "Ayrı Ayrı Dosyalar",
            "sheet_save_individual_desc": "Her video için kendi başlığıyla bağımsız bir .txt dosyası oluşturur.",
            "sheet_save_combined": "Yalnızca Tek Birleşik Dosya",
            "sheet_save_combined_desc": "Tüm videoların transkriptlerini sırayla tek bir oturum dosyasında birleştirir.",
            
            // Detail & Live Stream
            "status_live_stream_header": "Canlı Transkript Akışı",
            "status_live_stream_desc": "Metal GPU ile çözümlenen kelimeler anlık görüntüleniyor",
            "detail_session_combined": "Birleşik Oturum (%d)",
            "detail_single_video": "Tekil Video",
            "detail_no_transcript": "Henüz tamamlanan transkript bulunmuyor.",
            "detail_combined_title": "Toplu Oturum Transkripti (%d Video)",
            "detail_combined_desc_selected": "%d video seçildi ve birleştirildi",
            "detail_combined_desc_all": "Kuyruktaki tüm videolar tek bir transkript olarak birleştirildi",
            "detail_ready_title": "İşleme Hazır",
            "detail_ready_desc": "Transkript işlemini başlatmak için ⌘Return tuşlayabilir veya araç çubuğundaki butona basabilirsiniz.",
            "detail_error_title": "İndirme / Transkript Hatası",
            "detail_retry_btn": "Tek Tıkla Yeniden Dene",
            "detail_hero_welcome": "Transkript Hub",
            "detail_hero_sub": "Yerel Yapay Zeka Ses ve Video Metne Çevirme Stüdyosu",
            "action_quick_add_placeholder": "YouTube linki veya ses dosyası...",
            "action_add": "Ekle",
            "action_empty_queue_title": "Kuyruk Boş",
            "action_empty_queue_desc": "Panodaki linki almak için ⌘V tuşlayın veya dosyaları sağdaki stüdyo alanına sürükleyin.",
            
            // Settings
            "settings_language": "Arayüz Dili",
            "settings_language_desc": "Uygulamanın menü, buton ve mesajlarında kullanılacak dil.",
            "settings_whisper_models": "Whisper Yapay Zeka Modelleri",
            "settings_whisper_desc": "Modeller yerel olarak Mac'inizde saklanır ve Apple Silicon Metal GPU hızlandırıcısını doğrudan kullanır.",
            "settings_output_dir": "Çıktı Dizini",
            "settings_open_folder": "Klasörü Aç",
            "settings_hardware": "Donanım ve Hızlandırma",
            "settings_metal_active": "Apple Silicon Metal Hızlandırması: Aktif",
            "settings_metal_desc": "Cihaz içi yerel motor (whisper.cpp v1.9.2 Metal framework)",
            "settings_download": "İndir",
            "settings_downloaded": "İndirildi",
            "settings_active": "Aktif"
        ],
        
        .english: [
            // Menus & Sections
            "section_queue": "Queue",
            "section_history": "History",
            "section_watched_folder": "Watched Folder",
            "section_settings": "Settings",
            
            // Actions
            "action_transcribe_queue": "Transcribe Queue",
            "action_start_now": "Start Now",
            "action_select_all": "Select All",
            "action_deselect": "Deselect",
            "action_clear_queue": "Clear Queue",
            "action_paste_clipboard": "Paste Link from Clipboard",
            "action_audio_file": "Audio File...",
            "action_clipboard_monitoring": "Clipboard Monitored",
            "action_clipboard_off": "Clipboard: Off",
            "action_copy": "Copy",
            "action_copied": "Copied!",
            "action_open_finder": "Show in Finder",
            "action_open_browser": "Open in Browser",
            "action_remove_item": "Remove from Queue",
            "action_retry": "Retry",
            "action_retry_all": "Retry All",
            "action_cancel": "Cancel",
            "action_recommended": "Recommended",
            "action_words": "words",
            "action_chars": "chars",
            "action_search_text": "Search in text...",
            
            // Statuses
            "status_attention_required": "ACTION REQUIRED",
            "status_processing_queue": "PROCESSING & QUEUE",
            "status_completed": "COMPLETED",
            "status_queued": "Queued",
            "status_fetching": "Downloading",
            "status_transcribing": "Transcribing",
            "status_failed": "Error",
            "status_ready": "Ready",
            "status_live_transcribing": "LIVE TRANSCRIBING",
            "status_metal_active": "Transcribing with Apple Silicon GPU Metal...",
            "status_fetching_audio": "Downloading YouTube audio (yt-dlp)...",
            
            // Sheets
            "sheet_playlist_detected": "Playlist Detected",
            "sheet_channel_detected": "YouTube Channel Detected",
            "sheet_batch_question": "How many videos would you like to add to the queue?",
            "sheet_download_all_playlist": "Download All Videos (Full List)",
            "sheet_download_all_channel": "Download All Channel Videos",
            "sheet_single_video_only": "Add Only This Single Video",
            "sheet_latest_videos": "Get Latest Videos",
            "sheet_custom_count": "Set Custom Count",
            "sheet_save_mode_title": "Transcript Save Format",
            "sheet_save_mode_desc": "%d videos in queue. How should files be saved?",
            "sheet_save_both": "Both (Separate + Combined)",
            "sheet_save_both_desc": "Saves both individual files for each video and one consolidated session file.",
            "sheet_save_individual": "Separate Files",
            "sheet_save_individual_desc": "Creates an individual .txt file for each video titled with its name.",
            "sheet_save_combined": "Single Combined File Only",
            "sheet_save_combined_desc": "Combines all transcripts in order into a single session document.",
            
            // Detail & Live Stream
            "status_live_stream_header": "Live Transcript Stream",
            "status_live_stream_desc": "Words decoded with Metal GPU are displayed in real-time",
            "detail_session_combined": "Combined Session (%d)",
            "detail_single_video": "Single Video",
            "detail_no_transcript": "No transcript completed yet.",
            "detail_combined_title": "Batch Session Transcript (%d Videos)",
            "detail_combined_desc_selected": "%d videos selected and merged",
            "detail_combined_desc_all": "All videos in queue merged into a single transcript",
            "detail_ready_title": "Ready to Process",
            "detail_ready_desc": "Press ⌘Return or click the button in toolbar to start transcribing.",
            "detail_error_title": "Download / Transcription Error",
            "detail_retry_btn": "Retry with One Click",
            "detail_hero_welcome": "Transkript Hub",
            "detail_hero_sub": "Local AI Audio & Video Transcription Studio",
            "action_quick_add_placeholder": "YouTube link or audio file...",
            "action_add": "Add",
            "action_empty_queue_title": "Queue is Empty",
            "action_empty_queue_desc": "Press ⌘V to paste clipboard link or drag files into the studio on the right.",
            
            // Settings
            "settings_language": "Interface Language",
            "settings_language_desc": "Language used for application menus, buttons, and notifications.",
            "settings_whisper_models": "Whisper AI Models",
            "settings_whisper_desc": "Models are stored locally on your Mac and utilize Apple Silicon Metal GPU acceleration.",
            "settings_output_dir": "Output Directory",
            "settings_open_folder": "Open Folder",
            "settings_hardware": "Hardware & Acceleration",
            "settings_metal_active": "Apple Silicon Metal Acceleration: Active",
            "settings_metal_desc": "On-device local engine (whisper.cpp v1.9.2 Metal framework)",
            "settings_download": "Download",
            "settings_downloaded": "Downloaded",
            "settings_active": "Active"
        ],
        
        .german: [
            // Menus & Sections
            "section_queue": "Warteschlange",
            "section_history": "Verlauf",
            "section_watched_folder": "Überwachter Ordner",
            "section_settings": "Einstellungen",
            
            // Actions
            "action_transcribe_queue": "Warteschlange transkribieren",
            "action_start_now": "Jetzt starten",
            "action_select_all": "Alle auswählen",
            "action_deselect": "Auswahl aufheben",
            "action_clear_queue": "Warteschlange leeren",
            "action_paste_clipboard": "Link aus Zwischenablage einfügen",
            "action_audio_file": "Audiodatei...",
            "action_clipboard_monitoring": "Zwischenablage aktiv",
            "action_clipboard_off": "Zwischenablage: Aus",
            "action_copy": "Kopieren",
            "action_copied": "Kopiert!",
            "action_open_finder": "Im Finder anzeigen",
            "action_open_browser": "Im Browser öffnen",
            "action_remove_item": "Aus Warteschlange entfernen",
            "action_retry": "Wiederholen",
            "action_retry_all": "Alle wiederholen",
            "action_cancel": "Abbrechen",
            "action_recommended": "Empfohlen",
            "action_words": "Wörter",
            "action_chars": "Zeichen",
            "action_search_text": "Im Text suchen...",
            
            // Statuses
            "status_attention_required": "EINGRIFF ERFORDERLICH",
            "status_processing_queue": "IN BEARBEITUNG & WARTESCHLANGE",
            "status_completed": "ABGESCHLOSSEN",
            "status_queued": "In Warteschlange",
            "status_fetching": "Wird heruntergeladen",
            "status_transcribing": "Wird transkribiert",
            "status_failed": "Fehler",
            "status_ready": "Bereit",
            "status_live_transcribing": "LIVE-TRANSKRIPTION",
            "status_metal_active": "Transkription mit Apple Silicon GPU Metal...",
            "status_fetching_audio": "YouTube-Audio wird heruntergeladen (yt-dlp)...",
            
            // Sheets
            "sheet_playlist_detected": "Wiedergabeliste erkannt",
            "sheet_channel_detected": "YouTube-Kanal erkannt",
            "sheet_batch_question": "Wie viele Videos möchten Sie zur Warteschlange hinzufügen?",
            "sheet_download_all_playlist": "Alle Videos herunterladen (Gesamte Liste)",
            "sheet_download_all_channel": "Alle Kanalvideos herunterladen",
            "sheet_single_video_only": "Nur dieses einzelne Video hinzufügen",
            "sheet_latest_videos": "Neueste Videos abrufen",
            "sheet_custom_count": "Benutzerdefinierte Anzahl",
            "sheet_save_mode_title": "Transkript-Speicherformat",
            "sheet_save_mode_desc": "%d Videos in Warteschlange. Wie sollen Dateien gespeichert werden?",
            "sheet_save_both": "Beide (Einzeln + Kombiniert)",
            "sheet_save_both_desc": "Speichert sowohl separate Dateien für jedes Video als auch eine zusammengefasste Sitzungsdatei.",
            "sheet_save_individual": "Separate Dateien",
            "sheet_save_individual_desc": "Erstellt für jedes Video eine eigene .txt-Datei mit dem Videotitel.",
            "sheet_save_combined": "Nur eine kombinierte Datei",
            "sheet_save_combined_desc": "Kombiniert alle Transkripte der Reihe nach in einem einzigen Dokument.",
            
            // Detail & Live Stream
            "status_live_stream_header": "Live-Transkriptionsstream",
            "status_live_stream_desc": "Mit Metal-GPU decodierte Wörter werden in Echtzeit angezeigt",
            "detail_session_combined": "Kombinierte Sitzung (%d)",
            "detail_single_video": "Einzelnes Video",
            "detail_no_transcript": "Noch kein Transkript abgeschlossen.",
            "detail_combined_title": "Stapel-Sitzungstranskript (%d Videos)",
            "detail_combined_desc_selected": "%d Videos ausgewählt und zusammengeführt",
            "detail_combined_desc_all": "Alle Videos in der Warteschlange in einem einzigen Transkript zusammengeführt",
            "detail_ready_title": "Bereit zur Verarbeitung",
            "detail_ready_desc": "Drücken Sie ⌘Return oder klicken Sie auf die Schaltfläche in der Symbolleiste, um die Transkription zu starten.",
            "detail_error_title": "Download- / Transkriptionsfehler",
            "detail_retry_btn": "Mit einem Klick wiederholen",
            "detail_hero_welcome": "Transkript Hub",
            "detail_hero_sub": "Lokales KI Audio- & Video-Transkriptionsstudio",
            "action_quick_add_placeholder": "YouTube-Link oder Audiodatei...",
            "action_add": "Hinzufügen",
            "action_empty_queue_title": "Warteschlange ist leer",
            "action_empty_queue_desc": "Drücken Sie ⌘V, um den Zwischenablage-Link einzufügen, oder ziehen Sie Dateien in das Studio rechts.",
            
            // Settings
            "settings_language": "Sprache der Benutzeroberfläche",
            "settings_language_desc": "Sprache für Menüs, Schaltflächen und Benachrichtigungen.",
            "settings_whisper_models": "Whisper KI-Modelle",
            "settings_whisper_desc": "Modelle werden lokal auf Ihrem Mac gespeichert und nutzen die Apple Silicon Metal GPU-Beschleunigung.",
            "settings_output_dir": "Ausgabeverzeichnis",
            "settings_open_folder": "Ordner öffnen",
            "settings_hardware": "Hardware & Beschleunigung",
            "settings_metal_active": "Apple Silicon Metal Beschleunigung: Aktiv",
            "settings_metal_desc": "Lokale On-Device-Engine (whisper.cpp v1.9.2 Metal framework)",
            "settings_download": "Herunterladen",
            "settings_downloaded": "Heruntergeladen",
            "settings_active": "Aktiv"
        ]
    ]
}

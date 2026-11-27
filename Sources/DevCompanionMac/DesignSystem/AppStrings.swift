import Foundation
import DevCompanionCore

/// Centralized localized strings backed by `Localizable.xcstrings` in `Bundle.module`.
/// Views and Presenters must reference `AppStrings` instead of raw string literals.
enum AppStrings {
    private static let xcstringsTable: [String: [String: String]] = {
        guard let url = Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = json["strings"] as? [String: Any]
        else { return [:] }

        var result: [String: [String: String]] = [:]
        for (key, rawEntry) in strings {
            guard let entry = rawEntry as? [String: Any],
                  let locs = entry["localizations"] as? [String: Any]
            else { continue }
            var langMap: [String: String] = [:]
            for (lang, rawLoc) in locs {
                if let locObj = rawLoc as? [String: Any],
                   let unit = locObj["stringUnit"] as? [String: Any],
                   let value = unit["value"] as? String {
                    langMap[lang] = value
                }
            }
            result[key] = langMap
        }
        return result
    }()

    private static func loc(_ key: String) -> String {
        let override = AppPreferencesStore().load().languageOverride
        let preferred: String = switch override {
        case .en: "en"
        case .id: "id"
        case .system:
            Locale.preferredLanguages.first?.lowercased().hasPrefix("id") == true ? "id" : "en"
        }

        if override != .system,
           let lprojPath = Bundle.module.path(forResource: preferred, ofType: "lproj"),
           let langBundle = Bundle(path: lprojPath) {
            let val = langBundle.localizedString(forKey: key, value: "__MISSING__", table: nil)
            if val != "__MISSING__" && val != key {
                return val
            }
        } else {
            let fromBundle = Bundle.module.localizedString(forKey: key, value: "__MISSING__", table: nil)
            if fromBundle != "__MISSING__" && fromBundle != key {
                return fromBundle
            }
        }

        if let entry = xcstringsTable[key] {
            return entry[preferred] ?? entry["en"] ?? key
        }
        return key
    }

    enum Common {
        static var appName: String { loc("common.app_name") }
        static var ready: String { loc("common.ready") }
        static var copy: String { loc("common.copy") }
        static var copyCode: String { loc("common.copy_code") }
        static var copyDiff: String { loc("common.copy_diff") }
        static var scanProject: String { loc("common.scan_project") }
        static var scanWorkspace: String { loc("common.scan_workspace") }
        static var scanning: String { loc("common.scanning") }
        static var selectXcodeProject: String { loc("common.select_xcode_project") }
        static var selectXcodeProjectButton: String { loc("common.select_xcode_project_button") }
        static var clearProject: String { loc("common.clear_project") }
        static var noProjectSelected: String { loc("common.no_project_selected") }
        static var selectProjectFirst: String { loc("common.select_project_first") }
    }

    enum Navigation {
        static var workspaces: String { loc("nav.workspaces") }
        static var monitorSection: String { loc("nav.monitor_section") }
        static var toolsSection: String { loc("nav.tools_section") }
        static var overview: String { loc("nav.overview") }
        static var crashlytics: String { loc("nav.crashlytics") }
        static var simulator: String { loc("nav.simulator") }
        static var leaksAndHangs: String { loc("nav.leaks_and_hangs") }
        static var codeReview: String { loc("nav.code_review") }
        static var unitTests: String { loc("nav.unit_tests") }
        static var utilities: String { loc("nav.utilities") }
    }

    enum TopBar {
        static var noBootedSimulator: String { loc("topbar.no_booted_simulator") }
        static var themeAndBackground: String { loc("topbar.theme_and_bg") }
        static var quickSimulator: String { loc("topbar.quick_simulator") }
        static var darkShort: String { loc("topbar.dark_short") }
        static var lightShort: String { loc("topbar.light_short") }
        static var cleanBarShort: String { loc("topbar.clean_bar_short") }
        static var simulatorsSection: String { loc("topbar.simulators_section") }
        static var physicalDevicesSection: String { loc("topbar.physical_devices_section") }
        static var deviceConnected: String { loc("topbar.device_connected") }
        static var devicePaired: String { loc("topbar.device_paired") }
        static var useDeviceTarget: String { loc("topbar.use_device_target") }
        static var activeDeviceTarget: String { loc("topbar.active_device_target") }

        static func physicalDevicesCount(_ count: Int) -> String {
            String(format: loc("topbar.physical_devices_count"), count)
        }
    }

    enum Overview {
        static var title: String { loc("overview.title") }
        static var subtitle: String { loc("overview.subtitle") }
        static var scanTitle: String { loc("overview.scan_title") }
        static var scanSubtitle: String { loc("overview.scan_subtitle") }
        static var simulatorsBooted: String { loc("overview.simulators_booted") }
        static var hangCrashReports: String { loc("overview.hang_crash_reports") }
        static var diagnosticReportsPath: String { loc("overview.diagnostic_reports_path") }
        static var codeReviewFindings: String { loc("overview.code_review_findings") }

        static func totalAvailable(_ count: Int) -> String {
            String(format: loc("overview.total_available"), count)
        }

        static func scanCompleted(_ booted: Int, _ reports: Int) -> String {
            String(format: loc("overview.scan_completed"), booted, reports)
        }

        static var scanningMessage: String { loc("overview.scanning_message") }
        static var resetProjectData: String { loc("overview.reset_project_data") }
        static var resetConfirmMessage: String { loc("overview.reset_confirm_message") }
        static var exportBackup: String { loc("overview.export_backup") }
        static var restoreBackup: String { loc("overview.restore_backup") }
        static var dataResetDone: String { loc("overview.data_reset_done") }
        static func backupExported(_ fileName: String) -> String {
            String(format: loc("overview.backup_exported"), fileName)
        }
        static func backupRestored(_ count: Int) -> String {
            String(format: loc("overview.backup_restored"), count)
        }
        static var sessionCardTitle: String { loc("overview.session_card_title") }
        static var sessionCardSub: String { loc("overview.session_card_sub") }
        static var quickJumpHint: String { loc("overview.quick_jump_hint") }
        static var needProjectBanner: String { loc("overview.need_project_banner") }
        static var needSimulatorBanner: String { loc("overview.need_simulator_banner") }
        static var openDmgInstaller: String { loc("overview.open_dmg_installer") }
        static func openedInstallerFolder(_ path: String) -> String {
            String(format: loc("overview.opened_installer_folder"), path)
        }
    }

    enum Crashlytics {
        static var title: String { loc("crash.title") }
        static var subtitle: String { loc("crash.subtitle") }
        static var totalEvents: String { loc("crash.total_events") }
        static var fatalCrashes: String { loc("crash.fatal_crashes") }
        static var nonFatalHangs: String { loc("crash.non_fatal_hangs") }
        static var memoryJetsam: String { loc("crash.memory_jetsam") }
        static var searchPlaceholder: String { loc("crash.search_placeholder") }
        static var refreshReports: String { loc("crash.refresh_reports") }
        static var noReportsFound: String { loc("crash.no_reports_found") }
        static var stackTraceTab: String { loc("crash.stack_trace_tab") }
        static var rawLogTab: String { loc("crash.raw_log_tab") }
        static var appFrameBadge: String { loc("crash.app_frame_badge") }
        static var sysFrameBadge: String { loc("crash.sys_frame_badge") }
        static var selectEventPrompt: String { loc("crash.select_event_prompt") }
        static var openCrashlytics: String { loc("crash.open_crashlytics") }
        static var timelineTitle: String { loc("crash.timeline_title") }
        static var timelineSub: String { loc("crash.timeline_sub") }
        static var whereFileLineLabel: String { loc("crash.where_file_line_label") }
        static var whenActionLabel: String { loc("crash.when_action_label") }
        static var whyCauseLabel: String { loc("crash.why_cause_label") }
        static var agentFixSectionTitle: String { loc("crash.agent_fix_section_title") }
    }

    enum Simulator {
        static var title: String { loc("simulator.title") }
        static var refreshDevices: String { loc("simulator.refresh_devices") }
        static var appearanceSection: String { loc("simulator.appearance_section") }
        static var darkMode: String { loc("simulator.dark_mode") }
        static var lightMode: String { loc("simulator.light_mode") }
        static var cleanStatusBar: String { loc("simulator.clean_status_bar") }
        static var screenshotToClipboard: String { loc("simulator.screenshot_to_clipboard") }
        static var dynamicTypeSize: String { loc("simulator.dynamic_type_size") }
        static var deepLinkSection: String { loc("simulator.deep_link_section") }
        static var deepLinkPlaceholder: String { loc("simulator.deep_link_placeholder") }
        static var openURL: String { loc("simulator.open_url") }
        static var pushSection: String { loc("simulator.push_section") }
        static var bundleIDPlaceholder: String { loc("simulator.bundle_id_placeholder") }
        static var pushTitlePlaceholder: String { loc("simulator.push_title_placeholder") }
        static var pushBodyPlaceholder: String { loc("simulator.push_body_placeholder") }
        static var sendPush: String { loc("simulator.send_push") }
        static var statusBarOverridden: String { loc("simulator.status_bar_overridden") }
        static var screenshotFailed: String { loc("simulator.screenshot_failed") }

        static func appearanceUpdated(_ mode: String) -> String {
            String(format: loc("simulator.appearance_updated"), mode)
        }
        static func dynamicTypeUpdated(_ size: String) -> String {
            String(format: loc("simulator.dynamic_type_updated"), size)
        }
        static func deepLinkOpened(_ url: String) -> String {
            String(format: loc("simulator.deep_link_opened"), url)
        }
        static func pushSent(_ bundleID: String) -> String {
            String(format: loc("simulator.push_sent"), bundleID)
        }
        static func screenshotCopied(_ fileName: String) -> String {
            String(format: loc("simulator.screenshot_copied"), fileName)
        }
        static var liveReloadTitle: String { loc("simulator.live_reload_title") }
        static var liveReloadSubtitle: String { loc("simulator.live_reload_subtitle") }
        static var startLiveReload: String { loc("simulator.start_live_reload") }
        static var stopLiveReload: String { loc("simulator.stop_live_reload") }
        static var liveReloadStopped: String { loc("simulator.live_reload_stopped") }
        static var liveReloadFailed: String { loc("simulator.live_reload_failed") }
        static var liveReloadSchemePlaceholder: String { loc("simulator.live_reload_scheme_placeholder") }
        static func liveReloadWatching(_ project: String) -> String {
            String(format: loc("simulator.live_reload_watching"), project)
        }
        static func liveReloadTriggered(_ files: String) -> String {
            String(format: loc("simulator.live_reload_triggered"), files)
        }
        static func liveReloadSucceeded(_ files: String) -> String {
            String(format: loc("simulator.live_reload_succeeded"), files)
        }
    }

    enum Performance {
        static var title: String { loc("perf.title") }
        static var subtitle: String { loc("perf.subtitle") }
        static var agentPicker: String { loc("perf.agent_picker") }
        static var openInstruments: String { loc("perf.open_instruments") }
        static var geminiKeyPlaceholder: String { loc("perf.gemini_key_placeholder") }
        static var ollamaModelPlaceholder: String { loc("perf.ollama_model_placeholder") }
        static var liveTelemetryTitle: String { loc("perf.live_telemetry_title") }
        static var processPicker: String { loc("perf.process_picker") }
        static var selectSimulatorApp: String { loc("perf.select_simulator_app") }
        static var refreshPIDs: String { loc("perf.refresh_pids") }
        static var stopLive: String { loc("perf.stop_live") }
        static var startLive: String { loc("perf.start_live") }
        static var cpuUsage: String { loc("perf.cpu_usage") }
        static var liveSimulatorSub: String { loc("perf.live_simulator_sub") }
        static var memory: String { loc("perf.memory") }
        static var rssResidentSub: String { loc("perf.rss_resident_sub") }
        static var lastHang: String { loc("perf.last_hang") }
        static var diagnosticReportsSub: String { loc("perf.diagnostic_reports_sub") }
        static var potentialLeaks: String { loc("perf.potential_leaks") }
        static var staticCallTreeSub: String { loc("perf.static_call_tree_sub") }
        static var cpuTrackTitle: String { loc("perf.cpu_track_title") }
        static var cpuTrackIdleSub: String { loc("perf.cpu_track_idle_sub") }
        static var memoryTrackTitle: String { loc("perf.memory_track_title") }
        static var callTreeTitle: String { loc("perf.call_tree_title") }
        static var noLeaksOrHangs: String { loc("perf.no_leaks_or_hangs") }
        static var openInXcode: String { loc("perf.open_in_xcode") }
        static var copyAntigravityPrompt: String { loc("perf.copy_antigravity_prompt") }
        static var antigravityPromptCopied: String { loc("perf.antigravity_prompt_copied") }
        static var rootCauseTitle: String { loc("perf.root_cause_title") }
        static var manualStepsTitle: String { loc("perf.manual_steps_title") }
        static var applyPatch: String { loc("perf.apply_patch") }
        static var undoPatch: String { loc("perf.undo_patch") }
        static var emptySelectionPrompt: String { loc("perf.empty_selection_prompt") }
        static var noActiveSimProcess: String { loc("perf.no_active_sim_process") }
        static var processStopped: String { loc("perf.process_stopped") }
        static var noFindingForXcode: String { loc("perf.no_finding_for_xcode") }
        static var patchAppliedToEditor: String { loc("perf.patch_applied_to_editor") }
        static var crashReportTitle: String { loc("perf.crash_report_title") }
        static var exceptionLabel: String { loc("perf.exception_label") }
        static var terminationLabel: String { loc("perf.termination_label") }
        static var culpritLabel: String { loc("perf.culprit_label") }
        static var sourceLocationLabel: String { loc("perf.source_location_label") }
        static var offendingCodeLabel: String { loc("perf.offending_code_label") }
        static var rawLogLabel: String { loc("perf.raw_log_label") }
        static var showSystemReports: String { loc("perf.show_system_reports") }
        static var priorityAll: String { loc("perf.priority_all") }
        static var runtimeLeaksTitle: String { loc("perf.runtime_leaks_title") }
        static var runtimeLeaksZero: String { loc("perf.runtime_leaks_zero") }
        static var dynamicGraphTitle: String { loc("perf.dynamic_graph_title") }
        static var staticFreezeGraphTitle: String { loc("perf.static_freeze_graph_title") }
        static var staticFreezeGraphSub: String { loc("perf.static_freeze_graph_sub") }
        static var noFreezeCaptured: String { loc("perf.no_freeze_captured") }
        static var clearFreezeHistory: String { loc("perf.clear_freeze_history") }
        static var clickToInspectFix: String { loc("perf.click_to_inspect_fix") }
        static var freezeFlatlineBadge: String { loc("perf.freeze_flatline_badge") }
        static var newBadge: String { loc("perf.new_badge") }
        static var inspectInAgentFix: String { loc("perf.inspect_in_agent_fix") }

        static func freezeElapsedRunning(_ seconds: Double, _ location: String) -> String {
            String(format: loc("perf.freeze_elapsed_running"), seconds, location)
        }
        static func freezeDurationBadge(_ seconds: Double) -> String {
            String(format: loc("perf.freeze_duration_badge"), seconds)
        }
        static func staticFreezeStats(_ count: Int, _ maxSec: Double) -> String {
            String(format: loc("perf.static_freeze_stats"), count, maxSec)
        }
        static func runtimeLeaksSub(_ count: Int, _ kb: Int) -> String {
            String(format: loc("perf.runtime_leaks_sub"), count, kb)
        }

        static func liveCPUSub(_ cpu: Double) -> String {
            String(format: loc("perf.live_cpu_sub"), cpu)
        }
        static func liveMemorySub(_ mb: Double) -> String {
            String(format: loc("perf.live_memory_sub"), mb)
        }
        static func retainCyclesCount(_ count: Int) -> String {
            String(format: loc("perf.retain_cycles_count"), count)
        }
        static func lineTitle(_ line: Int) -> String {
            String(format: loc("perf.line_title"), line)
        }
        static func agentFixReady(_ fileName: String, _ line: Int) -> String {
            String(format: loc("perf.agent_fix_ready"), fileName, line)
        }
        static func patchAppliedToFile(_ fileName: String) -> String {
            String(format: loc("perf.patch_applied_to_file"), fileName)
        }
        static func patchRolledBack(_ fileName: String) -> String {
            String(format: loc("perf.patch_rolled_back"), fileName)
        }
        static func sampleHover(_ index: Int, _ value: Double, _ unit: String) -> String {
            String(format: loc("perf.sample_hover"), index, value, unit)
        }
        static func sampleLatest(_ value: Double, _ unit: String) -> String {
            String(format: loc("perf.sample_latest"), value, unit)
        }
        static func formattedCPU(_ cpu: Double) -> String {
            String(format: "%.1f%%", cpu)
        }
        static func formattedMemory(_ mb: Double) -> String {
            String(format: "%.1f MB", mb)
        }
        static func formattedHang(_ seconds: Double?) -> String {
            String(format: "%.2fs", seconds ?? 0)
        }
    }

    enum CodeReview {
        static var title: String { loc("codereview.title") }
        static var subtitle: String { loc("codereview.subtitle") }
        static var analyzeCode: String { loc("codereview.analyze_code") }
        static var pasteEditorTitle: String { loc("codereview.paste_editor_title") }
        static var noFindings: String { loc("codereview.no_findings") }
        static var emptyPrompt: String { loc("codereview.empty_prompt") }
        static var sourceBranchLabel: String { loc("codereview.source_branch_label") }
        static var targetBranchLabel: String { loc("codereview.target_branch_label") }
        static var changedLinesOnly: String { loc("codereview.changed_lines_only") }
        static var modulePickerLabel: String { loc("codereview.module_picker_label") }
        static var browseFolder: String { loc("codereview.browse_folder") }
        static var copyPRReport: String { loc("codereview.copy_pr_report") }
        static var prReportCopied: String { loc("codereview.pr_report_copied") }
        static var prReadyBadge: String { loc("codereview.pr_ready_badge") }
        static var prBlockedBadge: String { loc("codereview.pr_blocked_badge") }
        static var commitsTitle: String { loc("codereview.commits_title") }
        static var categoryAll: String { loc("codereview.category_all") }
        static var selectScopePrompt: String { loc("codereview.select_scope_prompt") }
        static var selectSourceBranchPlaceholder: String { loc("codereview.select_source_branch_placeholder") }
        static var selectTargetBranchPlaceholder: String { loc("codereview.select_target_branch_placeholder") }
        static var selectModulePlaceholder: String { loc("codereview.select_module_placeholder") }
        static var searchBranchPlaceholder: String { loc("codereview.search_branch_placeholder") }
        static var searchModulePlaceholder: String { loc("codereview.search_module_placeholder") }
        static var searchFindingsPlaceholder: String { loc("codereview.search_findings_placeholder") }
        static var swapBranches: String { loc("codereview.swap_branches") }
        static var quickFillPRBranches: String { loc("codereview.quick_fill_pr_branches") }
        static var currentBranchBadge: String { loc("codereview.current_branch_badge") }
        static var viewByPriority: String { loc("codereview.view_by_priority") }
        static var viewByFile: String { loc("codereview.view_by_file") }
        static var stopReview: String { loc("codereview.stop_review") }
        static var analyzingProgress: String { loc("codereview.analyzing_progress") }

        static func prDiffSummary(_ commits: Int, _ files: Int) -> String {
            String(format: loc("codereview.pr_diff_summary"), commits, files)
        }
        static func findingsTitle(_ count: Int) -> String {
            String(format: loc("codereview.findings_title"), count)
        }
        static func reviewCompletedProject(_ name: String, _ count: Int) -> String {
            String(format: loc("codereview.review_completed_project"), name, count)
        }
        static func reviewCompletedSnippet(_ count: Int) -> String {
            String(format: loc("codereview.review_completed_snippet"), count)
        }
    }

    enum UnitTest {
        static var title: String { loc("unittest.title") }
        static var subtitle: String { loc("unittest.subtitle") }
        static var frameworkPicker: String { loc("unittest.framework_picker") }
        static var loadSwift: String { loc("unittest.load_swift") }
        static var moduleNamePlaceholder: String { loc("unittest.module_name_placeholder") }
        static var buildPlan: String { loc("unittest.build_plan") }
        static var approveAndWrite: String { loc("unittest.approve_and_write") }
        static var previewTitle: String { loc("unittest.preview_title") }
        static var previewEmpty: String { loc("unittest.preview_empty") }
        static var runSectionTitle: String { loc("unittest.run_section_title") }
        static var projectPathPlaceholder: String { loc("unittest.project_path_placeholder") }
        static var detectSchemes: String { loc("unittest.detect_schemes") }
        static var schemePlaceholder: String { loc("unittest.scheme_placeholder") }
        static var destinationPlaceholder: String { loc("unittest.destination_placeholder") }
        static var runXcodebuildTest: String { loc("unittest.run_xcodebuild_test") }
        static var noFileLoaded: String { loc("unittest.no_file_loaded") }
        static var selectProjectToWrite: String { loc("unittest.select_project_to_write") }
        static var detectSchemesFailed: String { loc("unittest.detect_schemes_failed") }
        static var testsPassed: String { loc("unittest.tests_passed") }
        static var testsFailed: String { loc("unittest.tests_failed") }

        static func sourceFileTitle(_ fileName: String) -> String {
            String(format: loc("unittest.source_file_title"), fileName)
        }
        static func reviewPlanTitle(_ targetName: String) -> String {
            String(format: loc("unittest.review_plan_title"), targetName)
        }
        static func planReady(_ count: Int) -> String {
            String(format: loc("unittest.plan_ready"), count)
        }
        static func testFileWritten(_ fileName: String) -> String {
            String(format: loc("unittest.test_file_written"), fileName)
        }
        static func detectingSchemes(_ name: String) -> String {
            String(format: loc("unittest.detecting_schemes"), name)
        }
        static func schemesFound(_ count: Int) -> String {
            String(format: loc("unittest.schemes_found"), count)
        }
        static func runningTests(_ scheme: String) -> String {
            String(format: loc("unittest.running_tests"), scheme)
        }
    }

    enum Utilities {
        static var title: String { loc("utilities.title") }
        static var colorTokenTitle: String { loc("utilities.color_token_title") }
        static var tokenNamePlaceholder: String { loc("utilities.token_name_placeholder") }
        static var tokenHexPlaceholder: String { loc("utilities.token_hex_placeholder") }
        static var generate: String { loc("utilities.generate") }
        static var l10nTitle: String { loc("utilities.l10n_title") }
        static var l10nEmptyPrompt: String { loc("utilities.l10n_empty_prompt") }
        static var derivedDataTitle: String { loc("utilities.derived_data_title") }
        static var refreshSize: String { loc("utilities.refresh_size") }
        static var cleanDerivedData: String { loc("utilities.clean_derived_data") }

        static func missingLanguages(_ langs: String) -> String {
            String(format: loc("utilities.missing_languages"), langs)
        }
        static func derivedDataCount(_ count: Int) -> String {
            String(format: loc("utilities.derived_data_count"), count)
        }
        static func l10nScanCompleted(_ count: Int) -> String {
            String(format: loc("utilities.l10n_scan_completed"), count)
        }
        static func derivedDataCleaned(_ removed: Int) -> String {
            String(format: loc("utilities.derived_data_cleaned"), removed)
        }
    }

    enum MenuBar {
        static var darkMode: String { loc("menubar.dark_mode") }
        static var lightMode: String { loc("menubar.light_mode") }
        static var cleanBar: String { loc("menubar.clean_bar") }

        static func simCount(_ count: Int) -> String {
            String(format: loc("menubar.sim_count"), count)
        }
    }

    enum Background {
        static var themeTitle: String { loc("bg.theme_title") }
        static var workspaceBgTitle: String { loc("bg.workspace_bg_title") }
        static var chooseCustomImage: String { loc("bg.choose_custom_image") }
        static var scrimOpacity: String { loc("bg.scrim_opacity") }
        static var blur: String { loc("bg.blur") }
        static var presetSolid: String { loc("bg.preset_solid") }
        static var presetCustom: String { loc("bg.preset_custom") }
        static var themeDark: String { loc("bg.theme_dark") }
        static var themeLight: String { loc("bg.theme_light") }
        static var themeMidnight: String { loc("bg.theme_midnight") }
    }

    enum Router {
        static var openProjectPrompt: String { loc("router.open_project_prompt") }
        static func selectProjectFirst(_ fileName: String) -> String {
            String(format: loc("router.select_project_first"), fileName)
        }
        static func fileNotFound(_ fileName: String, _ project: String) -> String {
            String(format: loc("router.file_not_found"), fileName, project)
        }
        static func openedInXcode(_ fileName: String, _ line: Int) -> String {
            String(format: loc("router.opened_in_xcode"), fileName, line)
        }
    }

    enum CrashlyticsExtra {
        static var exportMarkdown: String { loc("crashlytics.export_md") }
    }

    enum Enhancements {
        static var quickJump: String { loc("enh.quick_jump") }
        static var preferences: String { loc("enh.preferences") }
        static var exportMD: String { loc("enh.export_md") }
        static var scanHealthTrend: String { loc("enh.scan_health_trend") }
        static var liveConsole: String { loc("enh.live_console") }
        static var deepLinkPresets: String { loc("enh.deeplink_presets") }
        static var buildSigning: String { loc("enh.build_signing") }
        static var unusedAssets: String { loc("enh.unused_assets") }
        static var sandboxTitle: String { loc("enh.sandbox_title") }
        static var telemetryInterval: String { loc("enh.telemetry_interval") }
        static var intervalFast: String { loc("enh.interval_fast") }
        static var intervalBalanced: String { loc("enh.interval_balanced") }
        static var intervalLowPower: String { loc("enh.interval_low_power") }
        static var logBuffer: String { loc("enh.log_buffer") }
        static var language: String { loc("enh.language") }
        static var bgNotifications: String { loc("enh.bg_notifications") }
        static var notifyCrash: String { loc("enh.notify_crash") }
        static var notifyHang: String { loc("enh.notify_hang") }
        static var notifyTask: String { loc("enh.notify_task") }
        static var keyboardShortcuts: String { loc("enh.keyboard_shortcuts") }
        static var scPalette: String { loc("enh.sc_palette") }
        static var scModules: String { loc("enh.sc_modules") }
        static var scScan: String { loc("enh.sc_scan") }
        static var scHide: String { loc("enh.sc_hide") }
        static var scShortcuts: String { loc("enh.sc_shortcuts") }
        static var scQuit: String { loc("enh.sc_quit") }
        static var simLifecycle: String { loc("enh.sim_lifecycle") }
        static var recordVideo: String { loc("enh.record_video") }
        static var stopSaveVideo: String { loc("enh.stop_save_video") }
        static var shutdownSim: String { loc("enh.shutdown_sim") }
        static var bootSim: String { loc("enh.boot_sim") }
        static var locationSpoofer: String { loc("enh.location_spoofer") }
        static var privacyReset: String { loc("enh.privacy_reset") }
        static var pruneSims: String { loc("enh.prune_sims") }
        static var inspectBuilds: String { loc("enh.inspect_builds") }
        static var auditAssets: String { loc("enh.audit_assets") }
        static var crossFileDeps: String { loc("enh.cross_file_deps") }
        static var resolveDeps: String { loc("enh.resolve_deps") }
        static var coverageTitle: String { loc("enh.coverage_title") }
        static var coverageEmpty: String { loc("enh.coverage_empty") }
        static var coverageScope: String { loc("enh.coverage_scope") }
        static var coverageTarget: String { loc("enh.coverage_target") }
        static var checkCoverage: String { loc("enh.check_coverage") }
        static var checkingCoverage: String { loc("enh.checking_coverage") }
        static var chooseFile: String { loc("enh.choose_file") }
        static var chooseDirectory: String { loc("enh.choose_directory") }
        static var generateForUncovered: String { loc("enh.generate_for_uncovered") }
        static func coverageScopeLabel(_ kind: CoverageScopeKind) -> String {
            switch kind {
            case .none: loc("enh.scope_none")
            case .file: loc("enh.scope_file")
            case .directory: loc("enh.scope_directory")
            case .project: loc("enh.scope_project")
            }
        }
    }
}

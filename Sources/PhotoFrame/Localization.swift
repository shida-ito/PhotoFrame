import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable, Codable {
    case english
    case japanese

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english: return "English"
        case .japanese: return "日本語"
        }
    }
}

enum L10n {
    private static let tagTokens = "{Camera}, {Lens}, {Focal}, {FStop}, {Shutter}, {ISO}, {Date}, {Year}, {Month}, {Day}"

    static func clear(_ language: AppLanguage) -> String { language == .japanese ? "クリア" : "Clear" }
    static func clearPhotos(_ language: AppLanguage) -> String { language == .japanese ? "写真をクリア" : "Clear Photos" }
    static func undoClear(_ language: AppLanguage) -> String { language == .japanese ? "元に戻す" : "Undo Clear" }
    static func dropJPEGFilesHere(_ language: AppLanguage) -> String { language == .japanese ? "写真または動画をここにドロップ" : "Drop photos or videos here" }
    static func photoCount(_ count: Int, _ language: AppLanguage) -> String { language == .japanese ? "\(count) 件" : "\(count) item(s)" }
    static func groupName(_ language: AppLanguage) -> String { language == .japanese ? "グループ名" : "Group Name" }
    static func addGroup(_ language: AppLanguage) -> String { language == .japanese ? "グループを追加" : "Add Group" }
    static func addPhotos(_ language: AppLanguage) -> String { language == .japanese ? "写真 / 動画を追加" : "Add Media" }
    static func newGroupTitle(_ language: AppLanguage) -> String { language == .japanese ? "グループを追加" : "New Group" }
    static func newGroupMessage(_ language: AppLanguage) -> String { language == .japanese ? "同じ設定をまとめたい写真用のグループ名を入力してください。" : "Enter a name for the photo group." }
    static func renameGroupTitle(_ language: AppLanguage) -> String { language == .japanese ? "グループ名を変更" : "Rename Group" }
    static func renameGroupMessage(_ language: AppLanguage) -> String { language == .japanese ? "グループ名を変更します。" : "Update the group name." }
    static func renameGroupMenu(_ language: AppLanguage) -> String { language == .japanese ? "名前を変更..." : "Rename Group..." }
    static func renameGroupAction(_ language: AppLanguage) -> String { language == .japanese ? "名前変更" : "Rename Group" }
    static func deleteGroup(_ language: AppLanguage) -> String { language == .japanese ? "グループを削除" : "Delete Group" }
    static func exportGroupSettings(_ language: AppLanguage) -> String { language == .japanese ? "Group設定を書き出す..." : "Export Group Settings..." }
    static func importGroupSettings(_ language: AppLanguage) -> String { language == .japanese ? "Group設定を読み込む..." : "Import Group Settings..." }
    static func groupSettingsMenu(_ language: AppLanguage) -> String { language == .japanese ? "Group設定" : "Group Settings" }
    static func exportAllGroupSettings(_ language: AppLanguage) -> String { language == .japanese ? "全てのGroup設定を書き出す..." : "Export All Group Settings..." }
    static func importAllGroupSettings(_ language: AppLanguage) -> String { language == .japanese ? "全てのGroup設定を読み込む..." : "Import All Group Settings..." }
    static func groupSettingsImportFailed(_ language: AppLanguage) -> String { language == .japanese ? "Group設定の読み込みに失敗しました" : "Failed to import group settings" }
    static func groupSettingsExportFailed(_ language: AppLanguage) -> String { language == .japanese ? "Group設定の書き出しに失敗しました" : "Failed to export group settings" }
    static func invalidGroupSettingsFile(_ language: AppLanguage) -> String { language == .japanese ? "有効な PhotoFrame Group設定 JSON ではありません。" : "The selected file is not a valid PhotoFrame group settings JSON." }
    static func deleteSelectedPhotos(_ language: AppLanguage) -> String { language == .japanese ? "選択を削除" : "Delete Selected" }
    static func moveToGroup(_ language: AppLanguage) -> String { language == .japanese ? "グループへ移動" : "Move to Group" }
    static func processSelected(_ count: Int, _ language: AppLanguage) -> String { language == .japanese ? "選択を書き出し (\(count))" : "Export Sel (\(count))" }
    static func processing(_ language: AppLanguage) -> String { language == .japanese ? "書き出し中…" : "Exporting…" }
    static func processAll(_ language: AppLanguage) -> String { language == .japanese ? "すべて書き出し" : "Export All" }
    static func exportCurrentGroup(_ count: Int, _ language: AppLanguage) -> String { language == .japanese ? "現在のGroupを書き出し (\(count))" : "Export Current Group (\(count))" }
    static func exportAllGroups(_ language: AppLanguage) -> String { language == .japanese ? "すべてのGroupを書き出し" : "Export All Groups" }
    static func exportSettingsTitle(_ language: AppLanguage) -> String { language == .japanese ? "書き出し設定" : "Export Settings" }
    static func exportFormat(_ language: AppLanguage) -> String { language == .japanese ? "形式" : "Format" }
    static func exportSize(_ language: AppLanguage) -> String { language == .japanese ? "画像サイズ" : "Image Size" }
    static func slideshowSecondsPerPhoto(_ language: AppLanguage) -> String { language == .japanese ? "1枚あたりの秒数" : "Seconds Per Photo" }
    static func slideshowAudio(_ language: AppLanguage) -> String { language == .japanese ? "サウンド" : "Sound" }
    static func chooseAudio(_ language: AppLanguage) -> String { language == .japanese ? "音声を選択..." : "Choose Audio..." }
    static func clearAudio(_ language: AppLanguage) -> String { language == .japanese ? "音声を外す" : "Remove Audio" }
    static func noAudioSelected(_ language: AppLanguage) -> String { language == .japanese ? "音声未選択" : "No audio selected" }
    static func fadeIn(_ language: AppLanguage) -> String { language == .japanese ? "フェードイン" : "Fade In" }
    static func fadeOut(_ language: AppLanguage) -> String { language == .japanese ? "フェードアウト" : "Fade Out" }
    static func fadeDuration(_ language: AppLanguage) -> String { language == .japanese ? "フェード秒数" : "Fade Duration" }
    static func customLongEdge(_ language: AppLanguage) -> String { language == .japanese ? "カスタム長辺(px)" : "Custom Long Edge (px)" }
    static func jpegQuality(_ language: AppLanguage) -> String { language == .japanese ? "JPEG 品質" : "JPEG Quality" }
    static func filenamePrefix(_ language: AppLanguage) -> String { language == .japanese ? "ファイル名プレフィックス" : "Filename Prefix" }
    static func copyMetadata(_ language: AppLanguage) -> String { language == .japanese ? "EXIF / メタデータを引き継ぐ" : "Copy EXIF / metadata" }
    static func exportDestination(_ language: AppLanguage) -> String { language == .japanese ? "書き出し先フォルダを選択します。" : "Choose an output folder after confirming these settings." }
    static func exportAction(_ language: AppLanguage) -> String { language == .japanese ? "書き出し" : "Export" }
    static func videoExportNote(_ language: AppLanguage) -> String { language == .japanese ? "動画は MOV で書き出します。サイズ設定は動画にも適用され、音声があれば保持します。" : "Videos export as MOV. Size settings also apply to video, and audio is preserved when present." }
    static func slideshowExportNote(_ language: AppLanguage) -> String { language == .japanese ? "MOV で書き出します。選択書き出しは選択中の写真をグループごとに1本へ、すべて書き出しは各グループを1本の動画にまとめます。" : "Exports as MOV. Selected export creates one video per group from the selected photos, and Export All creates one video per group." }
    static func preview(_ language: AppLanguage) -> String { language == .japanese ? "プレビュー" : "Preview" }
    static func selectPhotoToPreview(_ language: AppLanguage) -> String { language == .japanese ? "写真または動画を選択するとプレビューを表示します" : "Select a photo or video to preview" }
    static func previewModePhoto(_ language: AppLanguage) -> String { language == .japanese ? "写真" : "Photo" }
    static func previewModeSlideshow(_ language: AppLanguage) -> String { language == .japanese ? "スライドショー" : "Slideshow" }
    static func slideshowPreviewNeedsPhotos(_ language: AppLanguage) -> String { language == .japanese ? "スライドショープレビューには同じグループに1枚以上の写真が必要です" : "Slideshow preview needs at least one photo in the group" }
    static func slideshowPreviewAudioUsesExport(_ language: AppLanguage) -> String { language == .japanese ? "ここで選んだ音声と秒数は動画書き出しにも使います。" : "The audio and timing selected here are also used for video export." }
    static func preparingSlideshowPreview(_ language: AppLanguage) -> String { language == .japanese ? "スライドショーを準備中…" : "Preparing slideshow preview…" }
    static func fullscreenPreview(_ language: AppLanguage) -> String { language == .japanese ? "全画面プレビュー" : "Fullscreen Preview" }
    static func closeFullscreenPreview(_ language: AppLanguage) -> String { language == .japanese ? "全画面を閉じる" : "Close Fullscreen" }
    static func fullscreenSlideshowSettings(_ language: AppLanguage) -> String { language == .japanese ? "全画面スライドショー" : "Fullscreen Slideshow" }
    static func autoAdvanceGroups(_ language: AppLanguage) -> String { language == .japanese ? "終了後に次のGroupへ進む" : "Advance To Next Group After Playback" }
    static func preparingNextGroup(_ language: AppLanguage) -> String { language == .japanese ? "次のGroupを準備中…" : "Preparing next group…" }
    static func workspaceRecoveryTitle(_ language: AppLanguage) -> String { language == .japanese ? "ワークスペース復元" : "Workspace Recovery" }
    static func workspacePrimaryRestoreFailed(_ language: AppLanguage) -> String { language == .japanese ? "現在のワークスペース保存データを読めなかったため、バックアップから復元しました。" : "The current workspace data could not be read, so the app restored from backup." }
    static func workspaceRestoreFailedNoBackup(_ language: AppLanguage) -> String { language == .japanese ? "ワークスペース保存データを復元できず、利用可能なバックアップもありません。このセッションでは自動保存を停止して、これ以上の上書きを防ぎます。" : "The workspace data could not be restored and no backup is available. Auto-save is disabled for this session to prevent overwriting more data." }
    static func workspaceAutoSavePaused(_ language: AppLanguage) -> String { language == .japanese ? "ワークスペース保護のため、このセッションでは自動保存を停止しています。" : "Auto-save is paused for this session to protect the workspace data." }
    static func settings(_ language: AppLanguage) -> String { language == .japanese ? "設定" : "Settings" }
    static func editingGroup(_ groupName: String, _ language: AppLanguage) -> String { language == .japanese ? "編集中のグループ: \(groupName)" : "Editing Group: \(groupName)" }
    static func frameWidth(_ language: AppLanguage) -> String { language == .japanese ? "フレーム幅" : "Frame Width" }
    static func previewQuality(_ language: AppLanguage) -> String { language == .japanese ? "プレビュー品質" : "Preview Quality" }
    static func previewFast(_ language: AppLanguage) -> String { language == .japanese ? "高速 (400px)" : "Fast (400px)" }
    static func previewStandard(_ language: AppLanguage) -> String { language == .japanese ? "標準 (600px)" : "Standard (600px)" }
    static func previewHigh(_ language: AppLanguage) -> String { language == .japanese ? "高品質 (1000px)" : "High (1000px)" }
    static func previewUltra(_ language: AppLanguage) -> String { language == .japanese ? "最高品質 (1600px)" : "Ultra (1600px)" }
    static func preview2K(_ language: AppLanguage) -> String { language == .japanese ? "2K (2048px)" : "2K (2048px)" }
    static func preview4K(_ language: AppLanguage) -> String { language == .japanese ? "4K (3840px)" : "4K (3840px)" }
    static func savePresetTitle(_ language: AppLanguage) -> String { language == .japanese ? "プリセットを保存" : "Save Preset" }
    static func renamePresetTitle(_ language: AppLanguage) -> String { language == .japanese ? "プリセット名を変更" : "Rename Preset" }
    static func presetName(_ language: AppLanguage) -> String { language == .japanese ? "プリセット名" : "Preset Name" }
    static func save(_ language: AppLanguage) -> String { language == .japanese ? "保存" : "Save" }
    static func ok(_ language: AppLanguage) -> String { language == .japanese ? "OK" : "OK" }
    static func cancel(_ language: AppLanguage) -> String { language == .japanese ? "キャンセル" : "Cancel" }
    static func rename(_ language: AppLanguage) -> String { language == .japanese ? "変更" : "Rename" }
    static func savePresetMessage(_ language: AppLanguage) -> String { language == .japanese ? "現在のレイアウト名を入力してください。" : "Enter a name for your custom layout." }
    static func renamePresetMessage(_ language: AppLanguage) -> String { language == .japanese ? "プリセット名を変更します。" : "Update the preset name." }
    static func aspectRatio(_ language: AppLanguage) -> String { language == .japanese ? "アスペクト比" : "Aspect Ratio" }
    static func photoPosition(_ language: AppLanguage) -> String { language == .japanese ? "写真位置" : "Photo Position" }
    static func vertical(_ language: AppLanguage) -> String { language == .japanese ? "上下" : "Vertical" }
    static func horizontal(_ language: AppLanguage) -> String { language == .japanese ? "左右" : "Horizontal" }
    static func frameStyle(_ language: AppLanguage) -> String { language == .japanese ? "フレームスタイル" : "Frame Style" }
    static func color(_ language: AppLanguage) -> String { language == .japanese ? "色" : "Color" }
    static func photoBorder(_ language: AppLanguage) -> String { language == .japanese ? "写真枠を表示" : "Show Photo Border" }
    static func borderColor(_ language: AppLanguage) -> String { language == .japanese ? "枠色" : "Border Color" }
    static func borderWidth(_ language: AppLanguage) -> String { language == .japanese ? "枠幅 (%)" : "Border Width (%)" }
    static func textLayers(_ language: AppLanguage) -> String { language == .japanese ? "テキストレイヤー" : "Text Layers" }
    static func addLayer(_ language: AppLanguage) -> String { language == .japanese ? "レイヤーを追加" : "Add Layer" }
    static func tags(_ language: AppLanguage) -> String { language == .japanese ? "タグ: \(tagTokens)" : "Tags: \(tagTokens)" }
    static func photoExifTags(_ language: AppLanguage) -> String { language == .japanese ? "現在の写真で使えるタグ" : "Tags In Current Photo" }
    static func dynamicTagHint(_ language: AppLanguage) -> String { language == .japanese ? "下の一覧にあるタグ名は `{TagName}` 形式でそのまま使えます。" : "Use any tag below directly as `{TagName}`." }
    static func textTemplate(_ language: AppLanguage) -> String { language == .japanese ? "テキストテンプレート" : "Text Template" }
    static func textSize(_ language: AppLanguage) -> String { language == .japanese ? "文字サイズ" : "Text Size" }
    static func textPosition(_ language: AppLanguage) -> String { language == .japanese ? "位置 (X / Y)" : "Position (X / Y)" }
    static func align(_ language: AppLanguage) -> String { language == .japanese ? "揃え" : "Align" }
    static func removeLayer(_ language: AppLanguage) -> String { language == .japanese ? "レイヤーを削除" : "Remove Layer" }
    static func emptyLayer(_ language: AppLanguage) -> String { language == .japanese ? "空のレイヤー" : "Empty Layer" }
    static func font(_ language: AppLanguage) -> String { language == .japanese ? "フォント" : "Font" }
    static func fontFamily(_ language: AppLanguage) -> String { language == .japanese ? "フォントファミリー" : "Font Family" }
    static func fontFace(_ language: AppLanguage) -> String { language == .japanese ? "フォントフェイス" : "Font Face" }
    static func searchFonts(_ language: AppLanguage) -> String { language == .japanese ? "フォントを検索" : "Search fonts" }
    static func noFontsFound(_ language: AppLanguage) -> String { language == .japanese ? "該当するフォントがありません" : "No fonts found" }
    static func savedPresets(_ language: AppLanguage) -> String { language == .japanese ? "保存済みプリセット" : "Saved Presets" }
    static func applySelection(_ language: AppLanguage) -> String { language == .japanese ? "適用" : "Apply Selection" }
    static func managePresets(_ language: AppLanguage) -> String { language == .japanese ? "プリセット管理" : "Manage Presets" }
    static func overwritePreset(_ language: AppLanguage) -> String { language == .japanese ? "現在の設定で上書き" : "Overwrite with Current Settings" }
    static func importPresets(_ language: AppLanguage) -> String { language == .japanese ? "プリセットを読み込む..." : "Import Presets..." }
    static func pastePresetText(_ language: AppLanguage) -> String { language == .japanese ? "プリセット文字列を貼り付け..." : "Paste Preset Text..." }
    static func exportPreset(_ language: AppLanguage) -> String { language == .japanese ? "プリセットを書き出す..." : "Export Preset..." }
    static func exportAllPresets(_ language: AppLanguage) -> String { language == .japanese ? "すべてのプリセットを書き出す..." : "Export All Presets..." }
    static func renamePresetMenu(_ language: AppLanguage) -> String { language == .japanese ? "名前を変更..." : "Rename Preset..." }
    static func deletePreset(_ language: AppLanguage) -> String { language == .japanese ? "プリセットを削除" : "Delete Preset" }
    static func saveCurrentAsPreset(_ language: AppLanguage) -> String { language == .japanese ? "現在の設定をプリセット保存..." : "Save Current as Preset..." }
    static func clearAllPresets(_ language: AppLanguage) -> String { language == .japanese ? "すべてのプリセットを削除" : "Clear All Presets" }
    static func presetImportFailed(_ language: AppLanguage) -> String { language == .japanese ? "プリセットの読み込みに失敗しました" : "Preset Import Failed" }
    static func presetExportFailed(_ language: AppLanguage) -> String { language == .japanese ? "プリセットの書き出しに失敗しました" : "Preset Export Failed" }
    static func invalidPresetFile(_ language: AppLanguage) -> String { language == .japanese ? "有効な PhotoFrame プリセット JSON ではありません。" : "The selected file is not a valid PhotoFrame preset JSON." }
    static func pastePresetTitle(_ language: AppLanguage) -> String { language == .japanese ? "プリセット文字列を貼り付け" : "Paste Preset Text" }
    static func pastePresetMessage(_ language: AppLanguage) -> String { language == .japanese ? "PhotoFrame の preset JSON を貼り付けて読み込みます。" : "Paste PhotoFrame preset JSON to import it." }
    static func presetJSONPlaceholder(_ language: AppLanguage) -> String { language == .japanese ? "ここに preset JSON を貼り付け" : "Paste preset JSON here" }
    static func importPresetTextAction(_ language: AppLanguage) -> String { language == .japanese ? "読み込む" : "Import Text" }
    static func interface(_ language: AppLanguage) -> String { language == .japanese ? "表示" : "Interface" }
    static func displayLanguage(_ language: AppLanguage) -> String { language == .japanese ? "表示言語" : "Display Language" }
    static func colorMode(_ language: AppLanguage) -> String { language == .japanese ? "カラーモード" : "Color Mode" }
    static func fontPickerMode(_ language: AppLanguage) -> String { language == .japanese ? "フォント選択表示" : "Font Picker Mode" }
    static func fullListWarning(_ language: AppLanguage) -> String { language == .japanese ? "一覧表示モードでは、テキスト編集中の動作が少し重くなる場合があります。" : "Full List mode may make text-layer editing a bit heavier." }
    static func presets(_ language: AppLanguage) -> String { language == .japanese ? "プリセット" : "Presets" }
    static func noPresetsSaved(_ language: AppLanguage) -> String { language == .japanese ? "保存済みプリセットはありません" : "No presets saved" }
    static func presetHoverPreview(_ language: AppLanguage) -> String { language == .japanese ? "マウスオーバーでプレビュー、クリックで適用します。" : "Hover to preview, click to apply." }
}

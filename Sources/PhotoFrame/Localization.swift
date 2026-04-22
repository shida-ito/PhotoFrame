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
    private static let tagTokens = "{Camera}, {Lens}, {Focal}, {FStop}, {Shutter}, {ISO}, {Date}"

    static func clear(_ language: AppLanguage) -> String { language == .japanese ? "クリア" : "Clear" }
    static func clearPhotos(_ language: AppLanguage) -> String { language == .japanese ? "写真をクリア" : "Clear Photos" }
    static func undoClear(_ language: AppLanguage) -> String { language == .japanese ? "元に戻す" : "Undo Clear" }
    static func dropJPEGFilesHere(_ language: AppLanguage) -> String { language == .japanese ? "JPEG ファイルをここにドロップ" : "Drop JPEG files here" }
    static func photoCount(_ count: Int, _ language: AppLanguage) -> String { language == .japanese ? "\(count) 枚" : "\(count) photo(s)" }
    static func groupName(_ language: AppLanguage) -> String { language == .japanese ? "グループ名" : "Group Name" }
    static func addGroup(_ language: AppLanguage) -> String { language == .japanese ? "グループを追加" : "Add Group" }
    static func addPhotos(_ language: AppLanguage) -> String { language == .japanese ? "写真を追加" : "Add Photos" }
    static func newGroupTitle(_ language: AppLanguage) -> String { language == .japanese ? "グループを追加" : "New Group" }
    static func newGroupMessage(_ language: AppLanguage) -> String { language == .japanese ? "同じ設定をまとめたい写真用のグループ名を入力してください。" : "Enter a name for the photo group." }
    static func renameGroupTitle(_ language: AppLanguage) -> String { language == .japanese ? "グループ名を変更" : "Rename Group" }
    static func renameGroupMessage(_ language: AppLanguage) -> String { language == .japanese ? "グループ名を変更します。" : "Update the group name." }
    static func renameGroupMenu(_ language: AppLanguage) -> String { language == .japanese ? "名前を変更..." : "Rename Group..." }
    static func renameGroupAction(_ language: AppLanguage) -> String { language == .japanese ? "名前変更" : "Rename Group" }
    static func deleteGroup(_ language: AppLanguage) -> String { language == .japanese ? "グループを削除" : "Delete Group" }
    static func moveToGroup(_ language: AppLanguage) -> String { language == .japanese ? "グループへ移動" : "Move to Group" }
    static func processSelected(_ count: Int, _ language: AppLanguage) -> String { language == .japanese ? "選択を処理 (\(count))" : "Process Sel (\(count))" }
    static func processing(_ language: AppLanguage) -> String { language == .japanese ? "処理中…" : "Processing…" }
    static func processAll(_ language: AppLanguage) -> String { language == .japanese ? "すべて処理" : "Process All" }
    static func preview(_ language: AppLanguage) -> String { language == .japanese ? "プレビュー" : "Preview" }
    static func selectPhotoToPreview(_ language: AppLanguage) -> String { language == .japanese ? "写真を選択するとプレビューを表示します" : "Select a photo to preview" }
    static func settings(_ language: AppLanguage) -> String { language == .japanese ? "設定" : "Settings" }
    static func editingGroup(_ groupName: String, _ language: AppLanguage) -> String { language == .japanese ? "編集中のグループ: \(groupName)" : "Editing Group: \(groupName)" }
    static func frameWidth(_ language: AppLanguage) -> String { language == .japanese ? "フレーム幅" : "Frame Width" }
    static func previewQuality(_ language: AppLanguage) -> String { language == .japanese ? "プレビュー品質" : "Preview Quality" }
    static func previewFast(_ language: AppLanguage) -> String { language == .japanese ? "高速 (400px)" : "Fast (400px)" }
    static func previewStandard(_ language: AppLanguage) -> String { language == .japanese ? "標準 (600px)" : "Standard (600px)" }
    static func previewHigh(_ language: AppLanguage) -> String { language == .japanese ? "高品質 (1000px)" : "High (1000px)" }
    static func previewUltra(_ language: AppLanguage) -> String { language == .japanese ? "最高品質 (1600px)" : "Ultra (1600px)" }
    static func savePresetTitle(_ language: AppLanguage) -> String { language == .japanese ? "プリセットを保存" : "Save Preset" }
    static func renamePresetTitle(_ language: AppLanguage) -> String { language == .japanese ? "プリセット名を変更" : "Rename Preset" }
    static func presetName(_ language: AppLanguage) -> String { language == .japanese ? "プリセット名" : "Preset Name" }
    static func save(_ language: AppLanguage) -> String { language == .japanese ? "保存" : "Save" }
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
    static func textLayers(_ language: AppLanguage) -> String { language == .japanese ? "テキストレイヤー" : "Text Layers" }
    static func addLayer(_ language: AppLanguage) -> String { language == .japanese ? "レイヤーを追加" : "Add Layer" }
    static func tags(_ language: AppLanguage) -> String { language == .japanese ? "タグ: \(tagTokens)" : "Tags: \(tagTokens)" }
    static func textTemplate(_ language: AppLanguage) -> String { language == .japanese ? "テキストテンプレート" : "Text Template" }
    static func textSize(_ language: AppLanguage) -> String { language == .japanese ? "文字サイズ" : "Text Size" }
    static func textPosition(_ language: AppLanguage) -> String { language == .japanese ? "位置 (X / Y)" : "Position (X / Y)" }
    static func align(_ language: AppLanguage) -> String { language == .japanese ? "揃え" : "Align" }
    static func removeLayer(_ language: AppLanguage) -> String { language == .japanese ? "レイヤーを削除" : "Remove Layer" }
    static func emptyLayer(_ language: AppLanguage) -> String { language == .japanese ? "空のレイヤー" : "Empty Layer" }
    static func font(_ language: AppLanguage) -> String { language == .japanese ? "フォント" : "Font" }
    static func searchFonts(_ language: AppLanguage) -> String { language == .japanese ? "フォントを検索" : "Search fonts" }
    static func noFontsFound(_ language: AppLanguage) -> String { language == .japanese ? "該当するフォントがありません" : "No fonts found" }
    static func savedPresets(_ language: AppLanguage) -> String { language == .japanese ? "保存済みプリセット" : "Saved Presets" }
    static func applySelection(_ language: AppLanguage) -> String { language == .japanese ? "適用" : "Apply Selection" }
    static func renamePresetMenu(_ language: AppLanguage) -> String { language == .japanese ? "名前を変更..." : "Rename Preset..." }
    static func deletePreset(_ language: AppLanguage) -> String { language == .japanese ? "プリセットを削除" : "Delete Preset" }
    static func saveCurrentAsPreset(_ language: AppLanguage) -> String { language == .japanese ? "現在の設定をプリセット保存..." : "Save Current as Preset..." }
    static func clearAllPresets(_ language: AppLanguage) -> String { language == .japanese ? "すべてのプリセットを削除" : "Clear All Presets" }
    static func interface(_ language: AppLanguage) -> String { language == .japanese ? "表示" : "Interface" }
    static func displayLanguage(_ language: AppLanguage) -> String { language == .japanese ? "表示言語" : "Display Language" }
    static func fontPickerMode(_ language: AppLanguage) -> String { language == .japanese ? "フォント選択表示" : "Font Picker Mode" }
    static func fullListWarning(_ language: AppLanguage) -> String { language == .japanese ? "一覧表示モードでは、テキスト編集中の動作が少し重くなる場合があります。" : "Full List mode may make text-layer editing a bit heavier." }
}

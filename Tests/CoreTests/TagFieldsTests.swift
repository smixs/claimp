import Foundation
import Testing

@testable import Core

@Test("Темп из строкового тега: целое, с дробной частью и с пробелами")
func bpmParsesPlainAndFractional() {
    #expect(TagFields.bpm(from: "174") == 174)
    #expect(TagFields.bpm(from: "174.00") == 174)
    #expect(TagFields.bpm(from: " 128 ") == 128)
}

@Test("Мусор, ноль и запредельное значение темпа дают nil")
func bpmRejectsGarbage() {
    #expect(TagFields.bpm(from: "abc") == nil)
    #expect(TagFields.bpm(from: "") == nil)
    #expect(TagFields.bpm(from: nil) == nil)
    #expect(TagFields.bpm(from: "0") == nil)
    #expect(TagFields.bpm(from: "-5") == nil)
    #expect(TagFields.bpm(from: "1500") == nil)
}

@Test("Тональность берётся из тега любого контейнера: TKEY, INITIALKEY, ©key")
func musicalKeyFoundInAnyContainer() {
    #expect(TagFields.musicalKey(in: ["id3/TKEY": "8A"]) == "8A")
    #expect(TagFields.musicalKey(in: ["INITIALKEY": " Am "]) == "Am")
    #expect(TagFields.musicalKey(in: ["itsk/%A9key": "12B"]) == "12B")
}

@Test("Нет тега тональности или он пустой - nil, чужие теги не подходят")
func musicalKeyMissingGivesNil() {
    #expect(TagFields.musicalKey(in: [:]) == nil)
    #expect(TagFields.musicalKey(in: ["GENRE": "Techno", "KEYWORDS": "club"]) == nil)
    #expect(TagFields.musicalKey(in: ["TKEY": "   "]) == nil)
}

@Test("Темп в словаре тегов ищется по именам TBPM, BPM и tmpo")
func bpmFoundByTagNames() {
    #expect(TagFields.bpm(in: ["id3/TBPM": "140"]) == 140)
    #expect(TagFields.bpm(in: ["BPM": "92.5"]) == 92.5)
    #expect(TagFields.bpm(in: ["GENRE": "Techno"]) == nil)
}

@Test("Идентификатор колонки превращается в поле сортировки")
func columnKeyMapsToSortField() {
    #expect(TrackSortField.forColumnKey("bpm") == .bpm)
    #expect(TrackSortField.forColumnKey("bitrate") == .bitrate)
    #expect(TrackSortField.forColumnKey("key") == .key)
    #expect(TrackSortField.forColumnKey("artist") == .artist)
}

@Test("Чужой идентификатор колонки не даёт поля сортировки")
func unknownColumnKeyGivesNil() {
    #expect(TrackSortField.forColumnKey("genre") == nil)
    #expect(TrackSortField.forColumnKey("") == nil)
    #expect(TrackSortField.forColumnKey("Title") == nil)
}

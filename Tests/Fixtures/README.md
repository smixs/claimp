# Тестовые фикстуры

Синтетические файлы, сгенерированные локально для проекта. Чужой музыки, текстов и лицензионных
ограничений внутри нет: во всех
шести файлах один и тот же синус. MD5 приведены, чтобы поймать случайную правку бинарника.

`Tests/Fixtures/` не является таргетом SwiftPM - файлы в бандл не копируются, путь берётся
от исходника теста:

```swift
let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // Tests/CoreTests
    .deletingLastPathComponent()   // Tests
    .appending(path: "Fixtures")
```

Фикстуры только читаются: тесты не переписывают их (эталон - MD5 ниже).

## Что лежит внутри

| Файл | Формат | Теги | Длительность | Размер | MD5 |
|---|---|---|---|---|---|
| `id3v23.mp3` | MPEG-1 Layer III, ID3v2.3 | TIT2, TPE1, TALB, TYER, TDAT, APIC | 360.000 с | 14 403 210 | `038968f9773afe17f9cc88e8b2e45737` |
| `id3v24.mp3` | MPEG-1 Layer III, ID3v2.4 | TIT2, TPE1, TALB, TDRC, TDOR, APIC | 360.000 с | 14 403 216 | `b796204cc01bec5581a3033c52e34267` |
| `tagged.flac` | FLAC, 44.1 кГц / 16 бит / stereo | VORBIS_COMMENT + PICTURE | 5.000 с | 90 204 | `5836cca8d4248a8a0fa1b73dddd49b09` |
| `tagged.m4a` | MP4/M4A, AAC-LC, 44.1 кГц / stereo | ilst: title, artist, album, date | 5.014 с | 23 953 | `f6b53308d55f2ac7261f8cf52e6fd832` |
| `tone.wav` | WAVE, PCM s16le, 44.1 кГц / 16 бит / stereo | нет | 5.000 с | 882 044 | `672ba4d2ae48f7b1db1b2fb61c53dfed` |
| `tone.aiff` | AIFF, PCM s16be, 44.1 кГц / 16 бит / stereo | нет | 5.000 с | 886 096 | `dae3ae1ad28e44e1a244f333ec074dec` |

## Пофайлово

**`id3v23.mp3`** - CBR 320 kbps, 44.1 кГц, stereo, 6 минут. Контейнер ID3v2.3 (в заголовке
`ID3 03 00`, размер тега 584 байта) плюс кадр-заголовок `Info`; первый звуковой кадр с 0x152.
Кадры тега: `TIT2` = «Test Title 23», `TPE1` = «Test Artist», `TALB` = «Test Album»,
`TYER` = «1994», `TDAT` = «1503» (то есть 15 марта), `APIC` - обложка-заглушка.

**`id3v24.mp3`** - тот же звук (CBR 320 kbps, 6 минут), контейнер ID3v2.4 (`ID3 04 00`,
размер тега 590 байт), первый звуковой кадр с 0x158. Кадры: `TIT2` = «Test Title 24»,
`TPE1` = «Test Artist», `TALB` = «Test Album», `TDRC` = «1994-03-15», `TDOR` = «1991»
(год оригинального релиза), `APIC` - обложка-заглушка.

**`tagged.flac`** - FLAC 44.1 кГц / 16 бит / stereo, 220 500 кадров. Блок `VORBIS_COMMENT`
(vendor = `probe`): `TITLE` = «FLAC Test Title», `ARTIST` = «FLAC Artist», `ALBUM` = «FLAC Album»,
`DATE` = «1994-03-15», `ORIGINALDATE` = «1991», `RATING` = «80». Блок `PICTURE`: тип 3
(передняя обложка), MIME `image/png`, описание `cover`, картинка-заглушка.

**`tagged.m4a`** - MP4/M4A, AAC-LC 44.1 кГц stereo, 5.014 с (лишние 14 мс - паддинг AAC).
Теги в `ilst`: `title` = «M4A Title», `artist` = «M4A Artist», `album` = «M4A Album»,
`date` = «1994-03-15», `encoder` = `Lavf62.3.100`. Обложки нет: атома `covr` в файле не
существует - этим он и отличается от остальных тегированных фикстур.

**`tone.wav`** - WAVE, PCM signed 16-bit little-endian, 44.1 кГц stereo, ровно 5.000 с
(220 500 кадров), тегов нет вообще.

**`tone.aiff`** - AIFF, PCM signed 16-bit big-endian, 44.1 кГц stereo, ровно 5.000 с
(220 500 кадров), тегов нет вообще.

## Звук

Во всех шести файлах - синус 440 Гц: замер по переходам через ноль даёт 439.9 Гц, пик
11 999/32 768 = 0.366 от шкалы, RMS −11.74 dBFS. У `tagged.m4a` из-за AAC те же 440 Гц, но
пик 12 316 и длина 5.014 с. То есть для анализа волны годится любой файл: уровень и частота
у всех одинаковые, отличается только длина (5 с против 360 с) и формат контейнера.

## Годы (на что опираются тесты T1)

- 1994 - `id3v23.mp3` (TYER 1994 + TDAT 1503), `id3v24.mp3` (TDRC 1994-03-15),
  `tagged.flac` (DATE 1994-03-15), `tagged.m4a` (©day 1994-03-15);
- 1991 - год оригинала у `id3v24.mp3` (TDOR) и `tagged.flac` (ORIGINALDATE): в колонку «Год»
  он попадать не должен, поэтому эти два файла - проверка, что берётся дата, а не оригинал;
- `tone.wav` и `tone.aiff` - тегов нет, значит `year == nil` и `displayYear == ""`.

## Обложки - заглушки, а не картинки

В `id3v23.mp3`, `id3v24.mp3` (кадр `APIC`) и `tagged.flac` (блок `PICTURE`) лежит один и тот же
PNG-заглушка размером 75 байт: сигнатура и `IHDR` корректны (заявлено 1×1 RGBA), но поток `IDAT`
неполный - распаковывается 2 байта вместо 5, - и контрольные суммы (Adler-32, CRC `IDAT`) неверны.
Декодеры на ней спотыкаются: `ffprobe` пишет `inflate returned error -3`, `NSImage(data:)`
вернёт nil.

Практический вывод для тестов: проверять **наличие** обложки можно (`artwork != nil`, первые байты
`\x89PNG\r\n\x1a\n`), **декодировать и рисовать** её нельзя - для картинок нужна своя фикстура.
Заодно это повод не делать `artwork` обязательным полем: у `tagged.m4a`, `tone.wav` и `tone.aiff`
обложки нет вовсе.

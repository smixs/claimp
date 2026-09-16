# 08. Колонки плейлиста: готовый образец и рецепт переноса

Дата: 2026-09-16, 09:35-10:10 (по `date`). Продолжение `research/07-table-columns-behaviour.md`.
Источники: исходники четырёх клонов в `research/raw/`, поиск по коду GitHub (`gh api search/code`),
заголовки SDK `MacOSX27.sdk`, собственные замеры на живом AppKit
(`research/raw/probe/probe8.swift`, `probe8b.swift`, `probe8c.swift`; логи
`research/raw/probe/probe-08-recipe.log`, `probe-08-edges.log`, `probe-08-frame-step.log`;
сборка `DEVELOPER_DIR=/Library/Developer/CommandLineTools swiftc -O`).

Правила отчёта: каждое утверждение с опорой (`file:line` или строка лога). Где опоры нет -
написано «не установлено». В `Sources/` ничего не менялось.

---

## 0. Главный вывод в одну строку

**Открытого проекта, который делает ровно то, что требует владелец, нет.** Ни Aural, ни Cog,
ни Bòcan, ни IINA не компенсируют протяжку разделителя: у Aural и Cog обработчик
`tableViewColumnDidResize` существует, но только сохраняет состояние колонок
(`aural-player/Source/UI/PlayQueue/TabularView/PlayQueueTabularViewController+TableViewDelegate.swift:139-143`,
`Cog/Playlist/PlaylistView.m:174`, `:215`). Зато у Aural есть **готовый механизм**, который
закрывает все три требования владельца, если позвать его из одного места больше, чем зовёт Aural:
`tableView.sizeToFit()`. Замер подтверждает (см. §4) - это штатный AppKit, наша
`ColumnWidthBalancer` не нужна.

---

## 1. Кандидаты-образцы

### 1.1 Сводная таблица

| | Aural Player | Cog | Bòcan | IINA (History) |
|---|---|---|---|---|
| стиль autoresizing | атрибут в xib не задан = дефолт класса `lastColumnOnly` (`PlayQueueTabularView.xib:33`; `NSTableView.h:170`) | не задан (`Cog/Base.lproj/MainMenu.xib:34`) | `.lastColumnOnlyAutoresizingStyle` (`TrackTable.swift:125`) | `.firstColumnOnlyAutoresizingStyle` (`HistoryWindowController.swift:111`) |
| `resizingMask` колонок | у всех `resizeWithTable="YES" userResizable="YES"` (`xib:50,101,...`) | не установлено (в xib не задан → дефолт `3`, обе маски) | не установлено, задаются только min/ideal/max (`TrackTable+ColSpecs.swift`) | не задаётся (дефолт = обе маски) |
| min/max | текст `150..10000`, числа узко: `Duration 60..80`, `Year 60..80` (`xib:130,410,250`) | текст `96..1024`, `length 43..96`, `date 42..96` (`MainMenu.xib`) | `title 140/220/2000`, `bpm 40/52/72`, `key 40/56/80` (`TrackTable+ColSpecs.swift:45-49,216-231`) | `filename 200..5000`, `progress 110..1000`, `time 60..300` (`HistoryWindowController.swift:117-119`) |
| своя компенсация в `columnDidResize` | **нет**, только `saveColumnsState()` (`+TableViewDelegate.swift:139-143`) | **нет**, только `syncColumnState` по таймеру (`PlaylistView.m:215`, `:192-201`) | **нет** (`grep columnDidResize` по репо пусто) | **нет** уведомления; есть ручной `donateColWidth` при смене `minWidth` (`HistoryWindowController.swift:178-187`) |
| `sizeToFit` / `sizeLastColumnToFit` | **`sizeToFit()` в двух местах**: при восстановлении набора колонок (`PlayQueueTabularViewController.swift:57`) и при показе/скрытии колонки (`:110`) | `sizeToFit` только у текстового поля мини-плеера (`MiniPlayerPlusWindowController.m:237`), к таблице не относится | нет | нет; вместо него `layoutSubtreeIfNeeded()` после ручной раздачи (`:185`) |
| autosave | выключен (`xib:33`, `autosaveColumns="NO"`), состояние пишут сами (`:83-92`) | `autosaveName="Playlist"` (`MainMenu.xib:34`) плюс своя копия в `UserDefaults` (`PlaylistView.m:192-201`) | `autosaveTableColumns` после добавления колонок, потом `autosaveName` (`TrackTable.swift:141-156`); видимость хранят сами (`TrackTable+Helpers.swift:77-78`) | `autosaveName = "HistoryWindowTable"` (`:113`) |
| горизонтальный скролл | не установлено (в xib скроллвью не проверял построчно) | **нет** (`MainMenu.xib:27`, `hasHorizontalScroller="NO"`) | **да**, `hasHorizontalScroller = true`, `autohidesScrollers = true` (`TrackTable.swift:178-186`) | **нет** (`HistoryWindowController.swift:103`) |
| выравнивание чисел | заголовок слева, ячейка **справа** + отступ 8 pt (`xib:411,432,440`) | в xib числовые заголовки `alignment="right"` (`MainMenu.xib:391,435`); что рисует view-based ячейка - не установлено | **всё влево**, `NSTextField(labelWithString:)` без `alignment`, отступы 4/-4 (`TrackTableCoordinator.swift:108-122`) | не установлено |
| обрезка длинного текста | `lineBreakMode="truncatingTail"` в ячейке (`xib:432`) | не установлено | `lineBreakMode = .byTruncatingTail` + `truncatesLastVisibleLine = true` (`TrackTableCoordinator.swift:113-114`) | не установлено |
| своя маска/градиент | **нет ни у кого из четырёх** (`grep -rn "CAGradientLayer" research/raw` по плейлистам пусто) | нет | нет | нет |
| где живёт header | своя `NSTableHeaderCell` (`PlayQueueTabularViewTableHeaderCell.swift:15-22`) | своя `NSTableHeaderView` только ради `mouseDown` (`PlaylistHeaderView.m:13-31`) | штатный | штатный |

### 1.2 Дополнительные проекты (поиск по коду GitHub, 16.09)

`gh api search/code q='sizeLastColumnToFit language:Swift'` и `q='columnAutoresizingStyle language:Swift'`
дали 35 файлов. Отсмотрены на предмет «многоколоночная таблица, которую тянет пользователь»:

- `Automattic/simplenote-macos` → `Simplenote/TagListViewController+Swift.swift:20-21`:
  `tableView.ensureStyleIsFullWidth(); tableView.sizeLastColumnToFit()` - таблица **одноколоночная**
  (список тегов). Как образец **бесполезен**, но подтверждает идиому «после сборки один раз
  подогнать под ширину».
- `ProfileCreator/ProfileCreator` → `.../PayloadCellViewItemTableView.swift:21,30`:
  `allowsColumnReordering = false`, `sizeLastColumnToFit()` при сборке, `intercellSpacing = .zero`.
  Таблица внутри ячейки редактора, колонки пользователь не тянет. **Не подходит**.
- `iina/iina` (`SettingsPageAdvanced.swift`, `LogWindowController.swift`), `Lona/Lona`
  (`CanvasTableView.swift`, `ListEditor.swift`), `tw93/MiaoYan`, `gnachman/iTerm2`,
  `exelban/stats` - во всех `columnAutoresizingStyle` ставится на служебных таблицах логов и
  настроек с 1-2 колонками. Пользовательской протяжки девяти колонок там нет. **Не подходят.**
- Torrent/download-менеджеров и RSS-читалок на Swift/AppKit с настраиваемыми колонками в выдаче
  **не нашлось**; Transmission и Deluge-GUI - ObjC/GTK, в поиск по `language:Swift` не попадают.

Вывод: за пределами четырёх уже разобранных плееров нового образца нет. **Не установлено**, что
где-то в открытом коде есть готовая реализация «протяжка компенсируется соседями».

---

## 2. Выбранный образец: Aural Player, механизм `sizeToFit()`

### 2.1 Почему он

Aural - единственный из четырёх, кто управляет ширинами **одним штатным вызовом** и не пишет ни
строки своей арифметики:

```swift
// research/raw/aural-player/Source/UI/PlayQueue/TabularView/PlayQueueTabularViewController.swift:52-81
private func restoreDisplayedColumns() {
    ...
    defer {tableView.sizeToFit()}          // :57
    ...
}
// :104-113
@IBAction func toggleColumnAction(_ sender: NSMenuItem) {
    ...
    column.isHidden.toggle()
    tableView.sizeToFit()                  // :110
    saveColumnsState()
}
```

Чего у Aural нет: вызова `sizeToFit()` после протяжки разделителя. Его
`tableViewColumnDidResize` только сохраняет ширины
(`+TableViewDelegate.swift:139-143`). Поэтому у Aural таблица после протяжки шире окна - то же,
на что жалуется владелец. **Рецепт = механизм Aural + тот же самый вызов ещё из двух мест.**

### 2.2 Рецепт переноса

Свойства таблицы (всё штатное, ничего своего):

```swift
tableView.columnAutoresizingStyle = .noColumnAutoresizing   // раздачу делает sizeToFit, см. §4.2
tableView.allowsColumnResizing = true
tableView.allowsColumnReordering = true
tableView.autoresizingMask = [.width]       // таблица следует за шириной клипа
scrollView.hasHorizontalScroller = false
```

Свойства колонок:

```swift
column.minWidth = ...      // коридор: текст широкий, числа узкие (приём Aural/Cog/Bòcan)
column.maxWidth = ...
column.resizingMask = elastic                       // elastic == title, artist
    ? [.userResizingMask, .autoresizingMask]
    : [.userResizingMask]                           // числовые тянутся рукой, но не «дышат»
```

Единственная своя функция (та же, что уже есть у нас, только без балансировщика):

```swift
private func fitColumnsToWindow() {
    let clip = scrollView.contentView.bounds.width
    guard clip > 0 else { return }
    tableView.setFrameSize(NSSize(width: clip, height: tableView.frame.height))
    tableView.sizeToFit()
}
```

Зовётся из трёх мест, каждый - с защитой от повторного входа (`isFitting`):
1. `NSView.frameDidChangeNotification` на `scrollView.contentView` - окно меняет ширину (уже есть:
   `Sources/App/PlaylistController.swift:183-185`);
2. `NSTableView.columnDidResizeNotification` - владелец тянет разделитель (подписка уже есть:
   `PlaylistController.swift:186-188`, меняется только тело обработчика);
3. показ/скрытие колонки и смена кегля в `applySettings` - ровно как `sizeToFit()` у Aural
   (`PlayQueueTabularViewController.swift:110`).

**Что делать в `columnDidResize`: вызвать `fitColumnsToWindow()` и всё.** Никакой арифметики
дельты, никакого `NSOldWidth`, никакого списка доноров.

### 2.3 Как получается «таблица всегда по окну» при ужатии крайней колонки

Замер `probe-08-recipe.log` (6 колонок `title artist year dur bpm key`, эластичные - `title`,
`artist`, клип 500, `intercellSpacing.width = 8`):

```
  start (после fit)     widths=[139,115,46,56,48,48] sum+intercell=500 tableW=500 clipW=500 fits=true
  ужали КРАЙНЮЮ key -30 widths=[144,120,46,56,48,38] sum+intercell=500 tableW=500 clipW=500 fits=true
      кто изменился: ["title:139->144", "artist:115->120", "key:48->38"]
```

Механика: AppKit при протяжке меняет одну колонку и растягивает/сжимает саму таблицу
(доказано в research/07 §1.2 блок C). `sizeToFit()` после этого приводит **сумму ширин к ширине
таблицы**, а ширина таблицы принудительно равна ширине клипа. Освободившиеся 30 pt ушли в
`title`/`artist`, справа пустоты нет.

Контроль без рецепта, тот же лог, блок 0:
```
  ужали key -30   widths=[180,140,46,56,38,38] tableW=546 clipW=500 fits=false
```
то есть без вызова таблица остаётся 546 pt при окне 500 - это и есть сегодняшний брак.

### 2.4 Что происходит при упоре в минимумы

```
probe-08-recipe.log:
  протяжка year +400 (упор в max/min)  widths=[102,78,120,56,48,48] sum+intercell=500 fits=true
      year.max=120 title=102 (min 80) artist=78 (min 70)
  ещё title +400 - всё в минимумах     widths=[110,70,120,56,48,48] sum+intercell=500 fits=true
```

Тянутая колонка упирается в собственный `maxWidth`, эластичные - в свои `minWidth`, инвариант
«таблица == клип» держится. Дальше протяжка просто не даёт эффекта: это предсказуемо и
соответствует требованию (2).

Окно уже суммы минимумов (`probe-08-edges.log`, блок 4; сумма минимумов пробы 306 + 48 = 354):
```
  окно 380   widths=[80,70,46,56,48,48] tableW=396 clipW=380 fits=false
  окно 340   widths=[80,70,46,56,48,48] tableW=396 clipW=340 fits=false
  назад 500  widths=[132,122,46,56,48,48] tableW=500 clipW=500 fits=true
```
Ниже суммы минимумов таблица сжаться не может и вылезает за окно - крайняя правая колонка
подрезается. Это **риск для Claimp**, см. §5.4.

---

## 3. Текст в ячейке: нужна ли `FadingLabel`

### 3.1 Что делает образец

Bòcan - единственная фабрика ячейки на весь плейлист
(`research/raw/bocan-music/Modules/UI/Sources/UI/Browse/TrackTableCoordinator.swift:108-122`):

```swift
private func makeTextCell(cellID: NSUserInterfaceItemIdentifier) -> NSTableCellView {
    let cell = NSTableCellView()
    let tf = NSTextField(labelWithString: "")
    tf.lineBreakMode = .byTruncatingTail
    tf.cell?.truncatesLastVisibleLine = true
    cell.textField = tf
    NSLayoutConstraint.activate([
        tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
        tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
        tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])
    return cell
}
```

Ключевое: `alignment` не задаётся ни одной колонке - **все, включая BPM, Key и Length, выровнены
влево**; ширину текста решает колонка, потому что поле прибито к обоим краям ячейки; не влезло -
системное многоточие. Ни маски, ни градиента, ни `intrinsicContentSize`-хаков. Aural тот же
`truncatingTail` (`PlayQueueTabularView.xib:432`), но числа он выравнивает вправо с отступом 8 pt
(`xib:440`) - это ровно то, что владелец назвал «приклеено к правому краю», поэтому берём
вариант Bòcan.

### 3.2 Наш брак на снимке

снимок владельца 16.09 (`~/Pictures/Screenshots`): `Year` показывает
«2024» с последней цифрой под серым градиентом, `Length` - «2:35» с подрезанной пятёркой,
`BPM` - «170» с подрезанным нулём, при том что в колонке явно есть свободное место слева.
Числа прижаты к правому краю, то есть градиент `FadingLabel` (`Sources/App/FadingLabel.swift:87-93`)
садится ровно на последний знак. Требование владельца (3) нарушено дважды: и «приклеены»,
и «уходят в серый».

### 3.3 Вердикт по `FadingLabel`

**Не нужна.** Образцу она не нужна (ни у одного из четырёх проектов нет `CAGradientLayer` в
плейлисте), а весь её смысл - «текст не расширяет колонку» - штатно даёт
`NSTextField` с `lineBreakMode = .byTruncatingTail`, прибитый к обоим краям ячейки: у такого
поля ширина задана констрейнтами, `intrinsicContentSize` на раскладку не влияет.

Если владелец всё же захочет мягкую обрезку вместо многоточия, правильная форма - та, что уже
лежит в рабочем дереве незакоммиченной (`FadingLabel.swift:85-93`): маска включается **только при
переполнении** (`label.intrinsicContentSize.width > bounds.width`) и только у **правого края**,
при выравнивании влево. При выравнивании вправо гасить пришлось бы левый край, что читается как
«цифра обгрызена спереди», - поэтому выравнивание влево и мягкая обрезка справа совместимы, а
выравнивание вправо с любой маской - нет. Рекомендация: сначала перенести чистый вариант Bòcan
(`.byTruncatingTail`), градиент показать владельцу отдельным вопросом, а не тащить как данность.

---

## 4. Проба рецепта

Файлы: `research/raw/probe/probe8.swift` (основной), `probe8b.swift` (края), `probe8c.swift`
(нужен ли шаг с рамкой). Логи: `probe-08-recipe.log`, `probe-08-edges.log`,
`probe-08-frame-step.log`. Стенд: 6 колонок, окно 500×300, `hasHorizontalScroller = false`,
`tableView.autoresizingMask = [.width]`, `intercellSpacing.width = 8`
(поэтому `tableW = сумма ширин + 48`).

### 4.1 Три сценария владельца - числами

```
ужатие крайней правой:   ужали КРАЙНЮЮ key -30  widths=[144,120,46,56,48,38] sum+intercell=500 tableW=500 clipW=500 fits=true
расширение окна 500->900: окно 500->900          widths=[339,315,46,56,48,48] sum+intercell=900 tableW=900 clipW=900 fits=true
протяжка средней +40:     протяжка year +40      widths=[119,95,86,56,48,48]  sum+intercell=500 tableW=500 clipW=500 fits=true
      кто изменился: ["title:139->119", "artist:115->95", "year:46->86"]
возврат:                  вернули year -40       widths=[139,115,46,56,48,48] sum+intercell=500 fits=true
```

Сумма ширин + межколоночные промежутки == ширина клипа во всех трёх случаях. Протяжку гасят
только `title`/`artist`; `dur`, `bpm`, `key` не шевельнулись - то есть владелец, поставив ширину
числовой колонке рукой, её больше не теряет.

Серия из пяти протяжек подряд и обратно (`probe-08-edges.log`, блок 6) возвращает ровно исходные
ширины `[139,115,46,56,48,48]` - накопленной ошибки нет.

### 4.2 Какой `columnAutoresizingStyle` брать

Рецепт держит инвариант при **любом** стиле (`probe-08-recipe.log`: четыре блока, везде
`fits=true`). Разница только в том, как расходится прирост окна 500→900:

```
uniform         title:139->389, artist:115->265     (неравные доли)
sequential      artist:115->515                     (всё одной колонке)
lastColumnOnly  artist:115->515                     (всё одной колонке)
none            title:139->339, artist:115->315     (+200 и +200, поровну)
```

Требование владельца «место разошлось по колонкам» точнее всего выполняет
**`.noColumnAutoresizing`**: раздачу целиком делает `sizeToFit`, и она равная. `sequential` и
`lastColumnOnly` отдают весь прирост исполнителю, `uniform` делит неравно (вмешивается штатный
авторесайз до нашего вызова).

### 4.3 `sizeToFit` уважает `.autoresizingMask` - проверено

`probe-08-recipe.log`, блок 2:
```
до: [180,140,46,56,48,48]   после клип 900 + sizeToFit: [347,307,46,56,48,48] sum=852 tableW=900
изменились неэластичные? []
```
Это опровергает вывод 5 отчёта research/07 («`sizeToFit` переписывает все ширины»): он был
измерен на стенде, где `.autoresizingMask` стоял у **всех** колонок (`probe2.swift`). Как только
маска только у `title`/`artist`, `sizeToFit` трогает только их.

### 4.4 Нужен ли `setFrameSize` перед `sizeToFit`

`probe-08-frame-step.log`: при протяжке `bpm +40` результат одинаков с шагом и без него
(`widths=[119,95,46,56,88,48]`, `tableW=500`). То есть в стенде `tableView.autoresizingMask =
[.width]` уже удерживает рамку. Но на живом Claimp был зафиксирован случай, когда рамка уезжала
(смена кегля: таблица 737 pt при окне 500, `Sources/App/PlaylistController.swift:210-215`),
поэтому строку `setFrameSize` оставить: она стоит одну строку и доказанно не вредит.

### 4.5 `sizeLastColumnToFit` - не наш случай

`probe-08-recipe.log`, блок 3: при клипе 900 он отдал весь остаток последней колонке
(`key: 48 -> 474`), **проигнорировав её `maxWidth = 120`**. Для узких числовых колонок это
негодно.

---

## 5. Итог для исполнителя

### 5.1 Удалить

| Что | Где | Почему |
|---|---|---|
| `ColumnWidthBalancer` целиком | `Sources/Core/ColumnWidthBalancer.swift` (66 строк) + его тесты | вся арифметика раздачи делается `sizeToFit()` (§4.1) |
| `balanceColumns(after:oldWidth:)` | `Sources/App/PlaylistController.swift:307-328` | вся раздача - в `sizeToFit()` |
| Константы `resizedColumnKey`/`oldWidthKey` и разбор `userInfo` | `Sources/App/PlaylistController.swift:289-290`, `:296-305` | дельта и `NSOldWidth` больше не нужны |
| Флаг `isBalancingColumns` переименовать в `isFitting` и оставить один | `Sources/App/PlaylistController.swift:42`, `:323`, `:327`, `:368-370` | защита от рекурсии нужна, имя - от прежней механики |
| `FadingLabel` целиком | `Sources/App/FadingLabel.swift` (99 строк) | обрезку даёт `lineBreakMode = .byTruncatingTail` (§3) |
| `PlaylistColumn.alignsRight` | `Sources/App/PlaylistTable.swift:90` | всё влево, как у Bòcan; свойство-заглушка `false` не нужно |
| `runColumnProbe` и `reportColumnProbe` | `Sources/App/PlaylistController.swift:336-372`, `:374+` | отладочный прогон писался под балансировщик; вместо него - `probe8.swift` вне продукта |
| `Theme.column.cellInsetTrailing = 8` как «воздух под цифры справа» | `Sources/App/Theme.swift:~20` | у Bòcan симметричные 4/4; отступ 8 справа нужен был правому выравниванию |

### 5.2 Оставить

- Коридоры `minWidth/maxWidth` по колонкам (`Theme.swift`, `PlaylistColumn.widthRange`) - тот же
  приём у всех четырёх образцов.
- `PlaylistColumn.stretches` (маска `.autoresizingMask` только у `title`/`artist`) -
  именно она заставляет `sizeToFit` трогать только текстовые колонки (§4.3).
- Подписки на `frameDidChangeNotification` клипа и `columnDidResizeNotification`
  (`PlaylistController.swift:181-188`) - меняются только тела обработчиков.
- `autosaveName`/`autosaveTableColumns` после добавления колонок (`:177-178`) - порядок как у
  Bòcan (`TrackTable.swift:141-156`).
- `FlatHeaderCell` с риской и индикатором сортировки (`PlaylistTable.swift:158-200`) - к ширинам
  отношения не имеет, владелец риски просил.

### 5.3 Написать (оценка ~25 строк итогового кода вместо ~190 сегодняшних)

1. `fitColumnsToWindow()` - 5 строк (§2.2), плюс флаг `isFitting` - 3 строки.
2. `columnDidResize` → `fitColumnsToWindow()` - 3 строки вместо 30.
3. `clipDidResize` → то же самое (уже так).
4. В `applySettings`: `fitColumnsToWindow()` после смены видимости/кегля - 1 строка (как Aural
   `PlayQueueTabularViewController.swift:110`).
5. `tableView.columnAutoresizingStyle = .noColumnAutoresizing` - 1 строка (замена
   `PlaylistController.swift:158`).
6. Фабрика текстовой ячейки по Bòcan: `NSTextField(labelWithString:)`, `.byTruncatingTail`,
   `truncatesLastVisibleLine = true`, констрейнты leading +4 / trailing −4, без `alignment` -
   ~12 строк вместо `FadingLabel` (99 строк) и её вызовов.
7. Тест: один поведенческий на `fitColumnsToWindow` не нужен - это обёртка над AppKit
   (IO-обёртка, PBT и юнит не применимы по планке). Вместо теста - живой смок по трём сценариям
   §4.1 и снимок владельцу. Тесты `ColumnWidthBalancer` удаляются вместе с ним.

CRAP: `fitColumnsToWindow` - цикломатическая сложность 2, `columnDidResize` - 1. Сегодняшние
`balanceColumns` (5 ветвей) и `redistribute` (цикл + 4 тернарника) уходят.

### 5.4 Риски

1. **🔴 Сумма минимумов больше минимального окна.** Минимумы Claimp:
   `16+28+120+90+40+44+48+40+40 = 466` (`Sources/App/Theme.swift:96-118`) плюс
   `intercellWidth 2 × 9 = 18` → **484 pt**, а `windowMinWidth = 420`
   (`Sources/App/Theme.swift:80`). При 420 pt таблица физически не сожмётся и крайняя правая
   колонка подрежется (воспроизведено в `probe-08-edges.log`, блок 4). Лечится опусканием
   `titleMin` до ~80 и `artistMin` до ~60 (сумма 414) либо подъёмом `windowMinWidth` до 500.
   Решение - владельцу, но исполнитель обязан свести числа до сдачи.
2. **Владелец скрыл обе эластичные колонки.** Что делает `sizeToFit`, когда ни у одной видимой
   колонки нет `.autoresizingMask`, - **не установлено** (в пробе такого случая нет). Проверить
   одной строкой в `probe8b` до реализации; страховка - если эластичных не осталось, ставить
   `.autoresizingMask` последней видимой.
3. **Повторный вход.** `sizeToFit()` внутри обработчика `columnDidResizeNotification` сам
   порождает такие же уведомления; без флага `isFitting` будет рекурсия. В пробе флаг стоит
   (`probe8.swift`, `Harness.balancing`), и прогон чистый.
4. **Autosave и `sizeToFit`.** Сохранённые ширины восстанавливаются до первой раскладки, потом
   `fitColumnsToWindow` подгонит эластичные под текущее окно; ручные ширины числовых переживут
   (§4.1). На живом приложении подтвердить перезапуском - в пробе autosave не участвовал.
5. **research/07 вывод 5 устарел** (§4.3): в спеке исполнителю нельзя ссылаться на него как на
   довод против `sizeToFit`.

### 5.5 Что становится с `restoreWidthInvariant`

`Sources/App/PlaylistController.swift:281-287` - это уже и есть `fitColumnsToWindow` из §2.2
(`setFrameSize` по ширине клипа + `sizeToFit`). Переименовать и звать из трёх мест; писать заново
нечего. То есть правильный кусок у нас уже написан, лишними оказались балансировщик поверх него
и условие «звать только при смене кегля или видимости» (`:270-278`).

---

## 6. Скиллы

`npx -y skills find nstableview`:

| Скилл | Установок | Оценка |
|---|---|---|
| `travisjneuman/.claude@macos-native` | 291 | общий про «нативный macOS», про таблицы ничего не обещает - **бесполезен** |
| `rgmez/apple-accessibility-skills@appkit-accessibility-auditor` | 274 | доступность AppKit; к ширинам колонок не относится - **бесполезен** |
| `fandhe-ai/agent-reference-skills@apple-appkit` | 37 | справочник по AppKit, может пригодиться как шпаргалка, но первичные заголовки SDK у нас уже под рукой - **не нужен** |
| `mihaelamj/cupertino@cupertino` | 34 | **бесполезен** |
| `yigitkonur@apply-macos-hig` / `@develop-macos-hig` | 14 / 6 | HIG, а в HIG правил про компенсацию протяжки нет (research/07 §2) - **бесполезен** |
| `j4flmao/agent-skills@desktop-appkit` | 8 | **не установлено**, что внутри; 8 установок - брать не стоит |
| прочие (`crash-log-analyzer` 2, `appkit-accessibility-auditor` 2, `xcode-mcp` 2) | ≤2 | мимо темы |

`npx -y skills find "appkit table"`:

| Скилл | Установок | Оценка |
|---|---|---|
| `ehmo/platform-design-skills@macos-design-guidelines` | 3.8K | дизайн-гайдлайны macOS; к механике `NSTableView` не относится - **бесполезен для задачи** |
| `charleswiltgen/axiom@axiom-macos` | 951 | **уже установлен локально** (в списке скиллов сессии как `axiom-macos`), это общий macOS-скилл |
| `databricks@databricks-apps`, `reown-com/skills@appkit` (885) | - | `appkit` у Reown - это криптокошелёк, омоним; **мимо** |
| `pasqualevittoriosi/swift-accessibility-skill` (285), `rgmez/...` (274) | - | доступность, мимо |

**Итог по скиллам: ни одного полезного для колонок `NSTableView` не существует.** Локально уже
есть `swift-macos`, `macos-development` и `axiom-macos` - этого достаточно; ставить ничего не надо.

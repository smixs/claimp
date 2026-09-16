# 07. Колонки плейлиста: как AppKit меняет ширины и что делать

Дата: 2026-09-16. Источники: заголовки SDK macOS 27, developer.apple.com (JSON-API docs),
исходники четырёх открытых приложений на AppKit, собственные измерения на живом AppKit
(скрипты `research/raw/probe/probe2.swift`, `probe3.swift`, `probe5.swift`, собраны
`DEVELOPER_DIR=/Library/Developer/CommandLineTools swiftc`, запущены как accessory-приложение).
Папка `research/raw/` в публичный экспорт не входит.

Правила отчёта: каждое утверждение с опорой. Где опоры нет - написано «не установлено».

---

## 0. Что показывает видео владельца

- `frame-06.jpg`, `frame-12.jpg`: курсор ресайза стоит между `Length` и `BPM`; заголовок -
  сплошная плоская полоса, ни одной вертикальной риски между колонками.
- `frame-12.jpg`: после протяжки `Length` превратился в «Le…» - ужалась соседняя колонка,
  а не та, чью границу тянули.
- `frame-20.jpg`: левый край таблицы обрезан (виден хвост «мix)» вместо колонки «Название»),
  то есть таблица шире окна и уехала вправо - при `hasHorizontalScroller = false`
  (`Sources/App/PlaylistController.swift:183`) это выглядит как «колонка пропала».
- `contact.jpg`: BPM/Key прижаты друг к другу, между цифрой и следующей колонкой нет воздуха.

---

## 1. Как AppKit на самом деле меняет ширины

### 1.1 Что говорит SDK

`/Library/Developer/CommandLineTools/SDKs/MacOSX27.0.sdk/.../NSTableView.h:170-173`:

> `/* Get and set the columnAutoresizingStyle. This controls resizing in response to a tableView
> frame size change, usually done by dragging a window larger that has an auto-resized tableView
> inside it. The default value is NSTableViewLastColumnOnlyAutoresizingStyle. */`

Ключевое: `columnAutoresizingStyle` описывает **только реакцию на изменение рамки таблицы**.
Про перетаскивание разделителя в заголовке он не говорит ничего.

`NSTableView.h:30-51` - тексты констант:

> `NSTableViewUniformColumnAutoresizingStyle` - «Autoresize all columns by distributing equal
> shares of space simultaneously»
> `NSTableViewSequentialColumnAutoresizingStyle` - «Start with the last autoresizable column,
> proceed to the first»
> `NSTableViewReverseSequentialColumnAutoresizingStyle` - «Start with the first autoresizable
> column, proceed to the last»
> `NSTableViewLastColumnOnlyAutoresizingStyle` / `FirstColumnOnly` - «Autoresize only one table
> column one at a time. When that table column can no longer be resized, stop autoresizing.
> Normally you should use one of the Sequential autoresizing modes instead.»

`NSTableColumn.h:20-24`: маска `NSTableColumnAutoresizingMask` = «This column can be resized as
the table is resized», `NSTableColumnUserResizingMask` = «The user can resize this column
manually». Это две независимые вещи: участие в авторесайзе и разрешение тянуть рукой.

`NSTableView.h:166-168` (`allowsColumnResizing`): «Controls whether the user can attempt to
resize columns by dragging between headers».

### 1.2 Что происходит в действительности (измерено)

Замер `research/raw/probe/probe2.swift` - таблица 5 колонок [60,200,120,60,60] в `NSScrollView`
без горизонтального скроллера, `tableView.autoresizingMask = [.width]`, все колонки
`[.userResizingMask, .autoresizingMask]`.

**A. Перетаскивание разделителя (эмулировано `column.width += 60`, это ровно то, что делает
`NSTableHeaderView` при drag) - блок C/D замера:**

```
none          [28,200,120, 60,60] -setWidth-> [28,200,120,120,60] -relayout-> без изменений  tableW: 560  clipW: 500
uniform       [54,194,114, 54,54] -setWidth-> [54,194,114,114,54] -relayout-> без изменений  tableW: 560  clipW: 500
sequential    ... то же ...                                                                   tableW: 560
lastColOnly   ... то же ...                                                                   tableW: 560
firstColOnly  ... то же ...                                                                   tableW: 560
```

Вывод 1: **при перетаскивании разделителя меняется ровно одна колонка - та, что слева от
разделителя. Ни один `columnAutoresizingStyle` на это не влияет. Компенсации нет: растёт сама
таблица** (560 > 500 ширины клипа). Соседи справа просто уезжают вправо, крайняя правая уходит
за край окна. Это и есть жалобы (2) «Key нельзя оттянуть вправо» и `frame-20` с обрезанным
левым краем.

**B. Изменение рамки таблицы (окно) - блок A/B замера, все колонки авторесайзятся:**

```
500 -> 700:  none [28,200,120,60,60] -> без изменений
             uniform      [54,194,114,54,54] -> [94,234,154,94,94]   (+40 каждой, поровну)
             sequential   [60,200,120,60,28] -> [60,200,120,60,228]  (весь прирост последней)
             reverseSeq   [28,200,120,60,60] -> [228,200,120,60,60]  (весь прирост первой)
             lastColOnly  как sequential;  firstColOnly как reverseSeq
500 -> 400:  uniform      [54,194,114,54,54] -> [34,174,94,34,34]    (-20 каждой)
             sequential   [60,200,120,60,28] -> [60,200,72,18,18]    (съедает с хвоста, каскадом)
             reverseSeq   [28,200,120,60,60] -> [18,110,120,60,60]   (съедает с головы)
             lastColOnly  [60,200,120,60,28] -> [60,200,120,60,18]   и СТОП: tableW 490 > 400,
                                                 остальное вылезает за окно
```

Вывод 2: `lastColumnOnly`/`firstColumnOnly` **упираются** - дожали одну колонку до `minWidth` и
перестали; таблица остаётся шире окна. `sequential`/`reverseSequential` каскадируют дальше по
цепочке. `uniform` размазывает поровну по всем - это и есть жалоба (4).

**C. Маска колонки уважается всеми стилями** (`research/raw/probe/probe5.swift`, набор колонок
как в Claimp, `.autoresizingMask` только у `title` и `artist` - т.е. текущий
`PlaylistColumn.stretches`, `Sources/App/PlaylistTable.swift:43-45,64-66`):

```
окно 500 -> 420 (played number title artist year dur kbps bpm key)
uniform      [18,22,130,100,...] -> [18,22, 95, 65,...]   поровну между title и artist
sequential   [18,22,130,100,...] -> [18,22,130, 30,...]   сначала artist (последняя авторесайзная)
lastColOnly  [18,22,130,100,...] -> [18,22,130, 30,...]   то же самое
reverseSeq   [18,22,130,100,...] -> [18,22, 60,100,...]   сначала title (первая авторесайзная)
firstColOnly [18,22,130,100,...] -> [18,22, 60,100,...]   то же самое
none         без изменений, таблица остаётся 490 при окне 420
```

Вывод 3: «last column» в названии стиля означает **последнюю авторесайзную**, а не последнюю в
таблице. Key/BPM без `.autoresizingMask` не тронет ни один стиль. Это уже сделано правильно.

**D. Расширение окна работает только если сумма ширин РАВНА ширине таблицы** (`probe5`):

```
без sizeToFit:  окно 500 -> 800, сумма 490:   ни один стиль ничего не поменял, справа дыра
после sizeToFit (сумма стала ровно 500):
   uniform      [.,.,135,105,.] -> [.,.,285,255,.]
   sequential   [.,.,135,105,.] -> [.,.,135,405,.]
   reverseSeq   [.,.,135,105,.] -> [.,.,435,105,.]
```

Вывод 4: `sizeToFit()` - это не «подогнать под содержимое», а «сделать сумму ширин равной ширине
таблицы, растянув/сжав все авторесайзные колонки». Он же восстанавливает инвариант, без которого
расширение окна вообще не раздаёт место.

**E. `sizeToFit()` переписывает ширины, которые владелец выставил рукой** (`probe2`, блок E):

```
после ручного +60 на колонке #3, в клипе 500:
   none        [28,200,120,120,60] -sizeToFit-> [18,188,108,108,48]   (изменились ВСЕ пять)
   uniform     [54,194,114,114,54] -sizeToFit-> [42,182,102,102,42]
```

Вывод 5: `tableView.sizeToFit()` в `applySettings` (`Sources/App/PlaylistController.swift:217`)
вызывается на каждое применение настроек и **сдвигает все девять колонок**. Вместе с `uniform`
это вторая причина жалобы (4).

### 1.3 Сводка по вопросу 1

| Стиль | При drag разделителя | При изменении ширины окна | Крайняя правая, когда таблица прибита к окну |
|---|---|---|---|
| `none` | меняется только та колонка, таблица растёт | ничего не меняется | уезжает за край / появляется дыра справа |
| `uniform` | то же | дельта делится поровну между всеми авторесайзными | не выделена, страдает вместе со всеми |
| `sequential` | то же | последняя авторесайзная, потом предыдущая и т.д. | если она авторесайзная - забирает остаток первой |
| `reverseSequential` | то же | первая авторесайзная, потом следующая | не участвует, пока цепочка не дойдёт |
| `lastColumnOnly` | то же | только последняя авторесайзная, дальше стоп | забирает/отдаёт остаток, но упирается в min/max |
| `firstColumnOnly` | то же | только первая авторесайзная, дальше стоп | не участвует |

Дефолт класса - `lastColumnOnly`, подтверждено и доком (`NSTableView.h:170`), и замером
(`probe.swift`: `DEFAULT columnAutoresizingStyle rawValue = 4`).

Мелочи из того же замера, полезные при отладке: у свежего `NSTableColumn` `minWidth = 10`,
`maxWidth = 3.4e38`, `width = 100`, `resizingMask.rawValue = 3` (обе маски). У свежего
`NSTableView` на macOS 27 `intercellSpacing = (17.0, 0.0)` - документация в заголовке
(`NSTableView.h:179-181`, «default value is NSMakeSize(3, 2)») **устарела**.

---

## 2. Режим для компактного окна ~500 pt: что рекомендовать

Сначала факт: **AppKit не умеет из коробки «тяну границу - остальные на месте, крайняя правая
забирает остаток»**. Это доказано блоком C замера: после drag таблица всегда становится шире, и
ни один стиль не откусывает разницу у соседей. Значит выбирать приходится между двумя честными
моделями.

### Вариант A (рекомендуемый): `lastColumnOnly` + одна компенсация на изменённую колонку

```
tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
tableView.autoresizingMask = [.width]      // как сейчас
scrollView.hasHorizontalScroller = false   // как сейчас
// .autoresizingMask только у title и artist - как сейчас (PlaylistTable.swift:43-45)
```

плюс подписка на штатное уведомление. В SDK оно есть: `NSTableView.h:719` -
`- (void)tableViewColumnDidResize:(NSNotification *)notification;`, `NSTableView.h:729` -
`NSTableViewColumnDidResizeNotification; // @"NSTableColumn", @"NSOldWidth"`. По дельте
`width - NSOldWidth` отнять/добавить ту же дельту у «эластичной» колонки (artist, потом title),
не выходя за её `minWidth`.

Ровно так делает IINA, только руками и без уведомления:
`research/raw/iina/HistoryWindowController.swift:177-186`

```swift
private func donateColWidth(to targetColumn: NSTableColumn, targetWidth: CGFloat, from donorColumn: NSTableColumn) {
    let extraWidthNeeded = targetWidth - targetColumn.width
    let widthToDonate = min(extraWidthNeeded, max(donorColumn.width - donorColumn.minWidth, 0))
    if widthToDonate > 0 {
        donorColumn.width -= widthToDonate
        targetColumn.width += widthToDonate
    }
}
```

и комментарий оттуда же (строки 170-172): «Do not set this until after width has been adjusted!
Otherwise AppKit will change its width property but will not actually resize it».

Плюсы: точное поведение, которого хочет владелец; горизонтального скролла нет; крайняя правая
(Key) никогда не уезжает за край. Минусы: ~20 строк своего кода и один инвариант, который надо
держать (сумма ширин == ширина таблицы).

### Вариант B: как в Finder/Music - разрешить горизонтальный скролл

```
tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
scrollView.hasHorizontalScroller = true
scrollView.autohidesScrollers = true
// tableView.autoresizingMask НЕ трогаем (таблица имеет право быть шире клипа)
```

Так сделано в Bòcan: `research/raw/bocan-music/Modules/UI/Sources/UI/Browse/TrackTable.swift:126`
(`tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle`) и `:178-186`
(`hasHorizontalScroller = true`, `autohidesScrollers = true`).

Плюсы: ноль своего кода, поведение системное и предсказуемое. Минусы: в окне 500 pt при девяти
колонках горизонтальный скроллер будет почти всегда, а владелец уже зафиксировал инвариант
«длинный текст никогда не расширяет окно/колонки» (`CLAUDE.md`, раздел «UX-инварианты»).

### Что делает сам Finder / Music

Не установлено по первичным источникам: исходники закрыты, в HIG
(`developer.apple.com/design/human-interface-guidelines/lists-and-tables`) правил о том, какая
колонка компенсирует протяжку, нет. Единственное, что удалось подтвердить у Apple напрямую, -
`TableColumnAlignment` в SwiftUI (см. §5).

**Рекомендация: вариант A.** Он единственный даёт формулировку владельца слово в слово и не
ломает инвариант «ничего не вылезает за окно».

---

## 3. Разделители в заголовке и зона захвата

### 3.1 `gridStyleMask` заголовок не рисует - проверено

Замер `research/raw/probe/probe3.swift`: таблица 4×100 pt, `gridColor = .red`, снимаются битмапы
отдельно с `headerView` и с `tableView`, считаются красные пиксели по горизонтали.

```
grid none,     штатный header  | header: []              | body: []
grid vertical, штатный header  | header: []              | body: [166,167, 366,367, 566,567]
grid vertical, плоский header  | header: []              | body: [166,167, 366,367, 566,567]
```

Вывод: `NSTableView.gridStyleMask = .solidVerticalGridLineMask` рисует вертикальные линии
**только в теле таблицы, в заголовке - никогда**. Для жалобы (1) он бесполезен сам по себе
(хотя как «продолжение» риски вниз по списку может пригодиться).

### 3.2 Почему разделители пропали именно у нас

`Sources/App/PlaylistTable.swift:126-135` - `FlatHeaderCell.draw(withFrame:in:)` заливает весь
`cellFrame` цветом `Theme.surface.raised`, рисует только нижний хайрлайн и зовёт `drawInterior`.
`super.draw` не вызывается, значит штатная отрисовка `NSTableHeaderCell` (включая её бордер;
в xib'ах это `borderStyle="border"`, см. `research/raw/Cog/Base.lproj/MainMenu.xib:391`) не
происходит вовсе. Разделителей нет не «из-за настроек таблицы», а потому что их некому нарисовать.

### 3.3 Как рисуют другие

Aural, `research/raw/aural-player/Source/UI/PlayQueue/TabularView/PlayQueueTabularViewTableHeaderCell.swift:15-22`:

```swift
override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
    cellFrame.fill(withColor: systemColorScheme.backgroundColor)
    if stringValue != "#" {
        GraphicsUtils.drawLine(systemColorScheme.tertiaryTextColor,
            pt1: NSMakePoint(cellFrame.minX + 1, cellFrame.minY + 2),
            pt2: NSMakePoint(cellFrame.minX + 1, cellFrame.maxY - 5), width: 1)
    }
    ...
}
```

То есть: у **каждой** колонки, кроме первой, рисуется вертикальная линия шириной 1 pt по левому
краю ячейки, с отступами сверху/снизу (2 и 5 pt) - поэтому линия читается как «риска», а не как
сплошная сетка. Это ровно то, чего не хватает в `FlatHeaderCell`.

### 3.4 Зона захвата курсора ресайза

Штатной API-ручки «сделать зону шире» в SDK нет: `NSTableHeaderView.h:19-31` даёт только
`draggedColumn`, `draggedDistance`, `resizedColumn`, `headerRectOfColumn:`, `columnAtPoint:`.
Публичного свойства ширины хит-зоны нет; сама зона добавляется приватно внутри
`resetCursorRects` заголовка.

Рабочий путь, который реально применяют - переопределить `mouseDown` и самому решать, попал ли
клик в разделитель. Cog, `research/raw/Cog/Playlist/PlaylistHeaderView.m:13-31`:

```objc
- (void)mouseDown:(NSEvent *)theEvent {
    NSPoint local_point = [self convertPoint:[theEvent locationInWindow] fromView:nil];
    int column = (int)[self columnAtPoint:local_point];
    if([theEvent clickCount] == 2 && column != -1) {
        BOOL clickedSeperator = NO;
        NSRect rect = [self headerRectOfColumn:column];
        // handle a click one pixel away at right
        if(fabs(rect.origin.x - local_point.x) <= 1.0 && column > 0) { --column; clickedSeperator = YES; }
        // handle a click 3 pixels away at left
        else if(fabs(rect.origin.x + rect.size.width - local_point.x) <= 3.0) clickedSeperator = YES;
        ...
```

Из этого кода видно и порядок величин, на который ориентируются практики: 1-3 pt от границы.
Для «куда наводить мышь» этого мало - нужен видимый маркер (см. §6).

Дополнительно доступно без хаков:
- `resetCursorRects` у своего `NSTableHeaderView`: вызвать `super`, затем добавить свои
  `addCursorRect(_:cursor: .resizeLeftRight)` шириной 6-8 pt вокруг каждой границы. Это штатный
  механизм `NSView`, конфликтов с приватными ректами AppKit не создаёт (они складываются).
- `resizedColumn` (`NSTableHeaderView.h:27`) в момент отрисовки даёт индекс колонки, которую
  сейчас тянут, - можно подсветить её риску, пока идёт drag.

### 3.5 Индикатор сортировки - побочный риск

`NSTableHeaderCell.h:16-22` говорит, что `drawSortIndicatorWithFrame:...` и
`sortIndicatorRectForBounds:` - точки кастомизации, вызываемые штатной отрисовкой ячейки.
`FlatHeaderCell.draw` (`PlaylistTable.swift:126-135`) `super.draw` не зовёт, поэтому
`drawSortIndicator` (`PlaylistTable.swift:156-172`) может не вызываться вовсе. Плюс он рисует
треугольник в `cellFrame.midX` - по центру ячейки, тогда как штатное место (и место у Aural/Cog)
- у края. Проверить живым запуском; в текущей задаче не трогать, если индикатор виден.

---

## 4. Как это сделано в открытых плеерах

Все четыре разобраны по коду, не по README. Клоны - `research/raw/`.

### 4.1 Aural Player (kartik-venugopal/aural-player, MIT)

Файл `Source/UI/PlayQueue/TabularView/PlayQueueTabularView.xib`.

- `:33` - `<tableView identifier="tid_PlayQueueSimpleView" ... autosaveColumns="NO" rowHeight="30"
  headerView="jal-TJ-HVq" viewBased="YES" customClass="AuralTableView">`. Атрибута
  `columnAutoresizingStyle` нет. В том же репозитории IB пишет его явно там, где он не дефолтный
  (`grep -rho 'columnAutoresizingStyle="[a-z]*"'` по `Source`: 14 × `none`, 4 × `lastColumnOnly`,
  4 × `firstColumnOnly`), поэтому «атрибут отсутствует» здесь означает значение по умолчанию.
  Какое именно значение IB считает дефолтным - **не установлено**; дефолт класса по
  `NSTableView.h:170` - `lastColumnOnly`.
- `:34` - autosave колонок выключен (`autosaveColumns="NO"`), ширины не запоминаются.
- `:37` - `<size key="intercellSpacing" width="3" height="4"/>`.
- min/max по колонкам (`:40,:90,:130,:170,:210,:250,:290,:370,:410`):
  `Index 65/40..65`, `Title 255/150..10000`, `FileName 200/100..1000`, `Artist 150/80..500`,
  `Album 150/80..500`, `Genre 125/80..250`, `TrackNum 60/50..80`, `Year 80/60..80`,
  `Duration 80/60..80`. Приём: **у текстовой колонки maxWidth огромный, у числовых - узкий
  коридор** (Duration вообще 60..80, тянуть почти нечего).
- маска у всех: `:50,:101,...` - `<tableColumnResizingMask resizeWithTable="YES" userResizable="YES"/>`.
- Выравнивание Duration: заголовок `alignment="left"` (`:411`), а внутри прототипа ячейки
  `<textFieldCell key="cell" ... alignment="right">` (`:432`) и **отступ справа 8 pt**:
  `:440` - `<constraint firstAttribute="trailing" secondItem="XJ6-89-L5c" secondAttribute="trailing" constant="8"/>`.
- Кастомный заголовок - `PlayQueueTabularViewTableHeaderCell.swift` (см. §3.3): своя риска,
  и для «Duration» текст ставится в `cellFrame.maxX - size.width - 5` (`:40`) - те же ~5 pt
  воздуха справа.

### 4.2 Cog (losnoco/Cog, GPL)

- `Base.lproj/MainMenu.xib:34` - `<tableView ... autosaveName="Playlist" rowHeight="18"
  headerView="1517" viewBased="YES" customClass="PlaylistView">`; `columnAutoresizingStyle`
  не задан.
- `Base.lproj/MainMenu.xib:27` - `<scrollView ... hasHorizontalScroller="NO" ...>`: горизонтального
  скроллера нет, как у нас.
- min/max: `index 64/28..64`, `status 20/20..20`, `title 189.5/96..1024`, `artist 212/96..1024`,
  `album 210.5/96..1024`, `length 95.5/43.62..96`, `date 96/42..96`, `track 72/24..72`,
  `bitrate 64/32..1024`. Тот же приём: текст 96..1024, числа заперты в узкий коридор.
- Выравнивание (заголовки, `:42,:391,:435,:516,:556,:820`): `#`, `Length`, `Date`, `№`,
  `Play Count`, `Bitrate` - `alignment="right"`; `Title`, `Artist`, `Album`, `Genre`, `Composer`,
  `Path`, `Codec` - `alignment="left"`. `dataCell` числовых колонок тоже `alignment="right"`
  (`:396`). Что при этом реально показывает view-based ячейка (у прототипа `textFieldCell` на
  `:406` выравнивание не задано) - **не установлено**.
- Кастомный заголовок `Playlist/PlaylistHeaderView.m` - только `mouseDown` (§3.4), рисование
  штатное.

### 4.3 Bòcan (bocan/bocan-music)

`Modules/UI/Sources/UI/Browse/TrackTable.swift`:
- `:119-126` - `allowsColumnReordering = true`, `allowsColumnResizing = true`,
  `columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle`.
- `:178-186` - `hasVerticalScroller = true`, **`hasHorizontalScroller = true`**,
  `autohidesScrollers = true`. Маску `autoresizingMask` таблице не ставят - таблица имеет право
  быть шире клипа.
- `:141-156` - autosave: сперва добавить колонки, потом `autosaveTableColumns = true` и только
  затем `autosaveName`. Комментарий на `:148-155`: «Arming it earlier breaks order/width restore…
  every restore was a no-op on an empty table and each rebuild re-saved the default order».
  У нас порядок правильный (`PlaylistController.swift:133-149`), но `autosaveTableColumns`
  ставится до `autosaveName` - проверить, что восстановление работает.
- `TrackTable+Helpers.swift:77-78` - «`NSTableView.autosaveTableColumns` only saves width and
  order, not visibility»; видимость колонок они хранят сами в `UserDefaults`.
- `TrackTable+ColSpecs.swift`: `title 140/220/2000` (`:45-49`), `artist 100/160/2000` (`:54-58`),
  `duration 48/60/72` (`:90-94`), `bitrate 64/80/96` (`:180-186`), `bpm 40/52/72` (`:216-222`),
  `key 40/56/80` (`:225-231`).
- Выравнивание: `TrackTableCoordinator.swift:108-122` - единственная фабрика ячейки,
  `NSTextField(labelWithString:)` без установки `alignment`, отступы
  `leading +4 / trailing -4`. То есть **все колонки, включая BPM/Key/Length, выровнены влево**.

### 4.4 IINA (iina/iina) - `HistoryWindowController.swift`

- `:103` - `scrollView.hasHorizontalScroller = false`; `:111` -
  `outlineView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle`; `:114` -
  `allowsColumnReordering = false`; `:113` - `autosaveName = "HistoryWindowTable"`.
- `:117-124` - три колонки с min/max: `filename 200..5000`, `progress 110..1000`,
  `time 60..300`. Эластичная (filename) стоит **первой**, поэтому и выбран `firstColumnOnly`.
- `:156-186` - ручная передача ширины между колонками (`donateColWidth`, §2). Это
  прямое подтверждение, что компенсацию в AppKit пишут руками.

### 4.5 Сводная таблица

| | стиль | гор. скролл | текстовая колонка | числовая колонка | header | числа |
|---|---|---|---|---|---|---|
| Aural | дефолт (не задан) | нет | Title 150..10000 | Duration 60..80 | свой, своя риска 1 pt | вправо, отступ 8 pt |
| Cog | дефолт (не задан) | нет | Title 96..1024 | Length 43.6..96 | штатный + свой `mouseDown` | вправо (в xib) |
| Bòcan | `lastColumnOnly` | **да** | Title 140..2000 | BPM 40..72 | штатный | влево, отступ 4 pt |
| IINA | `firstColumnOnly` | нет | filename 200..5000 | time 60..300 | штатный | не установлено |
| Claimp сейчас | `uniform` | нет | Title min 18 max 800 | BPM min 18 max 800 | свой, без риски | вправо, отступ 3 pt |

Общее у всех четырёх и отсутствующее у нас: **числовые колонки заперты в узкий коридор
min..max, текстовые - широкий**. Ни у кого нет `minWidth = 18` на всех подряд.

---

## 5. Выравнивание чисел

Первичный источник у Apple ровно один и он про SwiftUI-таблицы -
`developer.apple.com/documentation/swiftui/tablecolumnalignment/numeric(_:)`
(получено через `tutorials/data/.../numeric(_:).json`):

> «Column alignment appropriate for numeric content. Use this alignment when a table column is
> primarily displaying numeric content, so that the values are easy to visually scan and compare.
> This uses the provided numbering system to determine the alignment.»

То есть Apple заводит для чисел **отдельный** вид выравнивания, а не «trailing», и мотивирует
его сравнимостью значений по вертикали.

Практика плееров (по коду, §4):
- Aural - Duration вправо, отступ от правого края **8 pt** (`PlayQueueTabularView.xib:440`),
  в заголовке **5 pt** (`PlayQueueTabularViewTableHeaderCell.swift:40`).
- Cog - `#`, Length, Date, №, Play Count, Bitrate вправо (`MainMenu.xib:42,391,435,516,556,820`).
- Bòcan - всё влево, включая BPM/Key/Length (`TrackTableCoordinator.swift:108-122`).
- Rekordbox, Music.app - **не установлено**: исходников нет, а по скриншотам утверждать нельзя.

Про «приклеивание» (жалоба 3). Причина не в выравнивании, а в отступе:
`Theme.column.cellInset = 3` (`Sources/App/Theme.swift:147`) и он же используется как отступ
заголовка (`PlaylistTable.swift:151`) и как `leading/trailing` ячейки
(`PlaylistTable.swift:263-264`). У Aural справа 8 pt, у Bòcan 4 pt. При 3 pt и нулевом
`intercellSpacing` (`PlaylistController.swift:128`) между последней цифрой BPM и первым
пикселем Key остаётся 3 pt - визуально ноль.

**Рекомендация:** числа оставить вправо (Apple, Aural, Cog - все за), но
(1) `cellInset` для правого края числовых колонок поднять до 8 pt, (2) вернуть
`intercellSpacing.width` хотя бы 2-3 pt или нарисовать вертикальную риску между колонками -
тогда столбик цифр читается как столбик, а не как «приклеенный» край. Третий вариант, если
владелец всё равно видит «приклеено», - моноширинные цифры уже есть
(`PlaylistController.swift:273-275`, `Theme.font.rowDigits`), можно центрировать узкие BPM/Key;
но это отход от Apple и от двух из трёх плееров, так что только по слову владельца.

---

## 6. Итог: минимальная конфигурация

### 6.1 Что поставить

```swift
// PlaylistController.setupTable
tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle   // было .uniform
tableView.intercellSpacing = NSSize(width: 2, height: 0)               // было 0×0
tableView.allowsColumnResizing = true                                  // дефолт, зафиксировать явно
// autoresizingMask = [.width] и hasHorizontalScroller = false оставить как есть
```

```swift
// PlaylistColumn.applyLimits - коридор на колонку, а не общий minAny = 18
// played   16..24        number 22..40
// title   120..800 (.autoresizingMask)   artist 90..800 (.autoresizingMask)
// year     32..48        duration 44..64  bitrate 48..72
// bpm      40..64        key     40..72 (keyBoth 60..96)
```

```swift
// PlaylistColumn / Theme.column
static let cellInsetLeading: CGFloat = 4
static let cellInsetTrailing: CGFloat = 8      // было 3 на обе стороны
```

### 6.2 Что дорисовать в заголовке

`FlatHeaderCell.draw(withFrame:in:)` (`PlaylistTable.swift:126-135`), после заливки и до
`drawInterior`: вертикальная риска `Theme.border.subtle` шириной `Theme.size.hairline` по
`cellFrame.minX`, высотой `cellFrame.height - 6` (по 3 pt сверху и снизу), **кроме первой
колонки** - один в один приём Aural (`PlayQueueTabularViewTableHeaderCell.swift:21`).

`FlatHeaderView` (`PlaylistTable.swift:176-182`) дополнить `resetCursorRects`:
вызвать `super.resetCursorRects()`, затем на каждую границу колонок добавить
`addCursorRect(NSRect(x: border - 3, y: 0, width: 6, height: bounds.height), cursor: .resizeLeftRight)`.
Границы берутся из `headerRectOfColumn(_:)` (`NSTableHeaderView.h:28`).

### 6.3 Что убрать

1. **`columnAutoresizingStyle = .uniformColumnAutoresizingStyle`**
   (`PlaylistController.swift:130`) - прямая причина жалобы (4): §1.2 блок B/C показывает, что
   именно `uniform` размазывает дельту по всем авторесайзным колонкам.
2. **`tableView.sizeToFit()` в `applySettings`** (`PlaylistController.swift:217`) - §1.2 блок E:
   он переписывает все девять ширин, в том числе выставленные рукой. Вызывать его только один
   раз после первичной сборки колонок (чтобы установить инвариант «сумма == ширина таблицы»,
   без которого расширение окна вообще не работает, §1.2 блок D), и **не** вызывать при смене
   кегля. При смене кегля достаточно уже существующего масштабирования ширин
   (`PlaylistController.swift:212-215`).
3. **Общий `minAny = 18` для всех колонок** (`Theme.swift:150`) - ни в одном из четырёх
   разобранных плееров такого нет; из-за него при сужении окна `Title` может схлопнуться до
   18 pt раньше, чем что-то одно упрётся в разумный минимум.
4. **`maxAny = 800` для числовых колонок** (`Theme.swift:152`) - позволяет растянуть BPM на
   пол-окна; у Aural Duration 60..80, у Bòcan BPM 40..72.

### 6.4 Что добавить (компенсация, ~20 строк)

Подписаться на `NSTableView.columnDidResizeNotification` (`NSTableView.h:729`, userInfo
`"NSTableColumn"`, `"NSOldWidth"`); на каждое срабатывание, если ресайз инициировал пользователь
(`(tableView.headerView as? NSTableHeaderView)?.resizedColumn != -1`, `NSTableHeaderView.h:27`),
отдать/забрать дельту у эластичных колонок в порядке `artist -> title`, по образцу
`donateColWidth` из IINA (`research/raw/iina/HistoryWindowController.swift:177-186`), не опуская
их ниже `minWidth`. Флаг-страж от рекурсии обязателен: собственная правка ширины снова
выстрелит тем же уведомлением.

### 6.5 Риски и как проверить живым запуском

| Риск | Проверка |
|---|---|
| Рекурсия в компенсации (уведомление на свою же правку) | `open build/Claimp.app`, потянуть границу BPM/Key; приложение не должно подвиснуть, CPU в норме |
| Старое автосохранение сохранило кривые ширины (`ClaimpPlaylistColumns`, `PlaylistController.swift:30`) | `defaults delete <bundle-id> "NSTableView Columns ClaimpPlaylistColumns"` перед первым прогоном, иначе увидишь старое состояние и решишь, что правка не сработала |
| `sizeToFit` убрали - при расширении окна справа появляется дыра | растянуть окно с 500 до 900 pt: Title/Artist должны забрать место, пустоты справа быть не должно (§1.2 блок D: без инварианта «сумма == ширина» расширение не работает) |
| Компенсация упёрлась в minWidth artist/title | сузить окно до 420 pt и тянуть BPM вправо: должно просто перестать тянуться, а не выпихивать Key за край |
| Индикатор сортировки перестал рисоваться (§3.5) | кликнуть по заголовку Year - треугольник должен появиться |
| Риска в заголовке «съедает» правый отступ числа | скриншот `screencapture -x`, смотреть глазами: между цифрой BPM и риской должно быть ~8 pt |
| Смена кегля в ⌘, роняет ширины | поставить крупный кегль и обратно; ширины, выставленные рукой, должны вернуться пропорционально, а не сброситься |

---

## Приложение: что осталось не установленным

- Какое значение `columnAutoresizingStyle` пишет Interface Builder по умолчанию (для Aural и Cog
  атрибут просто отсутствует). Дефолт **класса** - `lastColumnOnly`, это подтверждено
  и `NSTableView.h:170`, и замером `rawValue = 4`.
- Реальное выравнивание числовых колонок в view-based ячейках Cog (в xib оно задано на
  `dataCell`, который для view-based таблиц не используется).
- Поведение Finder, Music.app и Rekordbox при протяжке разделителя - исходников нет,
  в HIG правила нет.

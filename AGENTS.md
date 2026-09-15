# Ранбук исполнителя Claimp (читать целиком до первой команды)

Проект: нативный macOS-плеер, SwiftPM без Xcode-проекта, Swift 6.4 (SDK macOS 27 из Command Line Tools), macOS 27+. Корень: worktree этого репозитория.
Документы: `SPEC.md` (контракты и поведение), `DECISIONS.md` (решения владельца, последние блоки главнее), `PLAN.md`, спека твоей задачи в `.scratch/work/tasks/`.

`$MAIN` ниже = главный checkout репозитория, не твой worktree: `MAIN=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")`. Worktree удаляется после мержа вместе со своим `.scratch`, поэтому улики и логи гейта живут только в `$MAIN/.scratch/work`.

## Команды (только эти, из корня worktree)
| Что | Команда | Норма |
|---|---|---|
| Сборка | `make build` (или `DEVELOPER_DIR=/Library/Developer/CommandLineTools swift build`) | exit 0, 0 warnings, ~40 с тёплая |
| Тесты | `make test` (или `DEVELOPER_DIR=... swift test --filter <Suite>`) | exit 0; при нагрузке машины `--no-parallel` |
| Приложение | `bash scripts/build-app.sh` → `build/Claimp.app` | exit 0 |
| Запуск | `open build/Claimp.app` (плейлист восстановится из базы) или `open -a build/Claimp.app <папка с треками>` | окно ~500×760 |
| Скриншот | `sleep 5; screencapture -x $MAIN/.scratch/work/evidence/<задача>/<имя>.png` (главный checkout, не worktree: worktree удаляется после мержа вместе со своим .scratch) | смотреть самому (Read), сравнивать с эталоном |
| Остановка | `pkill -x Claimp` | всегда в конце |
| Лог гейта | каждая проверка отдельной строкой, вывод в `$MAIN/.scratch/work/gates/<задача>.log` (главный checkout); на проверочных командах пайпы (`\| tail`, `\| grep`) запрещены | |

Корпус для живых проверок: папка с треками на машине исполнителя (в репозиторий не входит; живые тесты анализатора берут её из `CLAIMP_CORPUS=~/Music/deemix make test`, без переменной пропускаются), один длинный трек ~60 мин для проверки памяти и волны, фикстуры с тегами - `Tests/Fixtures/`.

## Порядок работы
1. `git worktree add <репо>/.worktrees/<задача> -b <задача> master`, работать только там. Главный checkout и чужие worktree не трогать.
2. Периметр файлов из спеки задачи: вне него ничего не менять. Нужно чужое - `BLOCKED` с точной просьбой.
3. Сначала красный тест на шов, потом правка. Тесты поведенческие, 1 happy + 1 failure; тест, который зелёный при любой реализации, не считается.
4. Коммиты атомарные, без атрибуции ИИ. Перед сдачей `git rebase master`, потом полный `swift build` и `swift test`.
5. Сдача: последняя команда `herdr agent prompt fable-dj "<ЗАДАЧА> DONE|BLOCKED: SHA, ветка, суть 3 строки, что не проверено"`. Без неё задача не сдана.
6. Обрыв API (`Request timed out`), контекст > 60 %: сразу `git add -A && git commit -m "<задача> WIP"` в worktree, потом продолжать. Незакоммиченное после обрыва - потерянное время.

## Запрещено
- `orca` (любые команды), Computer Use, открытие любых приложений, кроме `build/Claimp.app` (Xcode GUI, сторонние приложения, браузер).
- Файлы вне репо: `/tmp`, `~/dev`, `~/Downloads`. Всё рабочее - в `$MAIN/.scratch/work/{tasks,qa,evidence,reviews,gates}` главного checkout, не в `.scratch` своего worktree (он исчезает с worktree).
- Правки `Package.swift`, `scripts/`, `Info.plist`, чужих модулей без слова в спеке. Субагенты. Скачивание моделей и пакетов сверх `Package.resolved`.
- Литералы цветов/размеров вне `Sources/App/Theme.swift` и `WaveformStyle`; оранжевый/белый (`#BD7A36 #D29046 #D8D8D8 #FFFFFF`).
- Фолбэки и тихие пропуски: обязательные данные без дефолтов, ошибка с исходной причиной наверх.
- Лишнее: файлы «на будущее», рефакторинг соседей, новые зависимости, полный прогон чужих сьютов по десять раз.

## Что где
- `Sources/Core` модель, сканер (SFBAudioEngine/TagLib), `PlayedStore` (GRDB), фильтр/сортировка/навигатор.
- `Sources/Playback` `PlayerEngine` (SFBAudioEngine), `NowPlayingBridge` (медиаклавиши).
- `Sources/Waveform` `PCMReader` → `BandSplitter` → `WaveformAnalyzer` → `WaveformCache` → `WaveformView`/`WaveformResampler`, параметры в `WaveformStyle`.
- `Sources/App` окно, шапка, таблица, drag-out/drop, `Theme.swift` (все токены цветов и размеров).
- Эталоны владельца (эти png в публичное дерево не входят): `research/aimp-reference.png` (раскладка), `research/owner-size-reference.png` (размер), `research/owner-ref-serato-waveform.png` (волна), `research/owner-ref-neumorphism-dark.png` (только палитра и типографика, стиль плоский), `research/owner-feedback-*.png` (что было плохо).

Не понял спеку - вопрос в BLOCKED, не додумывать. Не смог проверить глазами - написать «не проверено».

## UX-инварианты (владелец, 15.09)
- Длинный текст никогда не расширяет окно/шапку/колонки: обрезка мягкая, край уходит в градиент цвета фона, без многоточия и переноса.
- Drag-out файла работает из двух мест: строка плейлиста и обложка. Волна = только перемотка, drag с волны отменён.
- Шапка при любой ширине: обложка у левого края, текст и транспорт прижаты к обложке; фейдер громкости прилеплен к правому краю; пустота между ними.
- Волна: полный спектр цветов как у Serato (красный → жёлтый → зелёный → синий → фиолетовый), не одна тёплая гамма.

## Тулчейн (с 15.09, анализ BPM/тональности)
- Сборка и тесты только с `DEVELOPER_DIR=/Library/Developer/CommandLineTools` (Swift 6.4, SDK macOS 27 с MusicUnderstanding); Xcode 26.6 не подходит, обновлять и скачивать ничего не нужно. Makefile и scripts выставляют это сами; вручную: `DEVELOPER_DIR=/Library/Developer/CommandLineTools swift build`.
- Два известных шума этого тулчейна, не код: (1) `external macro implementation type 'TestingMacros...' could not be found` на `swift test`/`swift build --build-tests` - лечится загрузкой плагина в процесс компилятора, это делает `make test` (флаг `-load-plugin-library`, см. Makefile); голый `swift test` не использовать; (2) `ld: warning: search path '/Library/Developer/CommandLineTools/Developer/...' not found` на каждой цели - предупреждения линкера CLT, в норму «0 warnings» не входят.
- Одна точка: `scripts/toolchain.sh` (его `source`-ят все скрипты, Makefile зовёт целью `toolchain`). Нет `MusicUnderstanding.framework` в SDK - остановка с понятной ошибкой до сборки, а не `no such module` посреди компиляции.

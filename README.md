# facefusion-deck-kit

Готовый набор патчей и профилей **поверх чистого** [FaceFusion](https://github.com/facefusion/facefusion) (в т.ч. установка через [Pinokio](https://pinokio.computer/)).

Ориентирован на **Steam Deck / слабый AMD iGPU (DirectML)**, но ставится на любой Windows/Linux с FaceFusion 3.6.x.

> **Не является** форком FaceFusion. Скрипт только накладывает файлы и точечные правки на уже установленную копию.

## Что внутри

| Компонент | Описание |
|-----------|----------|
| **NSFW patch** | `detect_nsfw()` → всегда `False` + отключение hash-проверки `content_analyser` |
| **Pinokio** | `run.js` без `git checkout` (патчи не сбрасываются), меню профилей |
| **Профили** | `facefusion.fast.ini` / `balanced.ini` / `quality.ini` |
| **Трекинг / рот** | `face_selector_mode=one`, `expression_restorer` (Balanced/Quality), мягче detector |

### Профили качества

| Профиль | Назначение | Swapper | Extra |
|---------|------------|---------|--------|
| **Fast** | превью, батарея | inswapper 128 fp16 @ 128 | только swap |
| **Balanced** | обычная работа | inswapper 128 fp16 @ 256 | + expression_restorer |
| **Quality** | финал | hyperswap 256 @ 256 | + expression_restorer + gfpgan, occlusion |

Общее для профилей Deck:

- `execution_providers = directml` (Windows AMD)
- `execution_thread_count = 2–3`
- `video_memory_strategy = strict`
- `system_memory_limit = 8`
- `temp_frame_format = png`
- encode: `libx264` + `ultrafast` / `veryfast`

## Требования

1. Уже установлен **FaceFusion 3.6.x** (рекомендуется **3.6.1**).
2. Вариант A: **Pinokio** → приложение `facefusion-pinokio`.
3. Вариант B: обычный clone FaceFusion + свой Python/venv.
4. Python 3.10+ (для скрипта патча; подойдёт env из Pinokio).

## Установка

### Windows (Pinokio / Steam Deck Windows)

1. Установи FaceFusion в Pinokio как обычно (Install → дождись конца).
2. Скачай этот репозиторий:

```powershell
git clone https://github.com/PinyaGit/facefusion-deck-kit.git
cd facefusion-deck-kit
```

или скачай ZIP → распакуй.

3. Запусти:

```powershell
# авто-поиск C:\pinokio\api\facefusion-pinokio.git
.\apply.ps1

# или явный путь
.\apply.ps1 -Target "C:\pinokio\api\facefusion-pinokio.git"
```

Если PowerShell ругается на политику:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\apply.ps1
```

4. В Pinokio **полностью останови** FaceFusion и запусти снова:
   - **Fast (Deck)** / **Balanced (Deck)** / **Quality (Deck)**

### Linux / SteamOS

```bash
chmod +x apply.sh
./apply.sh
# или
./apply.sh --target "$HOME/pinokio/api/facefusion-pinokio.git"
```

### Без Pinokio (standalone FaceFusion)

```powershell
.\apply.ps1 -Target "D:\facefusion" -SkipPinokio
```

```bash
./apply.sh --target ~/facefusion --skip-pinokio
```

Запуск:

```bash
python facefusion.py run --config-path facefusion.balanced.ini
# или facefusion.fast.ini / facefusion.quality.ini
```

### Опции

| apply.ps1 | apply.sh | Смысл |
|-----------|----------|--------|
| `-SkipNsfw` | `--skip-nsfw` | не трогать NSFW |
| `-SkipProfiles` | `--skip-profiles` | не копировать `.ini` |
| `-SkipPinokio` | `--skip-pinokio` | не трогать `run.js`/`menu.js` |
| `-WhatIf` | `--dry-run` | только проверка |

Перед записью файлы копируются в:

`…/deck-kit-backup/<timestamp>/`

## Что именно меняется

```
<pinokio-app>/
  run.js                          ← overlay
  menu.js                         ← overlay
  facefusion/
    facefusion.ini                ← = balanced
    facefusion.fast.ini           ← new
    facefusion.balanced.ini       ← new
    facefusion.quality.ini        ← new
    facefusion/
      content_analyser.py         ← patch detect_nsfw
      core.py                     ← patch common_pre_check hash
```

Патч NSFW идемпотентный (повторный запуск безопасен).

## После Update / Reset в Pinokio

Pinokio Update/Reset или ручной `git checkout` внутри `facefusion/` **сотрёт** правки.

Снова:

```powershell
.\apply.ps1 -Target "C:\pinokio\api\facefusion-pinokio.git"
```

`run.js` из набора **отключает** шаг `git checkout` при каждом Run — иначе NSFW и ini слетают на старте.

## Советы по Steam Deck

- Для рта/мимики: **Balanced** или **Quality** (`expression_restorer`).
- Прыжки «своп ↔ оригинал» при повороте: в профилях стоит `face_selector_mode = one` (один человек в кадре).  
  Несколько людей → в UI: mode **reference**, **Reference Face Distance ~0.55–0.65**.
- Quality первый раз качает hyperswap / gfpgan / live_portrait — нужен интернет.
- Держи Deck на зарядке + Performance mode для длинных роликов.

## Структура репозитория

```
facefusion-deck-kit/
├── README.md
├── LICENSE
├── apply.ps1                 # Windows installer
├── apply.sh                  # Linux/macOS installer
├── scripts/
│   └── patch_nsfw.py         # точечный патч Python-исходников
└── overlay/
    ├── pinokio/
    │   ├── run.js
    │   └── menu.js
    └── facefusion/
        ├── facefusion.ini
        ├── facefusion.fast.ini
        ├── facefusion.balanced.ini
        └── facefusion.quality.ini
```

## Совместимость

| Версия FaceFusion | Статус |
|-------------------|--------|
| 3.6.1 | протестировано |
| 3.5–3.6.x | обычно ок (патч по сигнатурам) |
| 4.x | может сломаться — проверь `patch_nsfw.py` |

## Откат

```powershell
# пример: вернуть файлы из бэкапа
$b = "C:\pinokio\api\facefusion-pinokio.git\deck-kit-backup\<timestamp>"
Copy-Item "$b\facefusion__content_analyser.py" "C:\pinokio\api\facefusion-pinokio.git\facefusion\facefusion\content_analyser.py"
Copy-Item "$b\facefusion__core.py" "C:\pinokio\api\facefusion-pinokio.git\facefusion\facefusion\core.py"
# и т.д. для run.js / menu.js / ini
```

Либо Pinokio → **Reset** / переустановка приложения.

## Дисклеймер

- Используй только с контентом и лицами, на которые у тебя есть права.
- NSFW-фильтр отключается **осознанно** — ответственность на тебе.
- Соблюдай лицензию FaceFusion и законы своей страны.
- Авторы kit не связаны с facefusion.io / официальным проектом.

## Репозиторий

**https://github.com/PinyaGit/facefusion-deck-kit**

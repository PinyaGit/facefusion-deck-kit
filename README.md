# facefusion-deck-kit

Готовый набор патчей и профилей **поверх чистого** [FaceFusion](https://github.com/facefusion/facefusion).

Ориентирован на **Steam Deck**. Два пути:

1. **Нативно на SteamOS** (рекомендуется, если нет Pinokio) — `install-native.sh`
2. **Поверх Pinokio / уже установленного FaceFusion 3.6.x** — `apply.sh` / `apply.ps1`

> **Не является** форком FaceFusion. Скрипты ставят официальный 3.6.1 в `$HOME` и/или накладывают файлы на уже установленную копию.

## Что внутри

| Компонент | Описание |
|-----------|----------|
| **Native SteamOS** | Miniforge + Python 3.12 + FaceFusion 3.6.1 + ярлык, всё в `$HOME`, без sudo и Pinokio |
| **NSFW patch** | `detect_nsfw()` → всегда `False` + отключение hash-проверки `content_analyser` |
| **Pinokio** | `run.js` без `git checkout` (патчи не сбрасываются), меню профилей |
| **Профили** | `facefusion.fast.ini` / `balanced.ini` / `quality.ini` |
| **Трекинг / рот** | `face_selector_mode=one`, `expression_restorer` (Balanced/Quality), мягче detector |

### Профили качества

| Профиль | Назначение | Swapper | Extra |
|---------|------------|---------|-------|
| **Fast** | превью, батарея | inswapper 128 fp16 @ 128 | только swap |
| **Balanced** | обычная работа | inswapper 128 fp16 @ 256 | + expression_restorer |
| **Quality** | финал | hyperswap 256 @ 256 | + expression_restorer + gfpgan, occlusion |

Общее для профилей Deck:

- `video_memory_strategy = strict`
- `system_memory_limit = 8`
- `temp_frame_format = png`
- encode: `libx264` + `ultrafast` / `veryfast`
- **Windows / Pinokio:** `execution_providers = directml`, 2 потока
- **Linux / SteamOS native:** `apply.sh` сам ставит `cpu`, 4 потока (DirectML на Linux нет)

## Нативно на Steam Deck (SteamOS)

Нужны `git`, `curl`, `ffmpeg` (на SteamOS они уже есть). Интернет. Место в `/home` (~3 ГБ на env + модели при первом запуске). Корневую систему скрипт **не трогает**.

```bash
git clone https://github.com/PinyaGit/facefusion-deck-kit.git
cd facefusion-deck-kit
chmod +x install-native.sh
./install-native.sh
```

Повторный запуск безопасен: недостающее доставит, overlay наложит снова.

Запуск:

- ярлык **FaceFusion** на рабочем столе / в меню KDE
- или:

```bash
facefusion              # меню профилей, по умолчанию Balanced
facefusion fast
facefusion quality
```

Первый старт UI качает модели (сотни МБ) — нужен интернет, лучше на зарядке.

Переменные:

| Env / флаг | Смысл | По умолчанию |
|------------|--------|--------------|
| `FACEFUSION_HOME` / `--prefix` | куда класть FaceFusion | `~/facefusion` |
| `CONDA_ROOT` / `--conda-root` | Miniforge | `~/miniforge3` |
| `--force-deps` | заново прогнать `install.py` | выкл |
| `--skip-desktop` | не писать `.desktop` и symlink | выкл |

### GPU на SteamOS

DirectML — это **Windows**. На SteamOS APU Van Gogh / Sephiroth официальный ROCm не ставится в пользовательский home без контейнера, поэтому native-установщик использует **CPU onnxruntime**.

Картинки рабочие. Видео медленнее, чем на Windows+DirectML: Fast/Balanced для повседневки, Quality — финал/кадры. Держи Deck на зарядке + Performance.

## Windows (Pinokio / Steam Deck Windows)

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

## Linux Pinokio / уже есть FaceFusion

```bash
chmod +x apply.sh
./apply.sh
# или
./apply.sh --target "$HOME/pinokio/api/facefusion-pinokio.git"
```

Standalone:

```powershell
.\apply.ps1 -Target "D:\facefusion" -SkipPinokio
```

```bash
./apply.sh --target ~/facefusion --skip-pinokio
```

Запуск без лаунчера:

```bash
python facefusion.py run --open-browser --config-path facefusion.balanced.ini
```

### Опции apply

| apply.ps1 | apply.sh | Смысл |
|-----------|----------|--------|
| `-SkipNsfw` | `--skip-nsfw` | не трогать NSFW |
| `-SkipProfiles` | `--skip-profiles` | не копировать `.ini` |
| `-SkipPinokio` | `--skip-pinokio` | не трогать `run.js`/`menu.js` |
| `-WhatIf` | `--dry-run` | только проверка |

Перед записью файлы копируются в `…/deck-kit-backup/<timestamp>/`.

Патч NSFW идемпотентный (повторный запуск безопасен).

## После Update / Reset

Pinokio Update/Reset или `git checkout` внутри `facefusion/` **сотрёт** правки.

```powershell
.\apply.ps1 -Target "C:\pinokio\api\facefusion-pinokio.git"
```

```bash
~/facefusion/reapply-deck-kit.sh
# или
./apply.sh --target ~/facefusion --skip-pinokio
```

`run.js` из набора **отключает** шаг `git checkout` при каждом Run в Pinokio — иначе NSFW и ini слетают на старте.

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
├── install-native.sh         # SteamOS / Linux: полная нативная установка
├── apply.ps1                 # Windows overlay (Pinokio / standalone)
├── apply.sh                  # Linux overlay + CPU-адаптация ini
├── scripts/
│   ├── patch_nsfw.py         # точечный патч Python-исходников
│   └── run-facefusion.sh     # лаунчер профилей (копируется в ~/facefusion)
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

## Откат

```powershell
# пример: вернуть файлы из бэкапа
$b = "C:\pinokio\api\facefusion-pinokio.git\deck-kit-backup\<timestamp>"
Copy-Item "$b\facefusion__content_analyser.py" "C:\pinokio\api\facefusion-pinokio.git\facefusion\facefusion\content_analyser.py"
Copy-Item "$b\facefusion__core.py" "C:\pinokio\api\facefusion-pinokio.git\facefusion\facefusion\core.py"
# и т.д. для run.js / menu.js / ini
```

Нативно: удали `~/facefusion` и при желании conda-env `facefusion` / `~/miniforge3`. Либо Pinokio → **Reset**.

## Дисклеймер

- Используй только с контентом и лицами, на которые у тебя есть права.
- NSFW-фильтр отключается **осознанно** — ответственность на тебе.
- Соблюдай лицензию FaceFusion и законы своей страны.
- Авторы kit не связаны с facefusion.io / официальным проектом.

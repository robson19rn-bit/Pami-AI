# Licencje

## Aplikacja „Czytam Sam”

Kod źródłowy aplikacji oraz materiał dydaktyczny w `assets/content/` (litery, opisy głosek, sylaby, wyrazy,
zdania, czytanki, pytania) zostały napisane od zera na potrzeby tego projektu i są udostępnione na licencji **MIT**
(treść poniżej). Aplikacja nie zawiera cudzych nagrań, obrazów ani fontów (używa systemowego fontu Androida).

```
MIT License

Copyright (c) 2026 Czytam Sam – autorzy

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of
the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

## Zależności dołączane do APK

Licencje sprawdzone w plikach `LICENSE` pobranych pakietów (wersje z `pubspec.lock`). Pełne teksty licencji
wszystkich pakietów Dart/Flutter są wyświetlane w aplikacji: *Ustawienia → Informacje → Licencje*.

| Komponent | Wersja | Licencja | Rola |
|---|---|---|---|
| Flutter SDK (framework + silnik) | 3.50.0 | BSD-3-Clause | interfejs |
| material_ui, cupertino_ui | 1.11.1 / 1.1.x | BSD-3-Clause | komponenty Material |
| flutter_localizations, intl | SDK / 0.20.x | BSD-3-Clause | polska lokalizacja |
| sqflite, sqflite_common, sqflite_android | 2.4.6 / 2.5.17 / 2.4.6 | BSD-2-Clause | baza SQLite |
| path, path_provider | 1.9.1 / 2.1.6 | BSD-3-Clause | ścieżki plików |
| crypto | 3.0.8 | BSD-3-Clause | suma kontrolna kopii |
| flutter_tts | 4.2.5 | MIT | systemowy lektor Androida |
| permission_handler (+ _android) | 13.0.2 | MIT | uprawnienie mikrofonu |
| file_picker (+ android_file_picker) | 13.4.0 | MIT | eksport/import kopii, import modelu |
| Vosk Android (`com.alphacephei:vosk-android`) | 0.3.75 | Apache-2.0 (wg POM w Maven Central) | lokalne rozpoznawanie mowy |
| JNA (`net.java.dev.jna:jna`, aar) | 5.18.1 | Apache-2.0 lub LGPL-2.1 (licencja podwójna; używamy na Apache-2.0) | most JNI dla Vosk |

Tylko do testów (nie trafiają do APK): `flutter_test` (BSD-3), `sqflite_common_ffi` 2.4.7 (BSD-2), `sqlite3` 3.9.x (MIT),
`flutter_lints` 6.0.0 (BSD-3).

## Zasoby NIEdołączane do APK

| Zasób | Licencja | Uwagi |
|---|---|---|
| Model `vosk-model-small-pl-0.22` | Apache-2.0 – według listy modeli Vosk | Opiekun pobiera go sam i importuje z pliku. **W tej sesji nie udało się otworzyć strony alphacephei.com (host zablokowany przez politykę sieci), więc licencji modelu nie zweryfikowano bezpośrednio u źródła** – sprawdź ją na stronie przed pobraniem. |
| Polskie głosy TTS | licencje producenta systemu/silnika | Aplikacja używa głosu zainstalowanego w Androidzie; nie dołącza nagrań. |

## Projekty przejrzane, z których NIE skopiowano kodu

| Projekt | Licencja | Decyzja |
|---|---|---|
| github.com/ajanec01/phonix | MIT (plik LICENSE, © 2025 Aron Janecki) | Przejrzany jako możliwy szkielet. To angielski program (Letters and Sounds), większość ekranów to zaślepki (12 linii), brak trwałej bazy i modelu umiejętności. **Napisano czystą aplikację; nie skopiowano kodu ani materiałów**, więc nie ma obowiązku dołączania jego noty. |
| github.com/minormending/learn-letters | **brak pliku licencji** | Wyłącznie inspiracja koncepcyjna (oddzielenie rozpoznawania od wypowiadania, brak obrazka podczas dekodowania, kontrola startu TTS, nie dopisywać samogłoski do spółgłoski). **Nie skopiowano kodu ani nagrań.** |

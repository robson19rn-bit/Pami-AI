# Raport odbioru – „Czytam Sam” 1.0

Data: 2026-11-18. Środowisko wykonawcze: kontener Linux w chmurze, Flutter 3.50.0 / Dart 3.14.0, **bez urządzenia
z Androidem i bez Android SDK**.

Legenda: **PASS** – sprawdzone, dowód podany; **FAIL** – nie spełnione; **NOT_TESTED** – zaimplementowane,
ale nie dało się sprawdzić w tym środowisku (powód podany). Rozróżniam „kompiluje się / przechodzi testy”
od „sprawdzone na prawdziwym urządzeniu” – **na urządzeniu nie sprawdzono niczego**.

Dowody: `WYNIKI_TESTOW.txt` (pełny wydruk: walidacja materiału, `flutter analyze` – 0 problemów,
`flutter test` – **57/57 testów zaliczonych**, w tym przegląd wszystkich ekranów i typów zadań w 3 rozmiarach: telefon, tablet poziomo i pionowo – bez błędów układu), pliki testów `test/a01…a08_*.dart`.

## A. Najważniejsze: APK

| Wymóg | Wynik | Dowód / powód |
|---|---|---|
| Instalowalny APK | **PASS (zbudowany)** / NOT_TESTED (urządzenie) | GitHub Actions, uruchomienie nr 2 (`czytam-sam-build-2`): analiza, testy, budowa i weryfikacja (`apksigner verify`, identyfikator `pl.czytamsam.app`, brak uprawnienia INTERNET) zakończone sukcesem; plik `CzytamSam-N.apk` w zakładce *Releases*. Pierwsze uruchomienie nie powiodło się (zależności wymagały `compileSdk 37`) – poprawione. Nie instalowano na fizycznym urządzeniu. |
| Workflow CI (pub get, analiza, testy, APK, artefakt) | **PASS** | uruchomienie nr 2 zakończone sukcesem (wszystkie kroki zielone), artefakt + wydanie z plikiem APK. |
| Kod natywny (Kotlin, kanał Vosk) | **PASS (kompilacja)** / NOT_TESTED (urządzenie) | `MainActivity.kt` skompilowany kotlinc 2.2.20 przeciw oficjalnym artefaktom: `vosk-android 0.3.75`, `jna 5.18.1` (Maven Central), `flutter_embedding_release` (silnik 3.50.0), `android-all 16` (Robolectric, Maven Central); dla `androidx.lifecycle` użyto tylko pustej zaślepki typu do sprawdzenia typów. |

## B. Wymagania nieprzekraczalne (pkt 1)

| Wymóg | Wynik | Dowód |
|---|---|---|
| 100% po polsku (UI, komunikaty, wymowa) | PASS (UI/teksty) / NOT_TESTED (brzmienie lektora) | Wszystkie teksty w `lib/ui`, materiał w `assets/content`; `locale: pl_PL`. Brzmienie zależy od głosu w systemie – ekran „Sprawdzenie lektora”. |
| Brak opłat, reklam, zakupów, kont, telemetrii, płatnych API | PASS | test (24) `a08`: brak takich bibliotek w `pubspec.lock`/`pubspec.yaml`, brak wywołań sieciowych w `lib/` i `MainActivity.kt`. |
| Offline, brak wysyłania głosu/danych | PASS (kod) / NOT_TESTED (urządzenie) | test (20) `a08`: cały przebieg (materiał, sesja, zapis, raport, eksport/import) przy zablokowanej sieci – 0 prób połączeń; manifest bez `INTERNET` (test 24c); Vosk działa lokalnie; nagrania nie są zapisywane (dźwięk tylko w pamięci rozpoznawania). |
| Flutter/Dart, Android 13/14, telefon+tablet | PASS (kod) / NOT_TESTED (urządzenie) | `minSdk 24`, `targetSdk 36`; układ responsywny (`ConstrainedBox`, `Wrap`). |
| Duże litery, zero presji czasu | PASS | brak timerów w sesji (`SessionController` nie zmienia pytania samoczynnie); litery 64–160 pt; test (23b): przyciski ≥ 96 dp. Czas tylko w raporcie (test „czas odpowiedzi nie wpływa na ocenę”, `a02`). |
| Mikrofon bez udawania | PASS (logika) | testy (04)(05)(06), `a03`. |
| Pełna dostępność materiałów | PASS | brak blokad płatnych; ręczne odblokowanie etapów przez opiekuna. |
| Dane po zamknięciu i aktualizacji | PASS (logika) / NOT_TESTED (aktualizacja APK na urządzeniu) | testy (17)(22), `a05`; stały `applicationId`; stały klucz testowy. |

## C. Ścieżka nauki (pkt 3) i materiał (pkt 4)

| Wymóg | Wynik | Dowód |
|---|---|---|
| A. Diagnoza: znana/nieznana/mylona, osobno nazwa i głoska | PASS (logika) | `DiagnosisScreen`, `AppState.recordDiagnosis`; scenariusz `a06` (litery mylone trafiają do ćwiczeń, nieznane nie). |
| B–E. Ze słuchu, z wypowiedzią, samodzielne przypominanie, utrwalanie | PASS | T1–T4 w `TaskBuilder`; odłożone ponowne sprawdzenie po błędzie (test w `a03`); powtórki w kolejnych dniach (09)(10). |
| F–G. Synteza, sylaby, wyrazy, zdania, czytanki | PASS (logika) | T5/T6/T7; odblokowanie (14)(15); scenariusz `a06`: sylaby „ma, la, mo, lo, am, om, al, ol” po opanowaniu M/A/L/O. |
| H. Powrót do trudnych elementów po awansie | PASS | stan „do powtórzenia” (09), priorytet koszyka zaległych (10). |
| Nazwa litery ≠ głoska; bez dopisywania samogłoski | PASS | osobne umiejętności (02); instrukcja dla opiekuna „bez dodawania y”; lektor nie wymawia pojedynczych głosek. |
| 32 litery, wielkie/małe, nazwy, wymowa, przykłady | PASS | test (01) `a01`. |
| Dwuznaki i trójznak osobno (ch, cz, dz, dź, dż, rz, sz) + zmiękczenia | PASS | `letters.json → graphemes`; tokenizator; test w `a01`. |
| Tabela grafem → nazwa → głoski → kontekst → przykłady; brak reguły „1 litera = 1 dźwięk” | PASS | `letters.json` (`sounds[].context`); test w `a01` (ą, ę, u/ó, rz/ż, ch/h). |
| ≥ 60 sylab, ≥ 100 wyrazów, ≥ 30 zdań, ≥ 10 czytanek z oznaczeniami | PASS | 117 sylab, 136 wyrazów (w puli), 33 zdania, 10 czytanek; każda jednostka: grafemy, poziom, cel, wymowa; walidator: 0 błędów. |
| Niepewne pozycje wyłączone z puli | PASS | „gałąź” oznaczona `needsReview` – test w `a01`. |
| Weryfikacja językowa przez specjalistę | **NOT_TESTED** | Materiał przygotowany i sprawdzony automatycznie oraz ręcznie przez autora; **nie był sprawdzony przez logopedę/polonistę** – zalecane przed użyciem. |

## D. Zadania i dźwięk (pkt 5–6)

| Wymóg | Wynik | Dowód |
|---|---|---|
| T1–T7 z rzeczywistą interakcją | PASS (logika + widżety) | `session.dart`, `lesson_screen.dart`; testy `a03`, `a07`. |
| Powtórz polecenie / podpowiedź / przerwij / wróć później | PASS | przyciski na ekranie zadania; testy „Wróć później”, (07). |
| Podpowiedź tylko na życzenie lub po błędzie; po podpowiedzi ≠ samodzielnie | PASS | test (07) w `a02` i `a03`. |
| Ocena pierwszej próby, bez nabijania kliknięciami | PASS | test „wielokrotne klikanie…” `a03`, (07b) `a02`. |
| Po błędzie: spokojne wyjaśnienie, prawidłowa odpowiedź, odłożone sprawdzenie | PASS | `Feedback` z prawidłową odpowiedzią; ponowne sprawdzenie 4 zadania później, oznaczone jako „po pokazaniu odpowiedzi”. |
| Weryfikacja, że polecenie zabrzmiało; brak kontynuacji „ze słuchu” przy ciszy | PASS (logika + widżet) / NOT_TESTED (prawdziwy TTS) | test (19) `a03`, `a07`: komunikat, zablokowane odpowiedzi; `FlutterTtsOutput` czeka na potwierdzenie startu (limit 2,5 s). |
| Głoski tylko ze zweryfikowanych nagrań | PASS (przez wyłączenie) | Brak legalnych nagrań głosek → głoski **wymawia opiekun**, lektor nigdy. |
| 4 wyniki mikrofonu (poprawnie/niepoprawnie/nic/niepewne) | PASS | `classifyAsr`, testy (04)(06). |
| Panel opiekuna: Poprawnie / Jeszcze nie / Powtórz / Nie można ocenić | PASS | `_guardianRating` (otwierany przytrzymaniem); test (03b). |
| Brak uprawnienia / modelu → jawny tryb opiekuna | PASS | test (05); komunikaty w UI. |
| Pominięcie głosu zalicza tylko wskazanie | PASS | test (03) `a03`. |
| Brak zapisu surowych nagrań | PASS (kod) | `MainActivity.kt` nie zapisuje audio; brak pól na nagrania w bazie i kopii (`containsVoiceRecordings: false`, test 18). |
| Rzetelność Vosk na krótkich głoskach | **NOT_TESTED** | Nie zakładamy jej – litery/głoski zawsze ocenia opiekun; tryb automatyczny tylko dla sylab/wyrazów i domyślnie wyłączony. |

## E. Silnik adaptacyjny (pkt 7)

| Wymóg | Wynik | Dowód |
|---|---|---|
| Zapisywane pola (próby, samodzielne, po podpowiedzi, błędy, brak audio, ocena opiekuna, daty, typ, pomyłki, czas) | PASS | `Attempt`, `SkillStats`; test (16). |
| Stany NOWE→…→DO POWTÓRZENIA | PASS | (02)(08)(09). |
| Deterministyczny dobór: priorytet trudnych, domieszka opanowanych, losowanie układów, bez powtórzeń celu, równoważenie pozycji, pary mylone | PASS | (10)(10b: 12/5/3 przy 20 zadaniach = 60/25/15)(11)(11b)(12), test liczby opcji i dystraktorów. |
| Opcje 2/3/4/6 zależnie od umiejętności | PASS | `optionCountFor`, test w `a04`. |
| Kryteria opanowania (10 prób, 80%, 5/4 dla mowy, 2 sesje, późniejszy termin), konfigurowalne | PASS | (08)(09)(09b); edytor w Ustawieniach. |
| Wykluczenie prób po podpowiedzi i nierozpoznanej mowy | PASS | test „wykluczone z licznika…” `a02`. |
| Etap wg konkretnych głosek, bez blokowania całości; ręczne odblokowanie „bez zaliczenia” | PASS | (14)(15), (21). |
| Scenariusz syntetycznego dziecka | PASS | `a06`: 20 liter częściowo znanych, B/D/P mylone (85 pomyłek w mapie), brak awansu B/D/P, pierwsze sylaby 9. dnia, M/A/L/O 13. dnia, utrwalanie w kolejnych dniach. |

## F. Interfejs (pkt 8)

| Wymóg | Wynik | Dowód |
|---|---|---|
| Ekran startowy: Uczę się / Moje postępy / Ustawienia | PASS | test (23) `a07`. |
| Pierwsze uruchomienie: lektor, głośność, mikrofon, sposób oceny, diagnoza | PASS (kod) / NOT_TESTED (urządzenie) | `setup_screen.dart`. |
| Ekran zadania bez rozpraszaczy, bez odliczania | PASS | `lesson_screen.dart`. |
| Podsumowanie: pochwała wysiłku, bez procentów i rankingów | PASS | `SummaryScreen`. |
| Panel opiekuna za bramką; wszystkie wymienione widoki; bez pustych wykresów | PASS | `guardian_panel.dart`; testy panelu w `a07` (komunikat „Brak historii” zamiast pustego wykresu). |
| Wygląd: własna ikona (adaptacyjna + ikona motywu Androida 13 + PNG), ekran startowy w kolorach aplikacji | PASS (zasoby) / NOT_TESTED (launcher na urządzeniu) | `res/mipmap-anydpi-v26/ic_launcher.xml`, `res/drawable/ic_launcher_*.xml`, `res/mipmap-*/ic_launcher.png`. |
| Test na tablecie | **NOT_TESTED** | brak sprzętu; ekrany sprawdzone renderowaniem w rozmiarach telefonu i tabletu (test a09). |

## G. Dane (pkt 9) i testy obowiązkowe (pkt 11)

| Test | Wynik | Plik |
|---|---|---|
| (01) 32 litery, wielkie/małe, diakrytyki | PASS | a01 |
| (02) niezależne stany | PASS | a02 |
| (03) wskazanie bez wypowiedzi ≠ pełna umiejętność | PASS | a02, a03 |
| (04) hałas ≠ wypowiedź | PASS | a03 |
| (05) brak mikrofonu ≠ fikcyjne oceny | PASS | a03 |
| (06) niepewny ASR → powtórzenie/opiekun | PASS | a03 |
| (07) po podpowiedzi ≠ samodzielnie | PASS | a02, a03 |
| (08) trafienia w jednej sesji ≠ opanowanie | PASS | a02 |
| (09) trwałość w późniejszych sesjach | PASS | a02 |
| (10) powtórki mają pierwszeństwo, utrwalanie zostaje | PASS | a04 |
| (11) zrównoważone pozycje | PASS | a04 |
| (12) brak bezpośredniego powtórzenia celu | PASS | a04 (50 ziaren losowania) |
| (13) odrębne wyniki typów ćwiczeń | PASS | a02 |
| (14) sylaby wg głosek, nie całego alfabetu | PASS | a04 |
| (15) wyrazy/zdania bez nieoznaczonych elementów | PASS | a04 |
| (16) raport bez zacierania różnic | PASS | a05 |
| (17) postęp po restarcie | PASS (zamknięcie i ponowne otwarcie bazy) / NOT_TESTED (restart procesu na urządzeniu) | a05 |
| (18) eksport/import bez duplikatów, wykrycie uszkodzenia | PASS | a05 |
| (19) utrata polskiego głosu – komunikat, bez udawania | PASS | a03, a07 |
| (20) tryb samolotowy | PASS (symulacja braku sieci + brak uprawnienia INTERNET) / NOT_TESTED (urządzenie) | a08 |
| (21) działania opiekuna nie nadpisują prób | PASS | a05 |
| (22) migracja danych przy aktualizacji | PASS (migracja schematu v1→v2) / NOT_TESTED (instalacja APK na APK) | a05 |
| (23) duże obszary dotyku, kontrast | PASS (wytyczne Fluttera: androidTapTarget, labeledTapTarget, textContrast) | a07 |
| (24) brak reklam/telemetrii/logowania/płatnych wywołań | PASS | a08 |
| Atomowe zapisy, rozdzielenie treści i postępów, reset dwuetapowy | PASS | zapis próby = pojedynczy INSERT natychmiast; import w transakcji; treść w `assets`, postępy w SQLite; reset: dialog + wpisanie „USUŃ”. |

## H. Pliki wynikowe (pkt 13)

| Plik | Stan |
|---|---|
| Kod Flutter/Dart + `pubspec.yaml` | gotowe – `czytam_sam/` |
| Materiał JSON + walidator | gotowe – `assets/content/*.json`, `lib/content/validator.dart`, `tool/validate_content.dart` |
| Audio | brak nagrań (świadomie – brak legalnych, zweryfikowanych nagrań głosek); instrukcja konfiguracji lektora i modelu: `README_PL.md` |
| Testy i wyniki | `test/`, `WYNIKI_TESTOW.txt` |
| `.github/workflows/android.yml` | gotowe (w katalogu głównym repozytorium) |
| APK | zbudowany przez GitHub Actions – zakładka *Releases* repozytorium |
| `README_PL.md`, `LICENSES.md`, `RAPORT_ODBIORU.md` | gotowe |

## I. Znane ograniczenia i zadania naprawcze

1. **APK nie był jeszcze uruchomiony na prawdziwym tablecie** – zgłoszone uwagi z pierwszego użycia należy przekazać do poprawy.
2. **Klucz podpisu jest jawny (testowy)** – stały, ale publiczny. Przed szerszym użyciem: prywatny klucz w GitHub
   Secrets (instrukcja w `README_PL.md`, rozdz. 7) i jednorazowe przeniesienie danych eksportem/importem.
3. **Brak nagrań głosek** – zadania z głoskami wymagają opiekuna. W trybie „dziecko ćwiczy samo” umiejętności
   głoskowe nie rosną, więc sylaby odblokowują się tylko dzięki sesjom z opiekunem. Naprawa: nagrać legalnie
   (np. logopeda) krótkie głoski (ok. 40 nagrań) i dodać jako zasoby.
4. **Vosk nie sprawdzony na urządzeniu** (zużycie pamięci, czas ładowania modelu ~50 MB, obecność nazw liter
   w słowniku modelu small-pl). Słowa spoza słownika są ignorowane przez Vosk – wtedy wynik jest „niepewny”
   i decyduje opiekun. Licencji modelu nie zweryfikowano u źródła (host zablokowany).
5. **Lektor**: krótkie nazwy liter (a, e, i, o, u, ą, ę) mogą być czytane niejednoznacznie – oznaczone w danych
   (`ttsRisk`), opiekun może je oznaczyć jako „czyta źle” (wtedy polecenie czyta opiekun).
6. **Materiał** wymaga przeglądu logopedy/polonisty (szczególnie wymowa z ubezdźwięcznieniem i nosówkami).
7. Diagnoza obejmuje 32 litery (nazwa + głoska); dwuznaki i zmiękczenia nie mają osobnej diagnozy – wchodzą,
   gdy opanowane są litery składowe.
8. `allowBackup=false` – świadomie wyłączona automatyczna kopia Google (dane nie opuszczają urządzenia);
   przenoszenie danych tylko przez eksport/import.
9. Flutter 3.50.0 jest świeżym wydaniem (9 dni); jeśli CI napotka problem z wtyczkami, zmienić na 3.47.9
   w `android.yml` i `pubspec.lock`.
10. Kreator, panel i ustawienia nie były oglądane na fizycznym ekranie; testy widżetów sprawdzają działanie
    i dostępność, nie estetykę.

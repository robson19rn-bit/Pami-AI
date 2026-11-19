# Czytam Sam – instrukcja

Polska aplikacja na Androida (telefon i tablet) do nauki czytania dla dziecka ok. 7 lat:
litery → głoski → sylaby → wyrazy → zdania → krótkie czytanki.
**Bez reklam, bez opłat, bez kont, bez internetu, bez telemetrii.** Wszystkie dane zostają na urządzeniu.

> Stan na dziś: kod, materiał, testy i automatyczna budowa APK są gotowe.
> Aplikacja **nie była jeszcze uruchomiona na prawdziwym tablecie** – patrz `RAPORT_ODBIORU.md`.

---

## 1. Instalacja na tablecie

1. Na tablecie otwórz stronę z plikiem APK (zakładka **Releases** repozytorium, wpis
   „Czytam Sam – wersja N”, sekcja *Assets*, plik `CzytamSam-N.apk`) i pobierz go.
2. Otwórz pobrany plik. Android zapyta o zgodę na instalację z tego źródła – zezwól (jednorazowo).
3. Po instalacji uruchom **Czytam Sam**.

Wymagania: Android 7.0 lub nowszy (zaprojektowane i testowane logicznie pod Android 13/14), ok. 60 MB miejsca
(+ ok. 80 MB, jeśli zainstalujesz model rozpoznawania mowy).

## 2. Pierwsze uruchomienie (kreator dla opiekuna)

1. **Imię dziecka** – opcjonalne, zostaje tylko na urządzeniu.
2. **Lektor i głośność** – „Odtwórz zdanie testowe”. Jeśli nie słychać polskiego głosu, zainstaluj go w
   *Ustawienia Androida → System → Język → Zamiana tekstu na mowę → Silnik Google → Zainstaluj dane głosowe → polski*
   (pobierz go, aby działał bez internetu). Bez lektora polecenia czyta opiekun – aplikacja to wyraźnie pokazuje.
3. **Mikrofon** – test działa tylko po zainstalowaniu modelu mowy (pkt 4). Bez modelu wypowiedzi ocenia opiekun.
4. **Sposób oceny wypowiedzi** – domyślnie *ocenia opiekun* (zalecane). Tryb automatyczny dotyczy tylko sylab
   i wyrazów i można go włączyć dopiero, gdy test mikrofonu potwierdzi działanie rozpoznawania.
5. **Diagnoza początkowa** – dla każdej litery osobno: czy dziecko zna **nazwę** litery i czy zna jej **głoskę**
   (zna / myli z… / nie zna / nie można ocenić). Można przerwać i wrócić (Ustawienia → Diagnoza).

## 3. Model rozpoznawania mowy (opcjonalny, offline)

Aplikacja używa biblioteki **Vosk** (Apache-2.0), która rozpoznaje mowę wyłącznie na urządzeniu.
Model polskiej mowy nie jest dołączony do APK (ok. 50 MB); instaluje się go raz:

1. Na tablecie pobierz plik **`vosk-model-small-pl-0.22.zip`** ze strony `alphacephei.com/vosk/models`.
2. W aplikacji: **Ustawienia → Rozpoznawanie mowy → Importuj model z pliku ZIP** i wskaż pobrany plik.
3. Wróć do kreatora / ćwiczeń i sprawdź mikrofon („powiedz: mama”).

Ważne, uczciwe ograniczenia:
* Rozpoznawanie **pojedynczych liter i głosek nie jest wiarygodne** – dlatego litery i głoski **zawsze ocenia opiekun**,
  a wynik modelu jest tylko niewiążącą sugestią.
* Samo wykrycie dźwięku nigdy nie zalicza odpowiedzi. Niepewny wynik → „powtórz” albo ocena opiekuna.
  Model nigdy sam nie wystawia oceny „błędnie”.
* Nagrania nie są zapisywane ani wysyłane – dźwięk trafia z mikrofonu prosto do rozpoznawania w pamięci.
* Uprawnienie do mikrofonu jest prośbą tylko przy pierwszym ćwiczeniu głosowym.

## 4. Codzienne korzystanie

* **Uczę się** – dziecko ćwiczy **samo**, a całą lekcję prowadzi **lektor**: czyta polecenia, sylaby
  i wyrazy, a głoski podaje w słowach („Wskaż literę, którą słychać na początku słowa *mama*”), bo w izolacji
  syntezatory wymawiają je błędnie. Litery obecne w słowie i brzmiące tak samo (u/ó, h/ch) nie pojawiają się
  wtedy jako odpowiedzi, więc zadanie jest jednoznaczne.
* Dziecko nadal próbuje mówić (np. „Wskaż literę, a potem powiedz jej nazwę”), ale bez oceniającego taka
  wypowiedź jest tylko ćwiczeniem – zapisuje się jako „nieoceniona” i nie liczy do opanowania.
* **Ocena wypowiedzi z opiekunem** – *Moje postępy → przycisk „Ocena wypowiedzi”*. Kilka minut, tylko zadania
  mówione (nazwy liter, głoski, czytanie sylab i wyrazów); panel **Poprawnie / Jeszcze nie / Powtórz /
  Nie można ocenić** jest od razu otwarty. W zakładce *Etapy i plan* widać, co czeka na ocenę
  (np. głoski rozpoznawane ze słuchu, których wymowy jeszcze nikt nie potwierdził). Bez tej oceny sylaby się
  nie odblokują – to świadoma zasada: łączenie głosek wymaga ich poprawnego wymawiania.
* Gdy polski lektor nie działa, aplikacja wyraźnie o tym informuje i polecenia czyta dorosły.
* Na każdym ekranie: **Powtórz**, **Podpowiedź** (tylko na życzenie lub po błędzie – odpowiedź po podpowiedzi
  nie liczy się jako samodzielna), **Później**, **Przerwij** (postęp zapisuje się na bieżąco).
* Brak odliczania czasu i presji. Lekcja = 12 zadań (ok. 5–10 minut; zmiana w Ustawieniach).
* Typy zadań: T1 Usłysz i wskaż (literę lub głoskę w słowie), T2 Wskaż i powiedz, T3 Zobacz i nazwij,
  T4 Wielka–mała, T5 Które głoski słyszysz (ułóż z kafelków), T6 Przeczytaj na głos, T7 Przeczytaj i odpowiedz.

## 5. Panel opiekuna („Moje postępy”)

Chroniony prostym pytaniem dla dorosłych (mnożenie). Zakładki: **Litery** (każda umiejętność osobno),
**Czytanie** (sylaby, wyrazy, zdania, czytanki), **Mylone** (mapa pomyłek), **Historia** (dziennie i tygodniowo),
**Mowa i podpowiedzi** (mowa potwierdzona vs niepewna, efekt podpowiedzi, korekta oceny), **Etapy i plan**
(postęp do kolejnego etapu, co program planuje ćwiczyć, ręczne odblokowanie etapu – oznaczone „z pomocą,
ręczne, bez zaliczenia”).

Stany każdej umiejętności: nowe → uczone → ćwiczone → opanowane warunkowo → potwierdzone → do powtórzenia.
Domyślne kryteria (do zmiany w Ustawieniach, **nie są normą naukową**): rozpoznanie – min. 10 samodzielnych prób
i ≥ 80% poprawnych w ostatnich 10; mowa – min. 5 prób i ≥ 4 poprawne w ostatnich 5; potwierdzenie w ≥ 2 sesjach
i ≥ 2 różnych dniach. Błąd w kolejnym dniu cofa umiejętność do powtórek. Sylaba jest dostępna, gdy dziecko opanowało
**głoski, z których się składa** (rozpoznanie ze słuchu + samodzielne wypowiedzenie) – nie trzeba znać całego alfabetu.

## 6. Kopia zapasowa i przeniesienie na inny tablet

* **Ustawienia → Kopia zapasowa → Eksportuj do pliku** – zapisuje plik `czytam-sam-kopia-RRRR-MM-DD.json`
  (historia prób, sesje, ustawienia; bez nagrań głosu). Plik ma sumę kontrolną.
* **Importuj z pliku** – aplikacja najpierw sprawdza plik (uszkodzony zostanie odrzucony), a potem dopisuje
  brakujące zdarzenia. Ponowny import tego samego pliku niczego nie dubluje.
* **Reset profilu** wymaga dwóch potwierdzeń (w tym wpisania słowa USUŃ).

## 7. Aktualizacje i podpis APK (ważne dla zachowania postępów)

* Identyfikator aplikacji jest stały: `pl.czytamsam.app`. Baza ma migracje schematu – aktualizacja **nie usuwa danych**,
  o ile nowa wersja jest podpisana **tym samym kluczem**.
* Obecne APK z GitHub Actions są podpisane **jawnym kluczem testowym** zapisanym w repozytorium
  (`android/keystore/czytamsam-public-test.jks`). Jest on stały, więc kolejne wersje testowe aktualizują się
  z zachowaniem danych, **ale nie jest tajny** (repozytorium jest publiczne) – teoretycznie ktoś mógłby podpisać nim
  inną aplikację. Instaluj APK tylko z tego repozytorium.
* **Docelowo (zalecane)**: prywatny klucz w GitHub Secrets. Jednorazowo (osoba techniczna):
  1. `keytool -genkeypair -v -keystore czytamsam-release.jks -alias czytamsam -keyalg RSA -keysize 2048 -validity 20000`
  2. Zachowaj plik i hasła w bezpiecznym miejscu (menedżer haseł + kopia offline). Utrata klucza = brak aktualizacji.
  3. W repozytorium: *Settings → Secrets and variables → Actions* dodaj: `CZYTAMSAM_KEYSTORE_BASE64`
     (wynik `base64 -w0 czytamsam-release.jks`), `CZYTAMSAM_KEYSTORE_PASSWORD`, `CZYTAMSAM_KEY_ALIAS`, `CZYTAMSAM_KEY_PASSWORD`.
  4. Workflow sam użyje prywatnego klucza (w raporcie wydania: „Podpis: prywatny”).
* **Zmiana klucza (z testowego na prywatny) wymaga jednorazowej reinstalacji**: najpierw **Eksportuj kopię**,
  odinstaluj starą wersję, zainstaluj nową, **Importuj kopię**. Później aktualizacje działają już normalnie.

## 8. Dla programisty

```bash
cd czytam_sam
flutter pub get --enforce-lockfile
dart run tool/validate_content.dart   # walidacja materiału
flutter analyze
flutter test
flutter build apk --release           # wymaga Android SDK
```

Struktura: `lib/content` (materiał, tokenizator grafemów, walidator), `lib/engine` (opanowanie, odblokowanie,
dobór zadań, sesja, polityka oceny mowy, raport), `lib/data` (SQLite + migracje, kopia), `lib/services`
(lektor, mikrofon/Vosk), `lib/ui` (ekrany), `android/app/src/main/kotlin/.../MainActivity.kt` (kanał Vosk),
`assets/content/*.json` (materiał dydaktyczny – źródło prawdy; `tool/gen_content.py` to skrypt, którym materiał
został pierwotnie wygenerowany), `test/` (testy odbiorcze 01–24 + scenariusz), `.github/workflows/android.yml` (CI).
Wersje zależności są przypięte (`pubspec.yaml` + `pubspec.lock`, CI: `--enforce-lockfile`, Flutter 3.50.0).

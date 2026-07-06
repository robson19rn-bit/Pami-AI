# SessionKeeper APK — MVP v0.1

## 1. Ocena wykonalności: czy Accessibility Service widzi tekst z aplikacji AI?

**Krótka odpowiedź: mechanizm jest technicznie poprawny i ogólnie działa dla standardowych
widoków Androida, ale konkretne zachowanie dla ChatGPT/Claude/Gemini/Copilot wymaga
weryfikacji na Twoim urządzeniu — nie da się tego potwierdzić zdalnie bez testu.**

### Co wiem z wysoką pewnością (mechanizm platformy Android)

- `AccessibilityService.getRootInActiveWindow()` + rekurencyjne przejście po
  `AccessibilityNodeInfo.getChild(i)` to standardowy, udokumentowany sposób odczytu
  tekstu z dowolnej aplikacji — to ten sam mechanizm, na którym działa TalkBack.
- Standardowe widoki (`TextView`, listy oparte o `RecyclerView` z `TextView`) **domyślnie**
  eksponują swój tekst przez `getText()` do drzewa dostępności.
- Jetpack Compose (`Text()`) **domyślnie** generuje węzły semantyki z tekstem, chyba że
  deweloper świadomie je ukryje (rzadkie dla treści wiadomości — zepsułoby to TalkBack).
- Google Play (wpis ChatGPT) sam wspomina o funkcji "Screen share with Accessibility
  Services" — to nie potwierdza wprost, że MY odczytamy treść wiadomości, ale pokazuje,
  że mechanizm dostępności jest w tej aplikacji aktywnie używany, więc nie jest
  celowo zablokowany.

### Co jest realnym ryzykiem (niepewne bez testu)

1. **Wirtualizacja list.** Czaty renderują wiadomości w listach, które wypełniają tylko
   widoczny fragment ekranu. Jeśli blok `[SESSIONKEEPER_STATE]` jest dłuższy niż to,
   co mieści się na ekranie na raz, w drzewie dostępności może być tylko część bloku
   w danym momencie. Krótki blok (10–15 linii) często zmieści się na jednym ekranie
   telefonu, ale nie jest to gwarantowane przy większej czcionce czy dłuższych polach.
2. **WebView.** Jeśli którakolwiek z aplikacji renderuje treść czatu przez WebView
   zamiast natywnych widoków/Compose, dostępność DOM-u bywa niepełna, zwłaszcza dla
   treści ładowanej dynamicznie.
3. **Restricted settings (Android 13+).** Aplikacje sideloadowane (poza Google Play)
   mają domyślnie zablokowaną możliwość włączenia Accessibility Service — przełącznik
   jest wyszarzony z komunikatem "ze względów bezpieczeństwa ta opcja jest obecnie
   niedostępna". Trzeba: Ustawienia → Aplikacje → SessionKeeper → menu (⋮) →
   **"Zezwól na ograniczone ustawienia"** → dopiero wtedy przełącznik w Ustawieniach
   dostępności staje się klikalny. To dotyczy Androida 13/14/15 (potwierdzone
   źródłowo, stan na 2026). Na Samsungach z Auto Blocker może być dodatkowy krok
   (wyłączenie Auto Blockera).
4. **Zachowanie konkretnej aplikacji jest nieznane.** Nie mam możliwości zainstalowania
   ChatGPT/Claude/Gemini/Copilot i sprawdzenia ich drzewa widoków w tym środowisku.

### Jak to sprawdzić empirycznie (zrób to jako pierwszy krok)

W aplikacji jest wbudowany ekran **Diagnostyka** (`MainActivity`, sekcja "Diagnostyka"),
zasilany przez `DebugBridge` — pokazuje log ostatnich skanów (co widziała usługa, z jakiej
aplikacji, kiedy) oraz treść ostatniego wykrytego pełnego bloku, niezależnie od tego, czy
został on zapisany do archiwum (żeby odróżnić "nie wykryto" od "wykryto, ale to duplikat").

Jeśli testujesz przez przeglądarkę albo aplikację spoza domyślnej listy
(`com.openai.chatgpt`, `com.anthropic.claude`, `com.google.android.apps.bard`,
`com.microsoft.copilot`) — w tej samej sekcji jest checkbox **"Wyłącz filtr pakietów"**
(obserwuj wszystko, tryb testowy) oraz pole na dodatkowe nazwy pakietów po przecinku
(np. `com.android.chrome`).

1. Zbuduj i zainstaluj APK (patrz sekcja 4 niżej).
2. Włącz Accessibility Service (patrz ryzyko nr 3 wyżej — potrzebne "Zezwól na
   ograniczone ustawienia").
3. Na czas pierwszego testu zaznacz "Wyłącz filtr pakietów" i kliknij "Zapisz ustawienia
   filtra" — eliminuje to zmienną "zła nazwa pakietu" z pierwszego testu.
4. Otwórz ChatGPT/Claude/Gemini/Copilot, wklej **testowy** blok `[SESSIONKEEPER_STATE]`
   jako zwykłą wiadomość (nawet do siebie, treść wiadomości nie musi pochodzić od AI —
   liczy się czy Accessibility widzi tekst na ekranie).
5. Wróć do SessionKeeper, kliknij "Odśwież podgląd" w sekcji Diagnostyka.
6. Jeśli w logu skanów widzisz treść ekranu, a w "ostatni wykryty pełny blok" treść
   Twojego testowego bloku — mechanizm działa. Jeśli log skanów jest pusty — problem
   jest wcześniej (usługa nieaktywna albo aplikacja poza filtrem). Jeśli log skanów ma
   treść, ale "ostatni wykryty blok" jest pusty — blok nie zmieścił się w całości na
   ekranie (wirtualizacja) albo tagi się nie domknęły.

To jest właśnie różnica między "sądzę, że powinno działać" a "sprawdzone" — zgodnie z
Twoją zasadą krytyczną, nie twierdzę że to działa dla konkretnych aplikacji, dopóki
tego nie zobaczysz na własnym urządzeniu.

---

## 2. Architektura (minimalna)

```
AccessibilityEvent (co ~0.5s, debounced)
        │
        ▼
scanActiveWindow()  ── zbiera cały widoczny tekst z drzewa węzłów
        │
        ├──► DebugBridge.update()          (zawsze — do ekranu Diagnostyka)
        │
        ▼
StateBlockParser.extractFirstFullBlock()   (szuka [SESSIONKEEPER_STATE]...[/...])
        │  (null → koniec, czekamy na kolejne zdarzenie)
        ▼
StateBlockParser.parse()                   (rozbija na pola, tolerancyjnie)
        │
        ▼
LocalStore.load() → aktualizacja Project (Snapshot + Archive) → LocalStore.save()
        │
        ▼
Toast "SessionKeeper: zapisano stan projektu"
```

`MainActivity` i `SessionKeeperAccessibilityService` działają w tym samym procesie
aplikacji (nie ma `android:process` w manifeście), więc `DebugBridge` to zwykły
obiekt w pamięci — bez potrzeby IPC.

## 3. Struktura plików

```
SessionKeeperApk/
├── settings.gradle.kts
├── build.gradle.kts
├── gradle.properties
├── gradle/wrapper/gradle-wrapper.properties
└── app/
    ├── build.gradle.kts
    ├── proguard-rules.pro
    └── src/main/
        ├── AndroidManifest.xml
        ├── res/
        │   ├── xml/accessibility_service_config.xml
        │   ├── values/strings.xml
        │   ├── values/styles.xml
        │   └── layout/activity_main.xml
        └── java/com/sessionkeeper/app/
            ├── MainActivity.kt
            ├── SessionKeeperAccessibilityService.kt   ← główny mechanizm
            ├── StateBlockParser.kt                     ← port parsera z wersji HTML
            ├── LocalStore.kt                           ← zapis lokalny (plik JSON)
            ├── RestartPromptBuilder.kt
            ├── DebugBridge.kt                          ← most diagnostyczny
            ├── DiagnosticSettings.kt                    ← ustawienia filtra (tryb testowy)
            ├── DateUtils.kt
            └── model/Models.kt                         ← Project, Snapshot, Archive, AppState
```

## 4. Budowanie APK

**Ważne — brakujący Gradle Wrapper (potwierdzona luka z audytu):** w paczce jest
`gradle/wrapper/gradle-wrapper.properties`, ale **nie ma** `gradlew`, `gradlew.bat` ani
`gradle/wrapper/gradle-wrapper.jar`. Sprawdziłem wprost w tym środowisku: nie ma tu
lokalnie zainstalowanego Gradle, nie ma `javac`/`jar` (tylko JRE, nie pełny JDK), a
`services.gradle.org` jest zablokowane na poziomie sieci (403). Nie mogę więc uczciwie
wygenerować ani pobrać prawdziwego, poprawnego `gradle-wrapper.jar` — to plik binarny ze
skompilowanego bajtkodu konkretnej wersji Gradle, nie coś, co powinienem "odtwarzać z
pamięci". Zamiast zgadywać, dwie pewne ścieżki naprawy (obie zajmują sekundy po Twojej
stronie, gdzie masz i internet, i/albo Android Studio):

- **Najprościej:** Android Studio nie potrzebuje wrappera do otwarcia projektu — użyje
  własnego, wbudowanego Gradle. Przy `File → Open` i pierwszym sync może sam zaproponować
  wygenerowanie brakującego wrappera, albo zrobisz to ręcznie z zakładki *Terminal* w
  Android Studio (patrz punkt niżej).
- **Jeśli zależy Ci na `./gradlew assembleDebug` z linii poleceń:** zainstaluj Gradle
  (albo skorzystaj z tego wbudowanego w Android Studio) i w folderze projektu uruchom
  jednorazowo:
  ```
  gradle wrapper --gradle-version 8.7
  ```
  To wygeneruje poprawne, zweryfikowane `gradlew`, `gradlew.bat` i `gradle-wrapper.jar`
  dokładnie dopasowane do wersji 8.7 — szybciej i pewniej, niż gdybym próbował je tutaj
  odtworzyć bez możliwości przetestowania.

Dalsze kroki budowania:

1. Zainstaluj Android Studio (jeśli nie masz): https://developer.android.com/studio
2. `File → Open` → wskaż rozpakowany folder `SessionKeeperApk`.
3. Poczekaj na "Gradle Sync". Jeśli Android Studio zaproponuje upgrade Gradle/AGP —
   możesz zaakceptować, projekt użył celowo nieco starszych, sprawdzonych wersji
   (AGP 8.6, Kotlin 2.0), żeby zminimalizować ryzyko niezgodności, których nie mogłem
   tu przetestować kompilacją.
4. Podłącz telefon przez USB z włączonym USB debugging (Ustawienia → opcje
   programistyczne), albo użyj emulatora.
5. `Run ▶` (zielony trójkąt) — zainstaluje i uruchomi debug-owy build na urządzeniu.
6. Włącz usługę dostępności (patrz sekcja 1, ryzyko nr 3 — "Zezwól na ograniczone
   ustawienia" jest konieczne dla wersji zainstalowanej z Android Studio, bo to też
   jest technicznie "sideload").

## 5. Lista ryzyk technicznych

| # | Ryzyko | Wpływ | Status |
|---|---|---|---|
| 1 | Czy AI-app eksponuje pełny tekst wiadomości przez Accessibility | Krytyczny — bez tego cały mechanizm nie działa | DO WERYFIKACJI na urządzeniu (patrz Diagnostyka) |
| 2 | Wirtualizacja długich list — blok może być "obcięty" na ekranie | Wysoki | DO WERYFIKACJI; fallback: programowe przewijanie i sklejanie (poza zakresem MVP) |
| 3 | Android 13+ restricted settings dla sideloadowanych apek | Średni — dodatkowy krok w onboardingu, nie blokuje funkcji | Udokumentowane, obsłużone opisowo |
| 4 | Zużycie baterii przy stałym nasłuchu | Średni | Ograniczone filtrem pakietów + debounce 500ms |
| 5 | Duplikaty zapisu tego samego bloku (event fires wielokrotnie) | Niski | Obsłużone przez `lastProcessedBlockHash` |
| 6 | Nazwy pakietów aplikacji AI mogą się zmienić przy rebrandingu | Niski | Zweryfikowane wyszukiwaniem na dziś: `com.openai.chatgpt`, `com.anthropic.claude`, `com.google.android.apps.bard`, `com.microsoft.copilot` |
| 7 | Wersje Gradle/AGP/Kotlin są ruchomym celem (AGP już w linii 9.x) | Niski dla działania, średni dla "świeżości" | Świadomie użyto starszych, stabilnych wersji zamiast zgadywać składnię AGP 9.x |

## 6. Status znanych braków z audytu

**Zamknięte w tej wersji (kod, nie tylko deklaracja):**

1. ✅ **Warstwa Active Session.** `Project.activeSession: String` w modelu (`Models.kt`,
   z toJson/fromJson) + sekcja "Sesja robocza (Warstwa 1)" w `MainActivity` z polem
   notatek i przyciskami Zapisz/Wyczyść. Celowo NIE wchodzi do `RestartPromptBuilder`
   (prompt/Markdown) — tylko do pełnego backupu JSON, tak samo jak w wersji HTML.
2. ✅ **Eksport/import backupu JSON w UI.** Przyciski "Eksportuj/Importuj backup JSON"
   przez Storage Access Framework (`ActivityResultContracts.CreateDocument` /
   `OpenDocument`) — bez dodatkowych uprawnień w manifeście. Import pyta o
   potwierdzenie przed nadpisaniem danych.
3. ✅ **Usuwanie pojedynczych wpisów archiwum.** Archiwum to teraz dynamicznie
   generowana lista wierszy (`llArchiveEntries`), każdy z przyciskiem "Usuń" +
   potwierdzeniem, zamiast jednego bloku tekstu tylko do odczytu.
4. ✅ **Przełącznik `autoCreateProjectFromBlock`.** Checkbox w sekcji Projekt,
   zapisywany natychmiast po zmianie.

**Nadal otwarte — bez zmian względem poprzedniej wersji:**

5. ❌ **Gradle Wrapper (`gradlew`, `gradlew.bat`, `gradle-wrapper.jar`).** Ten sam
   udokumentowany wcześniej powód: brak lokalnego Gradle, brak `javac`/`jar`, sieć do
   `services.gradle.org` zablokowana w tym środowisku (potwierdzone ponownie). Ścieżka
   naprawy bez zmian — sekcja 4 wyżej (Android Studio albo `gradle wrapper
   --gradle-version 8.7` jednorazowo po Twojej stronie).

Punkty 1–4 nie były jeszcze testowane kompilacją (patrz ograniczenia środowiska w
sekcji 4) — zweryfikowałem składnię XML, zgodność ID między layoutem a kodem (skryptem,
nie wzrokiem) i spójność modelu danych, ale realna kompilacja Gradle wciąż czeka na
Twoje Android Studio.

## 7. Weryfikacja błędów (ta wersja) — co znalazłem i co z tym zrobiłem

Przegląd nie ograniczał się do składni (którą już wcześniej sprawdzałem skryptami) —
celowo szukałem błędów logicznych i przepływu danych.

**Naprawione:**

1. **Nieświeży UI po "Odśwież podgląd".** Przycisk w Diagnostyce odświeżał tylko log
   skanów, nie Snapshot/Archiwum/status bar. Gdyby usługa zapisała blok w tle, a
   użytkownik nie opuścił aplikacji (więc `onResume()` się nie wywołał), zobaczyłby
   nowy tekst w logu diagnostycznym, ale STARE dane w Archiwum/Snapshot — myląco
   wyglądałoby to jak częściowa awaria. Naprawione: przycisk przeładowuje teraz cały
   stan z dysku.
2. **Efekt uboczny powyższej poprawki.** Naiwna naprawa (użycie tej samej funkcji co
   przy zmianie projektu) czyściłaby już wygenerowany prompt restartowy przy każdym
   kliknięciu "Odśwież podgląd". Rozdzieliłem `loadActiveProjectIntoFields()`
   (czyści prompt — właściwe przy zmianie projektu) od nowego
   `refreshFieldsFromState()` (nie czyści promptu — właściwe przy zwykłym odświeżeniu).
3. **Race condition / lost update między Activity a usługą (poważniejszy).**
   `MainActivity` trzymała `state` wczytany raz przy starcie/ostatnim odświeżeniu.
   Jeśli `SessionKeeperAccessibilityService` zapisała nowy blok w tle, a użytkownik
   akurat kliknął "Zapisz Snapshot"/"Zapisz Pamięć"/"Zapisz notatki"/"Usuń wpis
   archiwum" — zapis z Activity nadpisywałby CAŁY plik swoją starszą kopią, kasując
   auto-przechwycony wpis. To realny scenariusz właśnie w teście krytycznym (usługa
   działa w tle niezależnie od tego, co robisz w UI). Naprawione przez
   `mutateActiveProjectAndSave()` — przeładowuje stan z dysku tuż przed każdym z tych
   czterech zapisów i nakłada zmianę na świeże dane, nie na starą kopię w pamięci.

**Znalezione, świadomie NIE naprawione (i dlaczego):**

4. **Zapis/odczyt pliku na wątku głównym w `SessionKeeperAccessibilityService`.**
   `LocalStore.load/save` wykonują synchroniczne I/O na głównym wątku (bo debounce
   też działa przez `Looper.getMainLooper()`). Dla małego pliku JSON i rzadkich zdarzeń
   (tylko gdy wykryto pełny blok, nie przy każdym skanie) ryzyko realnego zacięcia UI
   jest niskie, ale to nie jest best practice. Przeniesienie na wątek w tle dodałoby
   złożoność (koordynacja z Handlerem, ryzyko nowych błędów współbieżności), której nie
   mogę tu przetestować kompilacją — odłożone, niekrytyczne dla testu wykrywania.
5. **Wąski przypadek brzegowy: `autoCreateProjectFromBlock` + edycja w tle.** Jeśli
   usługa auto-utworzy i przełączy się na nowy projekt DOKŁADNIE w momencie, gdy
   użytkownik edytuje inny projekt na ekranie i klika Zapisz, `mutateActiveProjectAndSave`
   przywróci poprzednio aktywny projekt (ten widoczny na ekranie) jako aktywny,
   nadpisując wybór usługi. Bardzo wąski przypadek (wymaga dwóch rzeczy naraz:
   auto-create ORAZ jednoczesnej edycji), a `autoCreateProjectFromBlock` domyślnie
   jest wyłączone — odłożone jako nieistotne dla planowanego testu.

## 8. Czego świadomie NIE ma w tym MVP (zgodnie ze specyfikacją)

Room/baza danych, OCR, Git, agenci, chmura, konta użytkowników, logowanie,
synchronizacja, integracja API modeli AI, osobne ekrany/Nawigacja (wszystko w jednym
`MainActivity`), automatyczne przewijanie długich list. Wszystko to zostaje w backlogu
do rozważenia dopiero po potwierdzeniu, że podstawowy mechanizm wykrywania działa na
Twoich aplikacjach.
